// Minimal Chrome DevTools Protocol client (Node 22+ has a built-in WebSocket; nothing to install).
//   const tab = await openTab(9333, "https://...");  await tab.shot("out.png");  tab.close();
import fs from "node:fs";

export const sleep = ms => new Promise(r => setTimeout(r, ms));

export class Tab {
  constructor(ws) {
    this.ws = ws; this.id = 0; this.pending = new Map(); this.handlers = new Map(); this.inflight = new Set();
    ws.onmessage = e => {
      const m = JSON.parse(e.data);
      if (m.id && this.pending.has(m.id)) {
        const { res, rej } = this.pending.get(m.id); this.pending.delete(m.id);
        m.error ? rej(new Error(`${m.error.message} (${m.error.code})`)) : res(m.result);
      } else if (m.method) (this.handlers.get(m.method) || []).forEach(h => h(m.params));
    };
  }
  send(method, params = {}) {
    const id = ++this.id;
    return new Promise((res, rej) => { this.pending.set(id, { res, rej }); this.ws.send(JSON.stringify({ id, method, params })); });
  }
  on(method, h) { this.handlers.set(method, [...(this.handlers.get(method) || []), h]); }
  async init({ width = 1600, height = 900, scale = 2 } = {}) {
    await this.send("Page.enable"); await this.send("Runtime.enable"); await this.send("Network.enable");
    this.on("Network.requestWillBeSent", p => this.inflight.add(p.requestId));
    for (const ev of ["Network.loadingFinished", "Network.loadingFailed"]) this.on(ev, p => this.inflight.delete(p.requestId));
    await this.size(width, height, scale);
    return this;
  }
  size(width, height, scale = 2) {
    this.dim = { width, height, scale };
    return this.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: scale, mobile: false });
  }
  async eval(expr) {
    const r = await this.send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
    return r.result.value;
  }
  async go(url, { settle = 1500, text = null, timeout = 8000 } = {}) {
    this.inflight.clear();
    await this.send("Page.navigate", { url });
    await this.idle({ settle, timeout });
    if (text) await this.waitText(text, timeout);
    await sleep(settle);
  }
  async idle({ settle = 1200, timeout = 8000 } = {}) {  // network quiet for `settle` ms (polling pages: give up at timeout)
    const t0 = Date.now(); let quietSince = Date.now();
    while (Date.now() - t0 < timeout) {
      if (this.inflight.size > 0) quietSince = Date.now();
      else if (Date.now() - quietSince >= settle) return true;
      await sleep(100);
    }
    return false;
  }
  async waitText(text, timeout = 25000) {
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      if (await this.eval(`document.body && document.body.innerText.includes(${JSON.stringify(text)})`)) return true;
      await sleep(250);
    }
    throw new Error(`text not found: ${text}`);
  }
  async click(text, { selector = "a,button,[role=tab],[role=button],[role=menuitem],li,span,div", exact = true, nth = 0 } = {}) {
    // click the innermost visible element whose text matches
    const ok = await this.eval(`(() => {
      const want = ${JSON.stringify(text)}, exact = ${exact};
      const els = [...document.querySelectorAll(${JSON.stringify(selector)})].filter(e => {
        const t = (e.innerText || "").trim(); const r = e.getBoundingClientRect();
        return r.width > 0 && r.height > 0 && (exact ? t === want : t.includes(want));
      });
      const inner = els.filter(e => !els.some(o => o !== e && e.contains(o)));
      const el = inner[${nth}]; if (!el) return false; el.scrollIntoView({block: "center"}); el.click(); return true; })()`);
    if (!ok) throw new Error(`nothing to click: ${text}`);
    await sleep(400); await this.idle({ settle: 900 });
  }
  async box(text, { selector = "*", exact = false, nth = 0, pad = 8 } = {}) {  // CSS-pixel box of an element, for callouts
    return this.eval(`(() => {
      const want = ${JSON.stringify(text)}, exact = ${exact};
      const els = [...document.querySelectorAll(${JSON.stringify(selector)})].filter(e => {
        const t = (e.innerText || "").trim(); const r = e.getBoundingClientRect();
        return r.width > 0 && r.height > 0 && (exact ? t === want : t.includes(want));
      });
      const inner = els.filter(e => !els.some(o => o !== e && e.contains(o)));
      const el = inner[${nth}]; if (!el) return null; const r = el.getBoundingClientRect(), p = ${pad};
      return { x: r.x - p, y: r.y - p, w: r.width + 2 * p, h: r.height + 2 * p }; })()`);
  }
  async shot(path, { clip = null, format = "png" } = {}) {
    const params = { format, captureBeyondViewport: false };
    if (clip) params.clip = { ...clip, scale: 1 };
    const { data } = await this.send("Page.captureScreenshot", params);
    fs.writeFileSync(path, Buffer.from(data, "base64"));
    return path;
  }
  close() { try { this.ws.close(); } catch {} }
}

export async function connect(wsUrl) {
  const ws = new WebSocket(wsUrl);
  await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
  return new Tab(ws);
}

export async function targets(port) {
  return (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
}

export async function openTab(port, url = "about:blank", opts = {}) {
  const t = await (await fetch(`http://127.0.0.1:${port}/json/new?${encodeURIComponent(url)}`, { method: "PUT" })).json();
  const tab = await (await connect(t.webSocketDebuggerUrl)).init(opts);
  tab.targetId = t.id; tab.port = port;
  return tab;
}

export async function attach(port, match, opts = {}) {  // attach to an existing page whose URL contains `match`
  const t = (await targets(port)).find(x => x.type === "page" && x.url.includes(match));
  if (!t) throw new Error(`no page matching ${match}`);
  const tab = await (await connect(t.webSocketDebuggerUrl)).init(opts);
  tab.targetId = t.id; tab.port = port;
  return tab;
}

// GNB Assist sessions for screenshots and recordings: one headless Chrome (:9340), one isolated browser context per persona,
// each signed in with its test account (read from webui/.personas.env here; never printed).
//   import { persona } from "./gnb.mjs";  const aisha = await persona("aisha");  await aisha.go("/"); await aisha.shot("x.png");
import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";
import { connect, sleep } from "./cdp.mjs";

const HERE = path.dirname(new URL(import.meta.url).pathname);
const SCEN = path.resolve(HERE, "../..");
export const WEBUI = "http://localhost:3000";
const PORT = 9340;
const env = Object.fromEntries([...fs.readFileSync(path.join(SCEN, "webui/.personas.env"), "utf8").matchAll(/^(\w+)=(.*)$/gm)].map(m => [m[1], m[2]]));
export const PERSONAS = {
  aisha: ["aisha.retail@gnb.test", "PW_AISHA"], layla: ["layla.aml@gnb.test", "PW_LAYLA"], omar: ["omar.complaints@gnb.test", "PW_OMAR"],
  noura: ["noura.cardops@gnb.test", "PW_NOURA"], khalid: ["khalid.supervisor@gnb.test", "PW_KHALID"], admin: [env.WEBUI_ADMIN_EMAIL, "WEBUI_ADMIN_PASSWORD"],
};

async function browser() {
  const v = async () => (await fetch(`http://127.0.0.1:${PORT}/json/version`)).json();
  let info = await v().catch(() => null);
  if (!info) {
    spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", ["--headless=new", `--remote-debugging-port=${PORT}`,
      `--user-data-dir=${path.join(SCEN, "video/build/.gnb-profile")}`, "--hide-scrollbars", "--force-color-profile=srgb", "--mute-audio", "about:blank"],
      { detached: true, stdio: "ignore" }).unref();
    for (let i = 0; i < 40 && !info; i++) { await sleep(250); info = await v().catch(() => null); }
  }
  return connect(info.webSocketDebuggerUrl);
}

// session tokens reused across runs (Open WebUI allows 15 sign-ins per account per 3 minutes); shared with scripts/check.py
const CACHE = path.resolve(SCEN, "../run/gnb-assist/tokens.json");
export async function token(who) {
  const [email, pw] = PERSONAS[who];
  const cache = fs.existsSync(CACHE) ? JSON.parse(fs.readFileSync(CACHE, "utf8")) : {};
  if (cache[email]) {
    const ok = await fetch(`${WEBUI}/api/v1/auths/`, { headers: { Authorization: `Bearer ${cache[email]}` } }).then(r => r.ok).catch(() => false);
    if (ok) return cache[email];
  }
  const r = await fetch(`${WEBUI}/api/v1/auths/signin`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email, password: env[pw] }) });
  if (!r.ok) throw new Error(`sign-in failed for ${who}: ${r.status}`);
  cache[email] = (await r.json()).token;
  fs.mkdirSync(path.dirname(CACHE), { recursive: true }); fs.writeFileSync(CACHE, JSON.stringify(cache));
  return cache[email];
}

// a signed-in tab for a persona, in its own browser context (its own localStorage and cookies)
export async function persona(who, { width = 1280, height = 900, scale = 2 } = {}) {
  const b = await browser();
  const { browserContextId } = await b.send("Target.createBrowserContext", { disposeOnDetach: false });
  const { targetId } = await b.send("Target.createTarget", { url: "about:blank", browserContextId });
  const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();
  const t = await connect(list.find(x => x.id === targetId).webSocketDebuggerUrl);
  await t.init({ width, height, scale });
  const tok = await token(who);
  await t.go(WEBUI + "/auth", { settle: 600 });
  await t.eval(`localStorage.setItem("token", ${JSON.stringify(tok)}); true`);
  await t.go(WEBUI + "/", { settle: 1200 });
  t.who = who; t.browser = b; t.contextId = browserContextId; t.targetId = targetId;
  t.close = async () => { try { await b.send("Target.disposeBrowserContext", { browserContextId }); } catch {} try { b.ws.close(); } catch {} };
  return t;
}

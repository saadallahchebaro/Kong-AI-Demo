// A Chrome app window (no address bar, its own profile under run/gnb-assist/) at a given place on screen; reused if it's already open.
//   node window.mjs <name> <port> <url> [x,y,w,h] [--exact]   (open-persona.mjs and panes.sh use it)
//   --exact: an open window that shows another page is sent to <url>;  --front: bring the window to the front
import path from "node:path";
import { spawn } from "node:child_process";
import { connect, sleep } from "./tools/cdp.mjs";

const REPO = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const json = (port, p) => fetch(`http://127.0.0.1:${port}/json/${p}`).then(r => r.json()).catch(() => null);

export async function appWindow(name, port, url, bounds, { exact = false, front = false } = {}) {
  const origin = new URL(url).origin, find = async () => {  // the window's page: on the site, else any (each window is its own Chrome)
    const pages = ((await json(port, "list")) || []).filter(t => t.type === "page");
    return pages.find(t => t.url.startsWith(origin)) || pages.find(t => !t.url.startsWith("chrome://newtab"));
  };
  let page = await find(), fresh = !page;
  if (fresh) {
    const at = bounds ? [`--window-position=${bounds[0]},${bounds[1]}`, `--window-size=${bounds[2]},${bounds[3]}`] : ["--window-size=1280,900"];
    spawn("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", [`--user-data-dir=${path.join(REPO, "run/gnb-assist", name)}`,
      `--remote-debugging-port=${port}`, "--no-first-run", "--no-default-browser-check", `--app=${url}`, ...at], { detached: true, stdio: "ignore" }).unref();
    for (let i = 0; i < 60 && !page; i++) { await sleep(250); page = await find(); }
    if (!page) throw new Error(`the ${name} window didn't open`);
  }
  // a blank new-tab window (Chrome opens one when it's relaunched with its windows closed) never belongs on the stage
  for (const t of ((await json(port, "list")) || []).filter(t => t.type === "page" && t.url.startsWith("chrome://newtab"))) await json(port, `close/${t.id}`);
  if (!fresh && exact && page.url !== url) {
    const t = await connect(page.webSocketDebuggerUrl); await t.send("Page.navigate", { url }); t.close(); page.url = url;
  }
  if (bounds) {  // place it (also when it was already open)
    const b = await connect((await json(port, "version")).webSocketDebuggerUrl);
    const { windowId } = await b.send("Browser.getWindowForTarget", { targetId: page.id });
    await b.send("Browser.setWindowBounds", { windowId, bounds: { windowState: "normal" } });
    await b.send("Browser.setWindowBounds", { windowId, bounds: { left: bounds[0], top: bounds[1], width: bounds[2], height: bounds[3] } });
    b.close();
  }
  if (front) { const t = await connect(page.webSocketDebuggerUrl); await t.send("Page.bringToFront"); t.close(); }
  return { ...page, fresh };
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const args = process.argv.slice(2), exact = args.includes("--exact"), front = args.includes("--front"), [name, port, url, at] = args.filter(a => !a.startsWith("--"));
  await appWindow(name, Number(port), url, at ? at.split(",").map(Number) : null, { exact, front });
  process.exit(0);
}

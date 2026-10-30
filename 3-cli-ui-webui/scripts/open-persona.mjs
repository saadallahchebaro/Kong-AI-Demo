// A visible GNB Assist window for one persona: Chrome in app mode (no address bar), its own profile under run/gnb-assist/,
// signed in with the persona's test account (the token is set over CDP; no password typed or shown).
//   node open-persona.mjs <persona> [x,y,w,h] [model]   (open.sh, stage.sh); an open window is reused, moved and brought to the front,
//   its chat left as is; with a model id, it starts a new chat with that assistant
import { connect } from "./tools/cdp.mjs";
import { token, WEBUI, PERSONAS } from "./tools/gnb.mjs";
import { appWindow } from "./window.mjs";

const [who, at, model] = process.argv.slice(2);
if (!PERSONAS[who]) { console.error("unknown persona", who); process.exit(2); }
const page = await appWindow(who, 9350 + Object.keys(PERSONAS).indexOf(who), `${WEBUI}/auth`, at ? at.split(",").map(Number) : null, { front: true });
const t = await connect(page.webSocketDebuggerUrl);
await t.send("Runtime.enable");
const home = model ? `/?models=${encodeURIComponent(model)}` : "/";   // ?models=: a new chat with that assistant selected
if (page.fresh || !(await t.eval(`!!localStorage.getItem("token")`)))
  await t.eval(`localStorage.setItem("token", ${JSON.stringify(await token(who))}); location.href = ${JSON.stringify(home)}; true`);
else if (model) await t.eval(`location.href = ${JSON.stringify(home)}; true`);
console.log(`GNB Assist open as ${who} (${PERSONAS[who][0]})`);
t.close(); process.exit(0);

// After a reset: every open GNB Assist persona window goes back to a new, empty chat (reset.sh deletes the chats; open
// windows would still show them). Windows that aren't open are left alone.
import { connect } from "./tools/cdp.mjs";
import { WEBUI, PERSONAS } from "./tools/gnb.mjs";

let n = 0;
for (const [i, who] of Object.keys(PERSONAS).entries()) {
  const page = await fetch(`http://127.0.0.1:${9350 + i}/json/list`).then(r => r.json()).then(l => l.find(t => t.type === "page" && t.url.startsWith(WEBUI))).catch(() => null);
  if (!page) continue;
  const t = await connect(page.webSocketDebuggerUrl);
  await t.send("Page.navigate", { url: `${WEBUI}/` }); t.close(); n++;
}
console.log(n ? `✓ ${n} GNB Assist window(s) back to a new chat` : "no GNB Assist windows open");
process.exit(0);

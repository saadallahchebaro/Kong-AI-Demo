// The Konnect window for the shared screen: Chrome in app mode with its own profile (run/gnb-assist/konnect), where you sign in
// to Konnect once. It sits at GNB Assist's spot (run/gnb-assist/stage.json, written by stage.sh).
//   node konnect.mjs          open it, or put it back in place, without changing its page or bringing it forward (stage.sh)
//   node konnect.mjs <url>    show that Konnect page in it, in front (the Run tab's Konnect shortcuts)
// Exit 3: the window is on Konnect's sign-in page, not signed in yet.
import fs from "node:fs";
import path from "node:path";
import { connect, sleep } from "./tools/cdp.mjs";
import { appWindow } from "./window.mjs";

const REPO = path.resolve(path.dirname(new URL(import.meta.url).pathname), "../..");
const ENVF = path.join(REPO, ".env");   // the gateway and region come from .env (setup.sh writes it)
const ENV = Object.fromEntries((fs.existsSync(ENVF) ? fs.readFileSync(ENVF, "utf8") : "").split("\n")
  .map((l) => l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)).filter(Boolean).map((m) => [m[1], m[2].replace(/^["']|["']$/g, "")]));
const HOME = `https://cloud.konghq.com/${ENV.KONGCTL_DEFAULT_KONNECT_REGION || "eu"}/ai-manager/v2/gateways/${ENV.AI_GATEWAY_ID || ""}`;
const STAGE = path.join(REPO, "run/gnb-assist/stage.json");
const at = fs.existsSync(STAGE) ? JSON.parse(fs.readFileSync(STAGE, "utf8")).assist : null;
const url = process.argv[2];
if (url && !url.startsWith("https://cloud.konghq.com/")) { console.error("not a Konnect page"); process.exit(2); }
const page = await appWindow("konnect", 9348, url || HOME, at, { exact: !!url, front: !!url });
if (!url && !page.fresh) process.exit(0);   // just put back in place: a persona switch doesn't wait for Konnect
const t = await connect(page.webSocketDebuggerUrl);
// Konnect loads the page first and sends a signed-out window to signin.cloud.konghq.com a few seconds later; a signed-in one
// can pass through it too, to refresh its session. So judge the settled page: watch for 5 s at least, until the address has
// held for 1.5 s (12 s at most).
const login = (h, title) => { try { return new URL(h).host !== "cloud.konghq.com" || /^login/i.test(title); } catch { return true; } };
let href = "", title = "", same = 0;
for (let i = 0; i < 48 && !(i >= 20 && same >= 6); i++) {
  await sleep(250);
  const [now, ttl] = await t.eval(`[document.readyState === "complete" ? location.href : "", document.title]`).catch(() => ["", ""]);
  same = now && now === href ? same + 1 : 0; href = now; title = ttl;
}
const signedIn = !!href && !login(href, title);
if (signedIn)  // Konnect's chat bubble stays off the shared screen (as in scenario 2's captures); the app keeps it across its own page changes
  await t.eval(`(() => { if (document.getElementById("gnb-stage-css")) return; const s = document.createElement("style"); s.id = "gnb-stage-css";
    s.textContent = '[class*="chat-launcher"], [id*="intercom"], [class*="intercom"], iframe[title*="chat" i] { display: none !important; }'; document.head.append(s); })()`).catch(() => {});
t.close();
console.log(signedIn ? `Konnect: ${new URL(href).pathname}` : "the Konnect window isn't signed in: sign in there once");
process.exit(signedIn ? 0 : 3);

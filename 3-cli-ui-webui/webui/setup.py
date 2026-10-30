#!/usr/bin/env python3
"""Configure GNB Assist (Open WebUI) for scenario 3, through its admin API. Idempotent: safe to run again.

  python3 3-cli-ui-webui/webui/setup.py

Personas (test accounts, passwords in .personas.env) and what each one sees:
  Aisha  (Retail Banking)      Retail Assistant (gnb-assistant), Retail Copilot (gnb-copilot)   key: retail copilot app
  Layla  (AML)                 AML Copilot (gnb-copilot)                                        key: AML summaries app
  Omar   (Complaints)          Complaints Copilot (gnb-assistant)                               key: complaints copilot app
  Noura  (Card Operations)     Card-ops Agent (gnb-agent-llm + card-services MCP)               key: card-ops agent
  Khalid (Card Ops Supervisor) Card-ops Agent · Supervisor (same agent, supervisor identity)   key: khalid
The four assistants are the GNB AI Gateway pipe (pipe/gnb_gateway.py): the use case's key, the signed-in employee as
X-End-User. The agents are Open WebUI connections + native MCP servers to Kong (legacy tool calling: native tool calls
need streaming, which Kong denies on gnb-agent-llm). Keys come from .env.demo-keys; nothing is printed.
"""
import base64, json, pathlib, re, sys, time, urllib.error, urllib.request

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
WEBUI = "http://localhost:3000"
KONG = "http://host.docker.internal:8000"
env = dict(re.findall(r"^(\w+)=(.*)$", (HERE / ".personas.env").read_text(), re.M))
keys = dict(re.findall(r"^(KEY_\w+)=(.*)$", (REPO / ".env.demo-keys").read_text(), re.M))
VERSION = "0.11.4"

PERSONAS = [  # email, name, password var, group
    ("aisha.retail@gnb.test", "Aisha (Retail Banking)", "PW_AISHA", "Retail Banking"),
    ("layla.aml@gnb.test", "Layla (AML)", "PW_LAYLA", "AML"),
    ("omar.complaints@gnb.test", "Omar (Complaints)", "PW_OMAR", "Complaints"),
    ("noura.cardops@gnb.test", "Noura (Card Operations)", "PW_NOURA", "Card Operations"),
    ("khalid.supervisor@gnb.test", "Khalid (Card Ops Supervisor)", "PW_KHALID", "Card Ops Supervisors"),
]
AGENT_SYSTEM = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', re.search(r'SYSTEM = \((.*?)\)\n', (REPO / "agent/card_ops_agent.py").read_text(), re.S).group(1)))
RETAIL_SYSTEM = ("You are GNB Assist, the internal assistant for GNB retail banking staff in the UAE. Answer in at most three short "
                 "sentences or four short bullet points. Amounts are in AED, and a customer's identity document is the Emirates ID. "
                 "GNB serves customers in its branches, in the GNB mobile app and in online banking.")
AML_SYSTEM = ("You are GNB Assist for GNB's AML analysts in the UAE. Give a concise assessment in at most five short bullet points: "
              "the risk indicators, the risk level, and the next steps.")
COMPLAINTS_SYSTEM = ("You are GNB Assist for GNB's complaints team in the UAE. Draft a short, empathetic reply to the customer in at "
                     "most three sentences, and say what the bank will do next.")
ICON = "data:image/png;base64," + base64.b64encode((HERE / "brand/static/favicon-96x96.png").read_bytes()).decode()
sug = lambda *items: [{"content": c, "title": [t, s]} for t, s, c in items]
MODELS = {  # id: (name, group, description, suggestions, extra params, tool server)
    "gnb_gateway.retail-assistant": ("Retail Assistant", "Retail Banking", "For branch and contact-centre staff · in-country models with DR failover", sug(
        ("What documents do I need", "to open a savings account?", "What documents do I need to open a savings account?"),
        ("A customer complaint", "charged twice for the card fee", "My name is Ahmed Al Mansoori, Emirates ID 784-1990-1234567-1. I was charged twice for my card fee."),
        ("Which stocks should I buy", "with my bonus?", "Which stocks should I buy with my bonus?")), {"system": RETAIL_SYSTEM}, None),
    "gnb_gateway.retail-copilot": ("Retail Copilot", "Retail Banking", "Everyday retail questions · routed to the right-sized model, with a semantic cache", sug(
        ("What time do branches open", "on Saturday?", "What time do branches open on Saturday?"),
        ("What documents do I need", "to open a savings account?", "What documents do I need to open a savings account?"),
        ("Which papers are required", "to open a savings account?", "Which papers are required to open a savings account?")), {"system": RETAIL_SYSTEM}, None),
    "gnb_gateway.aml-copilot": ("AML Copilot", "AML", "Case triage for AML analysts · the large model for analysis", sug(
        ("14 cash deposits of AED 9,500", "across 3 branches in 5 days", "14 cash deposits of AED 9,500 across 3 branches in 5 days. Assess structuring risk and recommend next steps."),), {"system": AML_SYSTEM}, None),
    "gnb_gateway.complaints-copilot": ("Complaints Copilot", "Complaints", "Drafts replies to customer complaints · use case 13", sug(
        ("A customer complaint", "charged twice for the card fee", "My name is Ahmed Al Mansoori, Emirates ID 784-1990-1234567-1. I was charged twice for my card fee."),), {"system": COMPLAINTS_SYSTEM}, None),
    "agent.gnb-agent-llm": ("Card-ops Agent", "Card Operations", "Card operations agent · checks cards and KYC through the card-services API; escalates what it can't do", sug(
        ("Card ending 4242 stolen", "check the card and KYC, then block it", "Customer CUST-1001 says the card ending 4242 was stolen. Check the card and the customer's KYC, then block the card."),),
        {"system": AGENT_SYSTEM, "function_calling": "legacy", "stream_response": False}, "cards-agent"),
    "khalid.gnb-agent-llm": ("Card-ops Agent · Supervisor", "Card Ops Supervisors", "The card operations agent, acting with a supervisor's permissions", sug(
        ("Confirmed stolen", "block card 4242 for CUST-1001", "Confirmed stolen by the customer on a recorded call. Block card 4242 for customer CUST-1001."),),
        {"system": AGENT_SYSTEM, "function_calling": "legacy", "stream_response": False}, "cards-supervisor"),
}


def call(method, path, body=None, token=None, ok=(200,)):
    req = urllib.request.Request(WEBUI + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers={"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if token else {})})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        if e.code in ok:
            return None
        raise SystemExit(f"{method} {path} → {e.code}: {e.read()[:300].decode(errors='replace')}")


def signin(email, password):
    return call("POST", "/api/v1/auths/signin", {"email": email, "password": password})["token"]


def wait_up():
    for _ in range(90):
        try:
            if json.loads(urllib.request.urlopen(WEBUI + "/health", timeout=3).read()).get("status"):
                return
        except Exception:
            pass
        time.sleep(2)
    raise SystemExit("GNB Assist didn't come up on :3000")


wait_up()
admin = signin(env["WEBUI_ADMIN_EMAIL"], env["WEBUI_ADMIN_PASSWORD"])
if "--clear-chats" in sys.argv:  # reset.sh: every persona starts with an empty chat list
    for email, name, pw, _ in PERSONAS:
        call("DELETE", "/api/v1/chats/", token=signin(email, env[pw]))
    print("✓ GNB Assist chats cleared"); sys.exit(0)

# personas
existing = {u["email"]: u for u in (call("GET", "/api/v1/users/all", token=admin) or {}).get("users", [])}
for email, name, pw, _ in PERSONAS:
    if email not in existing:
        call("POST", "/api/v1/auths/add", {"name": name, "email": email, "password": env[pw], "role": "user", "profile_image_url": ""}, admin)
users = {u["email"]: u["id"] for u in call("GET", "/api/v1/users/all", token=admin).get("users", [])}

# groups
groups = {g["name"]: g["id"] for g in call("GET", "/api/v1/groups/", token=admin) or []}
for email, _, _, gname in PERSONAS:
    if gname not in groups:
        groups[gname] = call("POST", "/api/v1/groups/create", {"name": gname, "description": f"GNB {gname}"}, admin)["id"]
    call("POST", f"/api/v1/groups/id/{groups[gname]}/users/add", {"user_ids": [users[email]]}, admin)
grant = lambda g: [{"principal_type": "group", "principal_id": groups[g], "permission": "read"}]

# the agents: two connections to Kong (model), two MCP servers to Kong (tools), one per identity
conns = [("agent", "KEY_CARD_OPS_AGENT"), ("khalid", "KEY_KHALID")]
call("POST", "/openai/config/update", {"ENABLE_OPENAI_API": True, "OPENAI_API_BASE_URLS": [f"{KONG}/v1"] * 2, "OPENAI_API_KEYS": ["unused"] * 2,
     "OPENAI_API_CONFIGS": {str(i): {"enable": True, "prefix_id": p, "model_ids": ["gnb-agent-llm"], "connection_type": "external", "tags": [],
                                     "headers": {"apikey": keys[k], "X-End-User": "{{USER_EMAIL}}"}} for i, (p, k) in enumerate(conns)}}, admin)
servers = [{"url": f"{KONG}/mcp/card-services", "path": "", "type": "mcp", "auth_type": "none", "key": "", "forward_cookies": False,
            "headers": {"apikey": keys[k], "X-End-User": "{{USER_EMAIL}}"}, "config": {"enable": True, "access_grants": grant(g)},
            "info": {"id": sid, "name": name, "description": "GNB card-services API via the GNB AI Gateway (MCP)"}}
           for sid, name, k, g in [("cards-agent", "Card services", "KEY_CARD_OPS_AGENT", "Card Operations"),
                                   ("cards-supervisor", "Card services · supervisor", "KEY_KHALID", "Card Ops Supervisors")]]
call("POST", "/api/v1/configs/tool_servers", {"TOOL_SERVER_CONNECTIONS": servers}, admin)

# the GNB AI Gateway pipe, active, with each use case's app key
code = (HERE / "pipe/gnb_gateway.py").read_text()
fn = {"id": "gnb_gateway", "name": "GNB AI Gateway", "content": code, "meta": {"description": "GNB Assist's use-case assistants, governed by the GNB AI Gateway"}}
if call("GET", "/api/v1/functions/id/gnb_gateway", token=admin, ok=(404, 401)):
    call("POST", "/api/v1/functions/id/gnb_gateway/update", fn, admin)
else:
    call("POST", "/api/v1/functions/create", fn, admin)
if not (call("GET", "/api/v1/functions/id/gnb_gateway", token=admin) or {}).get("is_active"):
    call("POST", "/api/v1/functions/id/gnb_gateway/toggle", None, admin)
call("POST", "/api/v1/functions/id/gnb_gateway/valves/update", {"KONG_URL": f"{KONG}/v1/chat/completions", "KEY_RETAIL": keys["KEY_AISHA"],
     "KEY_AML": keys["KEY_LAYLA"], "KEY_COMPLAINTS": keys["KEY_OMAR"], "SHOW_GATEWAY_STATUS": True, "TIMEOUT_S": 90}, admin)

# each assistant: name, GNB icon, description, prompt suggestions, who may use it
have = {m["id"] for m in call("GET", "/api/v1/models/all", token=admin) or []}
for mid, (name, g, desc, sugg, params, server) in MODELS.items():
    meta = {"profile_image_url": ICON, "description": desc, "suggestion_prompts": sugg, "capabilities": {"vision": False, "file_upload": False, "citations": True}}
    if server:
        meta["toolIds"] = [f"server:mcp:{server}"]
    body = {"id": mid, "base_model_id": None, "name": name, "meta": meta, "params": params, "access_grants": grant(g), "is_active": True}
    call("POST", "/api/v1/models/model/update" if mid in have else "/api/v1/models/create", body, admin)

# each persona: their assistant selected, no "what's new" pop-up, light theme
for email, name, pw, g in PERSONAS:
    t = signin(email, env[pw])
    mine = [m for m, v in MODELS.items() if v[1] == g]
    cur = call("GET", "/api/v1/users/user/settings", token=t) or {}
    ui = {**(cur.get("ui") or {}), "models": mine[:1], "version": VERSION, "theme": "light", "showChangelog": False}
    call("POST", "/api/v1/users/user/settings/update", {**cur, "ui": ui}, t)
    seen = [m["id"] for m in (call("GET", "/api/models", token=t) or {}).get("data", [])]
    print(f"  {name:<30} sees: {', '.join(MODELS[m][0] for m in seen if m in MODELS) or '(none)'}")
print("✓ GNB Assist configured")

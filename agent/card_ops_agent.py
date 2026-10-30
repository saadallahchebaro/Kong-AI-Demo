"""GNB card-ops agent for the demo. Standard library only.

Its model calls go to Kong (gnb-agent-llm: OpenAI gpt-5.5, local 7B fallback) and its tools come from Kong's
AI MCP Server, so both its thinking and its actions are governed by the identity it runs as.

  python3 agent/card_ops_agent.py --as agent  --on-behalf-of noura.cardops "Customer CUST-1001 ... block it."
  python3 agent/card_ops_agent.py --as khalid --on-behalf-of khalid.supervisor "Confirmed stolen. Block card 4242."
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(__file__))
from mcp_client import MCP, MCPHTTPError  # noqa: E402

GW = "http://localhost:8000"
IDENTITIES = {"agent": ("card-ops-agent-01", "KEY_CARD_OPS_AGENT"), "khalid": ("khalid", "KEY_KHALID")}
SYSTEM = ("You are GNB's card-operations agent acting for a bank officer. Check the facts with your tools before "
          "acting. You can only act through the tools you have been given. If the task needs an action you have no "
          "tool for, do not pretend to do it: call escalate_to_supervisor with the reason, then tell the officer the case "
          "number. Never say you will do something you have no tool for. Before your final answer, check that every "
          "action the officer asked for was done with a tool; if one was not, call escalate_to_supervisor first. "
          "Keep the final answer to two sentences.")
SELF_CHECK = ("Self-check. The tools Kong grants you are exactly: {tools}. Compare them with every action the "
              "officer asked for. If the officer asked for an action that none of these tools performs, your next "
              "message must be a call to escalate_to_supervisor with the reason. If every requested action was completed "
              "by a tool call, give your final two-sentence answer to the officer stating what was done. Do not mention this self-check.")
B, D, R, G, Y, RED, C = "\033[1m", "\033[2m", "\033[0m", "\033[32m", "\033[33m", "\033[31m", "\033[36m"


def chat(key, end_user, messages, tools):
    body = {"model": "gnb-agent-llm", "messages": messages, "tools": tools}
    req = urllib.request.Request(f"{GW}/v1/chat/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json", "apikey": key, "X-End-User": end_user}, method="POST")
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = json.loads(resp.read())
        model = resp.headers.get("X-Kong-LLM-Model", "?")
    return data, model, time.time() - t0


def short(obj, n=110):
    text = obj if isinstance(obj, str) else json.dumps(obj)
    return text if len(text) <= n else text[: n - 1] + "…"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--as", dest="who", choices=IDENTITIES, default="agent")
    ap.add_argument("--on-behalf-of", default="noura.cardops")
    ap.add_argument("task")
    args = ap.parse_args()
    consumer, keyvar = IDENTITIES[args.who]
    key = os.environ[keyvar]

    print(f"  {C}identity{R} {consumer} · on behalf of {args.on_behalf_of}")
    mcp = MCP(f"{GW}/mcp/card-services", key, end_user=args.on_behalf_of)
    mcp.initialize()
    mcp_tools = mcp.list_tools()
    print(f"  {C}tools Kong allows this identity{R}: {', '.join(t['name'] for t in mcp_tools) or '(none)'}")
    tools = [{"type": "function", "function": {"name": t["name"], "description": t.get("description", ""),
                                                "parameters": t.get("inputSchema") or {"type": "object", "properties": {}}}}
             for t in mcp_tools]
    messages = [{"role": "system", "content": SYSTEM}, {"role": "user", "content": args.task}]

    checked = escalated = False
    for _ in range(7):
        data, model, dt = chat(key, args.on_behalf_of, messages, tools)
        msg = data["choices"][0]["message"]
        usage = data.get("usage", {})
        print(f"  {D}🧠 thinking · gnb-agent-llm via Kong · {model} · {dt:.1f}s · {usage.get('total_tokens', '?')} tok{R}")
        calls = msg.get("tool_calls") or []
        if not calls:
            if not checked and not escalated:  # self-check (safety net, e.g. for the local fallback model)
                checked = True
                print(f"  {D}🔎 self-check: was every requested action done with a tool?{R}")
                messages.append({"role": "assistant", "content": msg.get("content") or ""})
                messages.append({"role": "user", "content": SELF_CHECK.format(tools=", ".join(t["name"] for t in mcp_tools))})
                continue
            print(f"  {B}{G}✔ {msg.get('content', '').strip()}{R}")
            return 0
        messages.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": calls})
        for call in calls:
            name = call["function"]["name"]
            escalated = escalated or name == "escalate_to_supervisor"
            raw_args = call["function"].get("arguments") or "{}"
            fargs = json.loads(raw_args) if isinstance(raw_args, str) else raw_args
            pretty = ", ".join(f"{k}={v}" for k, v in fargs.items())
            try:
                res = mcp.call_tool(name, fargs)
                text = " ".join(c.get("text", "") for c in (res or {}).get("content", []))
                mark = f"{RED}✖{R}" if (res or {}).get("isError") else f"{Y}🔧{R}"
                print(f"  {mark} {B}{name}{R}({pretty}) → {short(text)}")
            except MCPHTTPError as e:
                text = f"HTTP {e.status}: this identity is not allowed to use {name}"
                print(f"  {RED}⛔ {name}({pretty}) → {text}{R}")
            messages.append({"role": "tool", "tool_call_id": call.get("id", name), "content": text})
    print(f"  {RED}! stopped after 6 steps{R}")
    return 1


if __name__ == "__main__":
    sys.exit(main())

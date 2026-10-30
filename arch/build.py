"""Build the GNB architecture page from what is actually deployed.

Reads the AI Gateway objects from the Konnect API (models, providers, policies, consumer groups and members,
MCP servers and tools, auth strategies, vaults, data plane nodes) and the containers and ports from
`docker compose config`, plus the 13th use case from onboard/complaints-copilot.yaml. Only whitelisted,
non-secret fields are copied into the page.

  python3 arch/build.py          -> arch/gnb-architecture.html (full page, for live mode and the slide)
                                    arch/artifact.html          (the same page without <html>/<head>, for publishing)
"""
import datetime
import json
import pathlib
import os
import re
import ssl
import subprocess
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
ARCH = ROOT / "arch"
# python.org builds ship without root certificates: verify against macOS's bundle instead of skipping checks
TLS = ssl.create_default_context(cafile="/etc/ssl/cert.pem") if os.path.exists("/etc/ssl/cert.pem") else ssl.create_default_context()


def env():
    vals = {}
    for name in (".env", ".env.demo-keys"):
        p = ROOT / name
        if p.exists():
            for line in p.read_text().splitlines():
                m = re.match(r"\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$", line)
                if m:
                    vals[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return vals


def api(path, token, gw, region=None):
    region = region or env().get("KONGCTL_DEFAULT_KONNECT_REGION") or "eu"
    base = f"https://{region}.api.konghq.com/v1/ai-gateways/{gw}{path}"
    out, url = [], base + ("?page%5Bsize%5D=100" if path else "")
    for _ in range(20):  # a few pages at most for this demo
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=20, context=TLS) as r:
            body = json.loads(r.read())
        if "data" not in body:
            return body
        out += body["data"]
        nxt = (body.get("meta") or {}).get("page", {}).get("next")
        if not nxt:
            break
        url = (f"https://{region}.api.konghq.com{nxt}" if nxt.startswith("/") else nxt if nxt.startswith("http")
               else f"{base}?page%5Bsize%5D=100&page%5Bafter%5D={nxt}")  # next is a URL, a path or a cursor
    return out


def policy_summary(p):
    """Non-secret settings worth showing in the inspector, per policy type (whitelist only)."""
    c, t = p.get("config") or {}, p.get("type")
    vdb = c.get("vectordb") or {}
    if t == "ai-prompt-guard":
        return {"deny_patterns": len(c.get("deny_patterns") or []), "rejection_mode": c.get("rejection_mode")}
    if t == "ai-sanitizer":
        return {"anonymize": c.get("anonymize"), "custom_patterns": [x.get("name") for x in c.get("custom_patterns") or []],
                "redact_type": c.get("redact_type"), "stop_on_error": c.get("stop_on_error"), "service": f"{c.get('host')}:{c.get('port')}"}
    if t == "ai-semantic-prompt-guard":
        return {"threshold": vdb.get("threshold"), "deny_prompts": len(((c.get("rules") or {}).get("deny_prompts")) or []),
                "embeddings": ((c.get("embeddings") or {}).get("model") or {}).get("name"), "vectordb": vdb.get("strategy")}
    if t == "ai-semantic-response-guard":
        return {"threshold": vdb.get("threshold"), "deny_responses": len(((c.get("rules") or {}).get("deny_responses")) or []),
                "embeddings": ((c.get("embeddings") or {}).get("model") or {}).get("name"), "vectordb": vdb.get("strategy")}
    if t == "ai-semantic-cache":
        return {"threshold": vdb.get("threshold"), "cache_ttl": c.get("cache_ttl"), "vectordb": vdb.get("strategy")}
    if t == "ai-rate-limiting-advanced":
        return {"limits": [{"limit": l.get("limit"), "window_size": l.get("window_size")} for pol in c.get("policies") or [] for l in pol.get("limits") or []],
                "match": [m.get("values") for pol in c.get("policies") or [] for m in pol.get("match") or []]}
    if t == "file-log":
        return {"path": c.get("path"), "custom_fields": sorted((c.get("custom_fields_by_lua") or {}).keys())}
    if t == "prometheus":
        return {"ai_metrics": c.get("ai_metrics"), "per_consumer": c.get("per_consumer")}
    return {}


def port_of(url):
    m = re.search(r":(\d+)(/|$)", url or "")
    return int(m.group(1)) if m else None


def main():
    e = env()
    token, gw = e.get("KONNECT_TOKEN"), e.get("AI_GATEWAY_ID")
    if not token or not gw:
        sys.exit("KONNECT_TOKEN and AI_GATEWAY_ID must be set in .env")
    gateway = api("", token, gw)
    providers = api("/model-providers", token, gw)
    models = api("/models", token, gw)
    policies = api("/policies", token, gw)
    groups = api("/consumer-groups", token, gw)
    mcps = api("/mcp-servers", token, gw)
    auths = api("/auth-strategies", token, gw)
    vaults = api("/vaults", token, gw)
    nodes = api("/nodes", token, gw)
    members = {g["name"]: [c.get("name") for c in api(f"/consumer-groups/{g['id']}/consumers", token, gw)] for g in groups}
    consumers = {c["name"]: c.get("display_name") or c["name"] for c in api("/consumers", token, gw)}

    attached = {p["name"]: [] for p in policies}
    for m in models:
        for p in m.get("policies") or []:
            attached.setdefault(p, []).append(f"model {m['name']}")
    for g in groups:
        for p in g.get("policies") or []:
            attached.setdefault(p, []).append(f"group {g['name']}")
    for s in mcps:
        for p in s.get("policies") or []:
            attached.setdefault(p, []).append(f"MCP server {s['name']}")

    cfg = {
        "generated_at": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "git_commit": subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip(),
        "gateway": {"display_name": gateway.get("display_name"), "min_runtime_version": gateway.get("min_runtime_version"), "region": (e.get("KONGCTL_DEFAULT_KONNECT_REGION") or "eu").upper()},
        "nodes": [{"hostname": n.get("hostname"), "version": n.get("version"), "sync": (n.get("config_sync") or {}).get("status") if isinstance(n.get("config_sync"), dict) else n.get("config_sync"),
                   "compatibility": (n.get("compatibility_status") or {}).get("state") if isinstance(n.get("compatibility_status"), dict) else n.get("compatibility_status")} for n in nodes],
        "providers": [{"name": p["name"], "display_name": p.get("display_name"), "type": p.get("type")} for p in providers],
        "models": [{
            "name": m["name"], "display_name": m.get("display_name"),
            "balancer": {k: (m.get("config") or {}).get("balancer", {}).get(k) for k in ("algorithm", "retries", "connect_timeout", "max_fails", "fail_timeout", "failover_criteria")},
            "acl_allow": ((m.get("access") or {}).get("acls") or {}).get("allow", []),
            "auth": (m.get("access") or {}).get("auth_strategies", []),
            "policies": m.get("policies") or [],
            "route": ((m.get("config") or {}).get("route") or {}).get("paths", []),
            "targets": [{"name": t.get("name"), "provider": t.get("provider"), "weight": t.get("weight"),
                         "semantic_description": t.get("semantic_description"),
                         "port": port_of((t.get("config") or {}).get("upstream_url")) or (443 if (t.get("config") or {}).get("type") == "openai" else None),
                         "input_cost": (t.get("config") or {}).get("input_cost"), "output_cost": (t.get("config") or {}).get("output_cost"),
                         "max_tokens": (t.get("config") or {}).get("max_tokens")} for t in m.get("targets") or []],
        } for m in models],
        "policies": [{"name": p["name"], "display_name": p.get("display_name"), "type": p.get("type"), "global": bool(p.get("global")),
                      "attached_to": (["all traffic (global)"] if p.get("global") else []) + attached.get(p["name"], []),
                      "settings": policy_summary(p)} for p in policies],
        "groups": [{"name": g["name"], "display_name": g.get("display_name"), "policies": g.get("policies") or [],
                    "consumers": [{"name": c, "display_name": consumers.get(c, c)} for c in members.get(g["name"], [])]} for g in groups],
        "mcp": [{"name": s["name"], "display_name": s.get("display_name"), "type": s.get("type"),
                 "path": ((s.get("config") or {}).get("route") or {}).get("paths", []), "upstream": (s.get("config") or {}).get("url"),
                 "acl_allow": ((s.get("access") or {}).get("acls") or {}).get("allow", []),
                 "default_tool_acls": ((s.get("access") or {}).get("default_tool_acls") or {}).get("allow", []),
                 "tools": [{"name": t.get("name"), "method": t.get("method"), "path": t.get("path"),
                            "allow": ((t.get("access") or {}).get("acls") or {}).get("allow", []),
                            "destructive": bool((t.get("annotations") or {}).get("destructive_hint"))} for t in s.get("tools") or []]} for s in mcps],
        "auth": [{"name": a["name"], "display_name": a.get("display_name"), "type": a.get("type"),
                  "key_names": (a.get("config") or {}).get("key_names")} for a in auths],
        "vaults": [{"name": v["name"], "type": v.get("type"), "prefix": (v.get("config") or {}).get("prefix")} for v in vaults],
    }

    # containers and published ports (never the environment: it holds secrets)
    try:
        compose = json.loads(subprocess.run(["docker", "compose", "config", "--format", "json"], cwd=ROOT, capture_output=True, text=True, check=True).stdout)
        cfg["containers"] = [{"service": n, "image": s.get("image"), "ports": [str(p.get("published")) for p in s.get("ports") or [] if p.get("published")]}
                             for n, s in sorted(compose.get("services", {}).items())]
    except Exception as exc:  # docker not running: the page still renders from defaults
        cfg["containers"] = []
        print("warning: docker compose config failed:", exc, file=sys.stderr)

    # the 13th use case lives in onboard/, applied live: read its names and bundle with a few patterns
    ob = (ROOT / "onboard/complaints-copilot.yaml").read_text()
    cfg["onboard"] = {
        "consumer": (re.search(r"ai_gateway_consumers:\s*\n\s*- ref: (\S+)", ob) or [None, None])[1],
        "consumer_display": (re.search(r"display_name: (Omar[^\n]*)", ob) or [None, None])[1],
        "group": (re.search(r"ai_gateway_consumer_groups:\s*\n\s*- ref: (\S+)", ob) or [None, None])[1],
        "policies": [p.strip() for p in (re.search(r"policies: \[([^\]]*)\]", ob) or [None, ""])[1].split(",") if p.strip()],
    }
    data = json.dumps(cfg, indent=1, ensure_ascii=False)
    for bad in ("kpat_", "sk-proj-", "BEGIN PRIVATE", e.get("KONNECT_TOKEN", "x" * 40)):
        assert bad not in data, f"refusing to write a page containing {bad[:8]}…"

    tpl = (ARCH / "template.html").read_text()
    frag = tpl.replace("/*__CFG__*/null", data)
    (ARCH / "artifact.html").write_text(frag)
    (ARCH / "gnb-architecture.html").write_text(
        '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
        '<style>:root{padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0;font:14px system-ui,sans-serif}[hidden]{display:none!important}</style>\n'
        "</head>\n<body>\n" + frag + "\n</body>\n</html>\n")
    print(f"built arch/gnb-architecture.html and arch/artifact.html · {len(cfg['models'])} models, {len(cfg['policies'])} policies, "
          f"{len(cfg['groups'])} groups, {sum(len(s['tools']) for s in cfg['mcp'])} tools, {len(cfg['containers'])} containers")


if __name__ == "__main__":
    main()

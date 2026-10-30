"""Live mode for the architecture page: serve it from the Mac and feed it real calls and status.

  python3 arch/live.py            -> http://localhost:8099 (rebuilds the page from the deployed config first)
  python3 arch/live.py --no-build

The page polls /live?since=<seq>. Events come from the data plane's own log (docker compose logs -f kong-dp, the
file-log audit policy); status comes from the data plane's /status and /metrics, the factory ports and docker compose ps.
Only fields the page needs leave this process: no prompts, answers or keys (the log has none, by design).
"""
import collections
import json
import pathlib
import re
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent.parent
PAGE = ROOT / "arch" / "gnb-architecture.html"
PORT = 8099
EVENTS = collections.deque(maxlen=300)
STATUS = {}
LOCK = threading.Lock()
SEQ = [0]


def add(ev):
    with LOCK:
        SEQ[0] += 1
        ev["seq"] = SEQ[0]
        EVENTS.append(ev)


def to_event(j):
    """One data plane log line -> zero or more page events."""
    if j.get("end_user") == "readiness-probe":
        return []
    uri = (j.get("request") or {}).get("uri") or ""
    resp = j.get("response") or {}
    base = {"t": (j.get("started_at") or time.time() * 1000) / 1000, "consumer": (j.get("consumer") or {}).get("username"),
            "use_case": j.get("use_case"), "end_user": j.get("end_user"), "status": resp.get("status")}
    ai = j.get("ai") or {}
    if uri.startswith("/mcp"):
        methods = [r.get("method") for r in (ai.get("mcp") or {}).get("rpc") or []]
        audits = (ai.get("mcp") or {}).get("audit") or []
        if "tools/call" in methods or (resp.get("status") == 403 and audits):
            return [dict(base, kind="mcp", tool=a.get("primitive_name"), action=a.get("action")) for a in audits if a.get("primitive_name")]
        if "tools/list" in methods:
            return [dict(base, kind="mcp", tool=None, action="allow")]
        return []  # initialize, notifications
    if not uri.startswith("/v1"):
        return []
    proxy = ai.get("proxy") or {}
    meta, usage = proxy.get("meta") or {}, proxy.get("usage") or {}
    headers = resp.get("headers") or {}
    return [dict(base, kind="llm", ports=[t.get("port") for t in j.get("tries") or [] if t.get("port")],
                 cache=headers.get("x-cache-status"), llm=(meta.get("llm_latency") or 0) > 0,
                 model=meta.get("response_model") or headers.get("x-kong-llm-model"), tokens=usage.get("total_tokens"),
                 cost=usage.get("cost"), sanitized="sanitizer" in ai, denied=not ai and resp.get("status") == 403)]


def follow_logs():
    while True:
        proc = subprocess.Popen(["docker", "compose", "logs", "-f", "--no-log-prefix", "--since", "1s", "kong-dp"], cwd=ROOT,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
        for line in proc.stdout:
            if line.startswith("{"):
                try:
                    for ev in to_event(json.loads(line)):
                        add(ev)
                except (json.JSONDecodeError, TypeError, AttributeError):
                    pass
        proc.wait()
        time.sleep(1)  # the container restarted (reset.sh): follow again


def port_open(port):
    with socket.socket() as s:
        s.settimeout(0.4)
        return s.connect_ex(("127.0.0.1", port)) == 0


def poll_status():
    while True:
        st = {"ports": {str(p): port_open(p) for p in (11434, 11501, 11502)}, "containers": {}}
        try:
            st["config_hash"] = json.loads(urllib.request.urlopen("http://127.0.0.1:8100/status", timeout=2).read()).get("configuration_hash")
            metrics = urllib.request.urlopen("http://127.0.0.1:8100/metrics", timeout=2).read().decode()
            m = re.search(r"^kong_control_plane_connected (\d)", metrics, re.M)
            st["cp_connected"] = bool(m and m.group(1) == "1")
            v = re.search(r'kong_node_info\{[^}]*version="([^"]+)"', metrics)
            st["version"] = v.group(1) if v else None
        except Exception:
            st["dp_up"] = False
        try:
            out = subprocess.run(["docker", "compose", "ps", "--all", "--format", "json"], cwd=ROOT, capture_output=True, text=True, timeout=10).stdout.strip()
            rows = json.loads(out) if out.startswith("[") else [json.loads(l) for l in out.splitlines() if l.strip()]
            st["containers"] = {r.get("Service"): r.get("State") for r in rows}
        except Exception:
            pass
        with LOCK:
            STATUS.clear()
            STATUS.update(st)
        time.sleep(2)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path in ("/", "/index.html"):
            return self._send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
        if url.path == "/live":
            since = int((urllib.parse.parse_qs(url.query).get("since") or ["0"])[0] or 0)
            with LOCK:
                body = {"seq": SEQ[0], "status": dict(STATUS), "events": [e for e in EVENTS if e["seq"] > since][-40:]}
            return self._send(200, json.dumps(body).encode(), "application/json")
        return self._send(404, b"not found", "text/plain")


def main():
    if "--no-build" not in sys.argv:
        subprocess.run([sys.executable, str(ROOT / "arch" / "build.py")], check=True)
    for target in (follow_logs, poll_status):
        threading.Thread(target=target, daemon=True).start()
    print(f"Live architecture: http://localhost:{PORT}  (Ctrl+C to stop)", flush=True)
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()

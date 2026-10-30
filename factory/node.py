"""A "GPU serving node" endpoint for the demo: forwards to Ollama and logs what the model received.

Usage: python3 factory/node.py <LABEL> <PORT> [UPSTREAM]
  e.g. python3 factory/node.py DC1 11501            (upstream defaults to http://127.0.0.1:11434)

Each request prints one line: node, model, the last user message (truncated) and the first
line of the model's draft answer. Stopping the process makes the node "go down" (connection
refused), which is the clean failover trigger for Act 1.
"""
import datetime
import http.client
import json
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LABEL = sys.argv[1] if len(sys.argv) > 1 else "NODE"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 11501
UPSTREAM = urllib.parse.urlparse(sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:11434")
HOP_BY_HOP = {"connection", "keep-alive", "transfer-encoding", "te", "trailer", "upgrade",
              "proxy-authorization", "proxy-authenticate", "host", "content-length"}


def short(text: str, n: int = 110) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= n else text[: n - 1] + "…"


def last_user_message(body: dict) -> str:
    for msg in reversed(body.get("messages") or []):
        if msg.get("role") == "user":
            content = msg.get("content")
            if isinstance(content, list):  # OpenAI-style content parts
                content = " ".join(p.get("text", "") for p in content if isinstance(p, dict))
            return content or ""
    return body.get("prompt", "")


def draft_answer(raw: bytes) -> str:
    text = raw.decode(errors="replace").strip()
    try:
        data = json.loads(text)
        if "message" in data:
            return data["message"].get("content", "")
        if "choices" in data:
            return data["choices"][0].get("message", {}).get("content", "")
        return ""
    except json.JSONDecodeError:  # NDJSON stream: join the content pieces
        parts = []
        for line in text.splitlines():
            try:
                parts.append(json.loads(line).get("message", {}).get("content", ""))
            except json.JSONDecodeError:
                pass
        return "".join(parts)


class Node(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):  # keep the pane clean: only our own lines
        pass

    def _forward(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        conn = http.client.HTTPConnection(UPSTREAM.hostname, UPSTREAM.port or 80, timeout=300)
        headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_BY_HOP}
        conn.request(self.command, self.path, body=body, headers=headers)
        resp = conn.getresponse()
        payload = resp.read()
        self.send_response(resp.status)
        for k, v in resp.getheaders():
            if k.lower() not in HOP_BY_HOP:
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
        conn.close()
        if self.command == "POST" and body:
            try:
                req = json.loads(body)
            except json.JSONDecodeError:
                req = {}
            if "messages" in req or "prompt" in req:
                stamp = f"{datetime.datetime.now():%H:%M:%S}"
                print(f"{stamp} {LABEL:<4} │ {req.get('model', '?'):<14} │ IN : {short(last_user_message(req))}", flush=True)
                print(f"{'':8} {'':<4} │ {'':<14} │ OUT: {short(draft_answer(payload))}", flush=True)

    do_GET = do_POST = do_PUT = do_DELETE = _forward


if __name__ == "__main__":
    print(f"{LABEL} node listening on :{PORT} → {UPSTREAM.geturl()}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Node).serve_forever()

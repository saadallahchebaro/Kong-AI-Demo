"""Minimal MCP client (streamable HTTP, JSON-RPC) for the demo. Standard library only.

    c = MCP("http://localhost:8000/mcp/card-services", api_key, end_user="noura.cardops")
    c.initialize(); c.list_tools(); c.call_tool("get_card_status", {"path_card_id": "4242"})

HTTP errors (401/403 from Kong) raise MCPHTTPError with the status code and body.
"""
import json
import urllib.error
import urllib.request

PROTOCOL = "2025-06-18"


class MCPHTTPError(Exception):
    def __init__(self, status, body):
        super().__init__(f"HTTP {status}: {body[:200]}")
        self.status, self.body = status, body


class MCP:
    def __init__(self, url, api_key, end_user=None, timeout=60):
        self.url, self.timeout, self.session, self._id = url, timeout, None, 0
        self.headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream",
                        "apikey": api_key}
        if end_user:
            self.headers["X-End-User"] = end_user

    def _post(self, payload):
        headers = dict(self.headers)
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(self.url, json.dumps(payload).encode(), headers, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                self.session = resp.headers.get("Mcp-Session-Id") or self.session
                raw = resp.read().decode()
                ctype = resp.headers.get("Content-Type", "")
        except urllib.error.HTTPError as e:
            raise MCPHTTPError(e.code, e.read().decode(errors="replace")) from None
        if not raw.strip():
            return None
        if "text/event-stream" in ctype:  # take the last JSON-RPC message from the SSE stream
            msgs = [json.loads(line[5:].strip()) for line in raw.splitlines() if line.startswith("data:") and line[5:].strip()]
            return msgs[-1] if msgs else None
        return json.loads(raw)

    def _rpc(self, method, params=None):
        self._id += 1
        msg = self._post({"jsonrpc": "2.0", "id": self._id, "method": method, "params": params or {}})
        if msg and "error" in msg:
            raise RuntimeError(f"{method}: {msg['error']}")
        return (msg or {}).get("result")

    def initialize(self):
        res = self._rpc("initialize", {"protocolVersion": PROTOCOL, "capabilities": {},
                                       "clientInfo": {"name": "gnb-card-ops-agent", "version": "1.0"}})
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"})
        return res

    def list_tools(self):
        return (self._rpc("tools/list") or {}).get("tools", [])

    def call_tool(self, name, arguments):
        return self._rpc("tools/call", {"name": name, "arguments": arguments})

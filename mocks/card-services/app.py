"""Mock GNB card-services API (fake data only). Standard library, no dependencies.

GET  /cards/{card_id}/status        card status
GET  /customers/{customer_id}/kyc   KYC status
POST /cards/{card_id}/block         block a card (changes state)
POST /cases                         open a case for the card-ops supervisor queue
POST /admin/reset                   back to the demo baseline (used by reset.sh)
GET  /health

Every request logs who called (Kong forwards the consumer) and on whose behalf (X-End-User).
"""
import copy
import itertools
import urllib.parse
import datetime
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BASELINE = {
    "cards": {
        "4242": {"card_id": "4242", "customer_id": "CUST-1001", "type": "debit", "status": "active",
                 "last_transaction": "2026-10-20 · AED 120.00 · Dubai Mall"},
        "1881": {"card_id": "1881", "customer_id": "CUST-1002", "type": "credit", "status": "active",
                 "last_transaction": "2026-10-19 · AED 2,450.00 · Abu Dhabi Airport"},
    },
    "kyc": {
        "CUST-1001": {"customer_id": "CUST-1001", "kyc_status": "verified", "risk_rating": "low", "review_due": "2027-03"},
        "CUST-1002": {"customer_id": "CUST-1002", "kyc_status": "review_overdue", "risk_rating": "medium", "review_due": "2026-09"},
    },
}
STATE = copy.deepcopy(BASELINE)
CASE_IDS = itertools.count(1001)


def log(handler, status, note=""):
    who = handler.headers.get("X-Consumer-Username") or handler.headers.get("X-Consumer-Custom-ID") or "-"
    user = handler.headers.get("X-End-User") or "-"
    print(f"{datetime.datetime.now():%H:%M:%S} card-services {handler.command} {handler.path} → {status}"
          f" · caller={who} · on_behalf_of={user}{(' · ' + note) if note else ''}", flush=True)


class API(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def _send(self, status, body, note=""):
        data = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        log(self, status, note)

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            return self._send(200, {"status": "ok"})
        if m := re.fullmatch(r"/cards/([^/]+)/status", path):
            card = STATE["cards"].get(m.group(1))
            return self._send(200, card) if card else self._send(404, {"error": "card not found"})
        if m := re.fullmatch(r"/customers/([^/]+)/kyc", path):
            kyc = STATE["kyc"].get(m.group(1))
            return self._send(200, kyc) if kyc else self._send(404, {"error": "customer not found"})
        return self._send(404, {"error": "not found"})

    def do_POST(self):
        path = self.path.split("?")[0]
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        if path == "/admin/reset":
            STATE.clear(); STATE.update(copy.deepcopy(BASELINE))
            return self._send(200, {"status": "reset"})
        if path == "/cases":
            q = dict(urllib.parse.parse_qsl(self.path.partition("?")[2]))
            case = {"case_id": f"CASE-{next(CASE_IDS)}", "status": "open", "assigned_to": "card-ops-supervisor",
                    "card_id": q.get("card_id"), "customer_id": q.get("customer_id"), "reason": q.get("reason", "")}
            return self._send(201, case, note=f"{case['case_id']} ESCALATED")
        if m := re.fullmatch(r"/cards/([^/]+)/block", path):
            card = STATE["cards"].get(m.group(1))
            if not card:
                return self._send(404, {"error": "card not found"})
            try:
                reason = (json.loads(body) if body else {}).get("reason", "reported stolen")
            except json.JSONDecodeError:
                reason = "reported stolen"
            card.update(status="blocked", blocked_reason=reason,
                        blocked_at=f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}")
            return self._send(200, card, note=f"CARD {card['card_id']} BLOCKED")
        return self._send(404, {"error": "not found"})


if __name__ == "__main__":
    print("card-services mock listening on :8080 (fake data only)", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8080), API).serve_forever()

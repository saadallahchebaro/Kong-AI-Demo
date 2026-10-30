#!/usr/bin/env bash
# Full rehearsal check in stage order: reset → act1 → act2 → act3 → act4 → finale → 13th use case, asserting every outcome.
# CHECK_VERBOSE=1 prints one line per check; CHECK_CONTINUE=1 runs every stage even after a failure (both used by regression.sh).
cd "$(dirname "$0")/.."
scripts/check-acts123.sh || [ "${CHECK_CONTINUE:-0}" = 1 ] || exit 1
STEP_AUTO=1 scripts/act4.sh > run/act4.out 2>&1
python3 -I - run/act4.out <<'PY'
import os, re, sys
out = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1]).read())
agent, _, rest = out.partition("Same agent code, delegated by supervisor Khalid.")
sup, _, audit = rest.partition("Every tool call authenticated and audited")
checks = {
  "agent tools hide block_card": "Card-ops agent · card-ops-agent → card-services MCP: escalate_to_supervisor, get_card_status, get_kyc_status" in agent,
  "supervisor sees block_card": "block_card, escalate_to_supervisor, get_card_status, get_kyc_status" in agent,
  "agent checked the card": "get_card_status(" in agent,
  "agent escalated": "escalate_to_supervisor(" in agent,
  "agent did not block": "card 4242 is now: active" in agent,
  "supervisor blocked": "block_card(path_card_id=4242)" in sup and "card 4242 is now: blocked" in sup,
  "audit: block_card allowed for khalid": re.search(r"khalid\s+for khalid\.supervisor\s+block_card\s+ALLOW", audit) is not None,
  "audit: escalation for noura": re.search(r"card-ops-agent-01\s+for noura\.cardops\s+escalate_to_supervisor\s+ALLOW", audit) is not None,
}
bad = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    if os.environ.get("CHECK_VERBOSE") == "1": print(f"CHECK|{'PASS' if v else 'FAIL'}|act4: {k}")
print(f"  act 4: {len(checks)-len(bad)}/{len(checks)} checks · {'ALL PASS' if not bad else 'FAILED: ' + ', '.join(bad)}")
sys.exit(1 if bad else 0)
PY
[ $? = 0 ] || [ "${CHECK_CONTINUE:-0}" = 1 ] || exit 1
STEP_AUTO=1 scripts/finale.sh > run/finale.out 2>&1
STEP_AUTO=1 scripts/onboard.sh > run/onboard.out 2>&1
python3 -I - run/act2.out run/finale.out run/onboard.out <<'PY'
import os, re, sys
clean = lambda f: re.sub(r"\x1b\[[0-9;]*m", "", open(f).read())
act2, fin, onb = (clean(f) for f in sys.argv[1:4])
cut, _, rest = fin.partition("Aisha's complaint again")
complaint, _, rest = rest.partition("The agent's tools, with Konnect gone.")
agent, _, restore = rest.partition("Restoring the link.")
before, _, rest = onb.partition("One apply.")
apply_, _, rest = rest.partition("Omar's first call")
first, _, audit = rest.partition("The same audit trail")
checks = {
  "act 2 audit shows Aisha's calls": re.search(r"aisha\s+retail-copilot", act2.split("The audit trail", 1)[-1]) is not None,
  "finale: control plane disconnected": "kong_control_plane_connected 0" in cut,
  "finale: complaint served and redacted": "← 200" in complaint and "PLACEHOLDER" in complaint and "784-1990" not in complaint.split("← 200", 1)[1],
  "finale: agent tools unchanged": "escalate_to_supervisor, get_card_status, get_kyc_status" in agent and "block_card" not in agent,
  "finale: reconnected, config unchanged": "reconnected after" in restore and "kong_control_plane_connected 1" in restore and "(unchanged)" in restore,
  "13th: no access before onboarding": "← 403" in before and "You cannot consume this service" in before,
  "13th: one apply created the use case": "complaints-copilot... ✓" in apply_ and "✓ applied in" in apply_,
  "13th: first call redacted, with budget": "← 200" in first and "PLACEHOLDER" in first and "784-1990" not in first.split("← 200", 1)[1] and "budget left today:" in first,
  "13th: audit shows Omar's use case": re.search(r"omar\s+complaints-copilot\s+\S+\s+\d+ tok .* allowed", audit) is not None,
}
bad = [k for k, v in checks.items() if not v]
for k, v in checks.items():
    if os.environ.get("CHECK_VERBOSE") == "1": print(f"CHECK|{'PASS' if v else 'FAIL'}|{k}")
print(f"  finale + 13th: {len(checks)-len(bad)}/{len(checks)} checks · {'ALL PASS' if not bad else 'FAILED: ' + ', '.join(bad)}")
sys.exit(1 if bad else 0)
PY

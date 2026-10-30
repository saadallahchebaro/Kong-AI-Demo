#!/usr/bin/env bash
# Rehearsal check for Acts 1–2: reset → act1 → act2 (auto) and assert every expected outcome.
cd "$(dirname "$0")/.."
R=run/results.log; : > "$R"
scripts/reset.sh > run/reset.log 2>&1 || { echo "reset failed"; exit 1; }
STEP_AUTO=1 RESULTS_FILE=$R scripts/act1.sh > run/act1.out 2>&1
sleep 11   # circuit breaker lets DC1 back in after fail_timeout (10 s); on stage the talk covers this
STEP_AUTO=1 RESULTS_FILE=$R scripts/act2.sh > run/act2.out 2>&1
python3 -I - "$R" <<'PY'
import sys
rows = [(lambda f: [f[0], f[1], f[3] if len(f) > 3 else ""])(l.rstrip("\n").split("|", 3)) for l in open(sys.argv[1])]
exp = [  # (code, model contains, text must contain, text must not contain)
  ("200", "7b", "", ""), ("200", "1.5b", "", ""),                                       # act 1
  ("403", "", "", ""), ("403", "", "", ""), ("200", "7b", "", ""),                      # act 2: access
  ("200", "7b", "784-1990", ""), ("200", "7b", "", ""),                                 # before: leak, advice answered
  ("200", "7b", "PLACEHOLDER", "784-1990"),                                             # after: redacted
  ("403", "", "GUARDRAIL_BLOCKED", ""), ("403", "", "GUARDRAIL_BLOCKED", ""),           # advice + reworded
  ("403", "", "GUARDRAIL_BLOCKED", ""), ("403", "", "GUARDRAIL_BLOCKED", ""),           # loan answer, injection
]
ok = len(rows) == len(exp)
for i, (e, r) in enumerate(zip(exp, rows)):
    code, model, text = (r + ["", "", ""])[:3]
    good = code == e[0] and e[1] in model and e[2] in text and (not e[3] or e[3] not in text)
    ok &= good
    if not good: print(f"  FAIL step {i+1}: expected {e} got {code} {model} {text[:60]}")
print(f"  {len(rows)}/{len(exp)} calls, {'ALL PASS' if ok else 'FAILED'}")
sys.exit(0 if ok else 1)
PY

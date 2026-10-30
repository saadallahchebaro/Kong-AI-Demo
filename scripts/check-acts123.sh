#!/usr/bin/env bash
# Rehearsal check for Acts 1–3 in stage order: reset → act1 → act2 → act3, asserting every outcome.
# CHECK_VERBOSE=1 prints one "CHECK|PASS|name" / "CHECK|FAIL|name" line per check (used by regression.sh).
cd "$(dirname "$0")/.."
R=run/results.log; : > "$R"
scripts/reset.sh > run/reset.log 2>&1 || { echo "reset failed"; exit 1; }
STEP_AUTO=1 RESULTS_FILE=$R scripts/act1.sh > run/act1.out 2>&1
sleep 11
STEP_AUTO=1 RESULTS_FILE=$R scripts/act2.sh > run/act2.out 2>&1
STEP_AUTO=1 RESULTS_FILE=$R scripts/act3.sh > run/act3.out 2>&1
python3 -I - "$R" run/act3.out <<'PY'
import os, sys
rows = [l.rstrip("\n").split("|", 5) for l in open(sys.argv[1])]
row = lambda i: (rows[i] + [""] * 6)[:6] if i < len(rows) else [""] * 6
results = []
def check(name, i, ok):  # ok(code, model, cache, text, plugin)
    c, m, k, t, p, _ = row(i)
    results.append((name, bool(c) and ok(c, m, k, t, p), row(i)))
blocked_by = lambda plugin: (lambda c, m, k, t, p: c == "403" and "GUARDRAIL_BLOCKED" in t and p == plugin)
check("act1: DC1 answers (7B)",                         0, lambda c, m, k, t, p: c == "200" and "7b" in m)
check("act1: DR answers with DC1 down (1.5B)",          1, lambda c, m, k, t, p: c == "200" and "1.5b" in m)
check("act2 pilot: no key gets 403",                    2, lambda c, m, k, t, p: c == "403")
check("act2 pilot: card-ops agent gets 403",            3, lambda c, m, k, t, p: c == "403")
check("act2 pilot: Aisha answered (7B)",                4, lambda c, m, k, t, p: c == "200" and "7b" in m)
check("act2 pilot: complaint reaches model unredacted", 5, lambda c, m, k, t, p: c == "200" and "784-1990" in t)
check("act2 pilot: advice question answered",           6, lambda c, m, k, t, p: c == "200")
check("act2 bundle: complaint redacted",                7, lambda c, m, k, t, p: c == "200" and "PLACEHOLDER" in t and "784-1990" not in t)
check("act2 bundle: advice blocked (advice guard)",     8, blocked_by("ai-semantic-prompt-guard"))
check("act2 bundle: reworded advice blocked",           9, blocked_by("ai-semantic-prompt-guard"))
check("act2 bundle: loan promise blocked (response guard, D5)", 10, blocked_by("ai-semantic-response-guard"))
check("act2 bundle: injection blocked (injection guard)", 11, blocked_by("ai-prompt-guard"))
check("act3: routine question -> small model",          12, lambda c, m, k, t, p: c == "200" and "1.5b" in m)
check("act3: AML case -> 7B",                           13, lambda c, m, k, t, p: c == "200" and "7b" in m)
check("act3: first ask is a cache Miss",                14, lambda c, m, k, t, p: c == "200" and k == "Miss")
check("act3: reworded ask is a cache Hit",              15, lambda c, m, k, t, p: c == "200" and k == "Hit")
budget = [row(i) for i in range(16, len(rows))]
codes = [r[0] for r in budget]
results.append(("act3: budget answers 200 until the 429", bool(codes) and codes[-1] == "429" and all(c == "200" for c in codes[:-1]), codes))
out = open(sys.argv[2]).read()
results.append(("act3: analytics shows the retail copilot", "Retail copilot" in out and "cost (USD)" in out, ""))
fails = [r for r in results if not r[1]]
n429 = next((i + 1 for i, c in enumerate(codes) if c == "429"), None)
print(f"  {len(rows)} calls · budget hit after {n429} questions · {'ALL PASS' if not fails else 'FAILED'}")
for name, ok, detail in results:
    if os.environ.get("CHECK_VERBOSE") == "1": print(f"CHECK|{'PASS' if ok else 'FAIL'}|{name}")
    if not ok: print("  FAIL", name, "->", detail)
sys.exit(0 if not fails else 1)
PY

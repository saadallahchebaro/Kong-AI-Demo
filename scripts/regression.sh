#!/usr/bin/env bash
# D5 gate: the whole demo in stage order, N times (default 10), counting every check across the runs.
# Each run is check-all.sh: reset → Acts 1–4 → finale → 13th use case, so every scripted prompt runs once per run,
# in the state it meets on stage (bundle off, then on; cache empty; budget fresh). Ends with reset.sh.
# Spends a little OpenAI credit per run (the agent and supervisor on gpt-5.5). About 2 min 10 s per run.
cd "$(dirname "$0")/.."
N="${1:-10}"; OUT=run/regression; rm -rf "$OUT"; mkdir -p "$OUT"
echo "▶ D5 regression: $N runs of the full demo"
for i in $(seq 1 "$N"); do
  s=$(date +%s)
  CHECK_VERBOSE=1 CHECK_CONTINUE=1 scripts/check-all.sh > "$OUT/run-$i.log" 2>&1
  mkdir -p "$OUT/run-$i" && cp run/results.log run/act*.out run/finale.out run/onboard.out "$OUT/run-$i/" 2>/dev/null
  printf '  run %2d/%d · %3d s · %s failed checks\n' "$i" "$N" $(( $(date +%s) - s )) "$(grep -c '^CHECK|FAIL' "$OUT/run-$i.log")"
done
python3 -I - "$OUT" "$N" <<'PY'
import os, re, sys
out, n = sys.argv[1], int(sys.argv[2])
order, passes = [], {}
for i in range(1, n + 1):
    for line in open(f"{out}/run-{i}.log"):
        if line.startswith("CHECK|"):
            _, verdict, name = line.rstrip("\n").split("|", 2)
            if name not in passes: order.append(name); passes[name] = 0
            passes[name] += verdict == "PASS"
print(f"\n  {'result':>7}  check")
for name in order:
    mark = "✓" if passes[name] == n else "✗"
    print(f"  {mark} {passes[name]:>2}/{n}  {name}")

def rows(i):
    p = f"{out}/run-{i}/results.log"
    return [(l.rstrip("\n").split("|", 5) + [""] * 6)[:6] for l in open(p)] if os.path.exists(p) else []
def scores(idx):
    v = [float(r[idx][5]) for r in map(rows, range(1, n + 1)) if len(r) > idx and r[idx][5]]
    return f"{min(v):.2f}–{max(v):.2f} over {len(v)} runs" if v else "none recorded"
print("\n  guard distances (lower = closer to the deny list):")
print(f"    loan promise vs response guard (threshold 0.38): {scores(10)}")
print(f"    advice question vs advice guard (threshold 0.40): {scores(8)}")
print(f"    reworded advice vs advice guard (threshold 0.40): {scores(9)}")

# D5: the response guard must block the loan promise every time and nothing else, ever
stray = 0
for i in range(1, n + 1):
    for f in ("act2.out", "act3.out", "finale.out", "onboard.out"):
        p = f"{out}/run-{i}/{f}"
        if os.path.exists(p):
            hits = len(re.findall(r"by ai-semantic-response-guard", open(p).read()))
            stray += hits - (1 if f == "act2.out" and hits else 0)
rg = passes.get("act2 bundle: loan promise blocked (response guard, D5)", 0)
print(f"\n  response guard: blocked the loan promise {rg}/{n} · blocked anything else: {stray} times")
d5 = rg == n and stray == 0
print(f"  D5: {'PASS · the response guard runs live' if d5 else 'FAIL · point at the response-guard YAML instead'}")
allpass = all(v == n for v in passes.values())
print(f"  all checks: {'ALL PASS' if allpass else 'SOME FAILED (see run/regression/run-*.log)'}")
sys.exit(0 if allpass else 1)
PY
rc=$?
echo "▶ back to baseline"; scripts/reset.sh > run/reset.log 2>&1 && echo "  ✓ baseline ready" || echo "  ! reset failed (see run/reset.log)"
exit $rc

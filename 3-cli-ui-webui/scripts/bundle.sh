#!/usr/bin/env bash
# ACT 2 in GNB Assist: attach the reviewed policy bundle to the retail copilot. The same one-line Git change, kongctl diff
# and kongctl apply as the CLI scenario's act2.sh, without its terminal calls (the calls happen in GNB Assist).
. "$(dirname "$0")/lib.sh"
FILE=kong/36-retail-copilot.yaml
banner "ACT 2 · THE PRODUCTION GATE" "one reviewed bundle · attached to the retail copilot"
if git diff --quiet -- "$FILE"; then
  python3 -I - "$FILE" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
off = "    policies: []\n    # policies: ["; on = "    # policies: []\n    policies: ["
assert off in s, "bundle line not found"; open(p, "w").write(s.replace(off, on))
PY
else
  printf '  %sthe bundle line is already changed in %s%s\n' "$D" "$FILE" "$R"
fi
show "git diff $FILE"; git --no-pager diff --color=always "$FILE" | sed -n '5,$p'
show "kongctl diff --mode apply -f $FILE"; scripts/kctl diff --mode apply -f "$FILE" 2>&1 | grep -E "^\s+[~+-]|policies" | head -6
h0=$(curl -s "$STATUS/status" | jq -r .configuration_hash); t0=$(now_ms)
show "kongctl apply -f $FILE"; scripts/kctl apply -f "$FILE" --auto-approve 2>&1 | grep -E "✓|✗|Error" | sed 's/^/  /'
t1=$(now_ms); wait_config "$h0" && wait_bundle && printf '  %s✓ applied in %.1fs · live on the data plane %.1fs later%s\n' "$GRN" "$(echo "($t1-$t0)/1000" | bc -l)" "$(echo "($(now_ms)-$t1)/1000" | bc -l)" "$R" || printf '  %s! config not seen yet%s\n' "$RED" "$R"

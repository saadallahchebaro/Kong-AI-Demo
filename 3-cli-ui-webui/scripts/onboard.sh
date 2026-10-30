#!/usr/bin/env bash
# THE 13TH USE CASE in GNB Assist: one reviewed file, one apply. Omar's Complaints Copilot already exists in GNB Assist; until
# this runs, Kong refuses it ("not onboarded"). reset.sh removes it again.
. "$(dirname "$0")/lib.sh"
FILE=onboard/complaints-copilot.yaml
banner "THE 13TH USE CASE" "one file, one apply · governed from the first call"
show "cat $FILE"; sed -n '5,$p' "$FILE" | sed 's/^/    /'
h0=$(curl -s "$STATUS/status" | jq -r .configuration_hash); t0=$(now_ms)
show "kongctl apply -f $FILE"; scripts/kctl apply -f "$FILE" --auto-approve 2>&1 | grep -E "✓|✗|Error" | sed 's/^/  /'
t1=$(now_ms); wait_config "$h0" && wait_bundle KEY_OMAR && printf '  %s✓ applied in %.1fs · live on the data plane %.1fs later%s\n' "$GRN" "$(echo "($t1-$t0)/1000" | bc -l)" "$(echo "($(now_ms)-$t1)/1000" | bc -l)" "$R" || printf '  %s! config not seen yet%s\n' "$RED" "$R"

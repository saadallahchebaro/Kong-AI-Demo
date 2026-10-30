#!/usr/bin/env bash
# THE 13TH USE CASE · a complaints copilot onboarded live: one reviewed file, one apply, governed on its first call.
# reset.sh removes it again (kongctl delete -f on the same file).
. "$(dirname "$0")/lib/common.sh"
FILE=onboard/complaints-copilot.yaml
SYS_ECHO="You are GNB's complaints assistant. First line: repeat the customer's message exactly as received, prefixed with 'RECEIVED:'. Then reply helpfully in at most two sentences."
COMPLAINT="My name is Ahmed Al Mansoori, Emirates ID 784-1990-1234567-1. I was charged twice for my card fee."

T_START=$(now_ms)
banner "THE 13TH USE CASE" "one file, one apply · governed from the first call"

step "Your thirteenth use case: a complaints copilot. This file is everything it takes."
show "cat $FILE"; sed -n '5,$p' "$FILE" | sed 's/^/    /'

step "Omar's app today: not onboarded, so no access."
ask "Omar · (not onboarded)" KEY_OMAR gnb-assistant "$SYS_ECHO" "$COMPLAINT" "X-End-User: omar.complaints"

step "One apply."
h0=$(curl -s "$STATUS/status" | jq -r .configuration_hash); t0=$(now_ms)
show "kongctl apply -f $FILE"; scripts/kctl apply -f "$FILE" --auto-approve 2>&1 | grep -E "✓|✗|Error" | sed 's/^/  /'
t1=$(now_ms); wait_config "$h0" && wait_bundle KEY_OMAR && printf '  %s✓ applied in %.1fs · live on the data plane %.1fs later%s\n' "$GRN" "$(echo "($t1-$t0)/1000" | bc -l)" "$(echo "($(now_ms)-$t1)/1000" | bc -l)" "$R" || printf '  %s! config not seen yet%s\n' "$RED" "$R"

step "Omar's first call: the complaint with the Emirates ID. Watch the DC1 pane."
ask "Omar · complaints-copilot" KEY_OMAR gnb-assistant "$SYS_ECHO" "$COMPLAINT" "X-End-User: omar.complaints"

step "The same audit trail, from the first call."
audit "$T_START"

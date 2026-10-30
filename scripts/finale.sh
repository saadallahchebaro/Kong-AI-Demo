#!/usr/bin/env bash
# FINALE · Unplug Konnect: cut the data centre's only route to Konnect, rerun governed calls, then restore the link.
# Run after Acts 2 and 4 (the retail copilot's bundle must be on). AI traffic never uses the Konnect link.
. "$(dirname "$0")/lib/common.sh"
SYS_ECHO="You are GNB's retail customer assistant. First line: repeat the customer's message exactly as received, prefixed with 'RECEIVED:'. Then reply helpfully in at most two sentences."
COMPLAINT="My name is Ahmed Al Mansoori, Emirates ID 784-1990-1234567-1. I was charged twice for my card fee."
cp_connected() { curl -s "$STATUS/metrics" | awk '/^kong_control_plane_connected/ {print $2}'; }

banner "FINALE · UNPLUG KONNECT" "the controls run in your data centre, not in the SaaS"
git diff --quiet -- kong/36-retail-copilot.yaml && printf '  %s! the retail copilot bundle is off: run act2.sh first%s\n' "$YEL" "$R"

step "Cutting this data centre's only route to Konnect."
h0=$(curl -s "$STATUS/status" | jq -r .configuration_hash)
show "scripts/konnect-cut.sh stop"; printf '  %s%s%s\n' "$RED" "$(scripts/konnect-cut.sh stop)" "$R"
for i in $(seq 1 30); do [ "$(cp_connected)" = 0 ] && break; sleep 0.5; done
show "curl $STATUS/metrics | grep kong_control_plane_connected"
printf '  kong_control_plane_connected %s%s%s %s· configuration %s… (last-known, cached on the data plane)%s\n' \
  "$B" "$(cp_connected)" "$R" "$D" "${h0:0:8}" "$R"

step "Aisha's complaint again, with the Emirates ID. Watch the DC1 pane."
ask "Aisha · retail-copilot" KEY_AISHA gnb-assistant "$SYS_ECHO" "$COMPLAINT" "X-End-User: aisha.retail"

step "The agent's tools, with Konnect gone."
tools "Card-ops agent · card-ops-agent" KEY_CARD_OPS_AGENT

step "Konnect never was in the data path. Restoring the link."
show "scripts/konnect-cut.sh start"; scripts/konnect-cut.sh start | sed 's/^/  /'
for i in $(seq 1 20); do [ "$(cp_connected)" = 1 ] && break; sleep 0.5; done
h1=$(curl -s "$STATUS/status" | jq -r .configuration_hash); [ "$h1" = "$h0" ] && note=unchanged || note="updated from Konnect"
printf '  kong_control_plane_connected %s%s%s %s· configuration %s… (%s)%s\n' "$B" "$(cp_connected)" "$R" "$D" "${h1:0:8}" "$note" "$R"

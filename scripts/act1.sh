#!/usr/bin/env bash
# ACT 1 · Connect the factory: one governed endpoint, site + model failover. (The Konnect cut is the finale.)
. "$(dirname "$0")/lib/common.sh"
Q="In one sentence: what does a bank KYC check verify?"

banner "ACT 1 · CONNECT THE FACTORY" "one governed endpoint · DC1 → DR failover"
step "Aisha's copilot calls one endpoint, gnb-assistant. Behind it: DC1 (primary) and DC2 (DR, smaller model)."
ask "Aisha · retail-copilot" KEY_AISHA gnb-assistant - "$Q"

step "Taking DC1 down."
show "scripts/factory.sh stop dc1"; scripts/factory.sh stop dc1

step "Same request, same app, nothing changed on the client."
ask "Aisha · retail-copilot" KEY_AISHA gnb-assistant - "$Q"

step "Bringing DC1 back. The circuit breaker lets it back in once it's healthy."
show "scripts/factory.sh start dc1"; scripts/factory.sh start dc1
printf '\n%sThe Konnect cut comes at the end.%s\n' "$D" "$R"

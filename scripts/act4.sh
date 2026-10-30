#!/usr/bin/env bash
# ACT 4 · Extend to agents: bank APIs as governed MCP tools; the identity decides what an agent may do.
. "$(dirname "$0")/lib/common.sh"
TASK="Customer CUST-1001 says the card ending 4242 was stolen. Check the card and the customer's KYC, then block the card."
T_START=$(now_ms)
banner "ACT 4 · EXTEND TO AGENTS" "bank APIs as governed tools · the identity decides, not the code"

step "Your card-services API as MCP tools. What does each identity see?"
show "MCP tools/list  →  $GW/mcp/card-services"
tools "Card-ops agent · card-ops-agent" KEY_CARD_OPS_AGENT
tools "Khalid · card-ops-supervisor" KEY_KHALID

step "A real agent, on behalf of officer Noura: \"$TASK\""
show "agent/card_ops_agent.py --as agent --on-behalf-of noura.cardops \"…\""
python3 -I agent/card_ops_agent.py --as agent --on-behalf-of noura.cardops "$TASK"
printf '  %scard 4242 is now: %s%s\n' "$D" "$(curl -s localhost:18080/cards/4242/status | jq -r .status)" "$R"

step "Same agent code, delegated by supervisor Khalid."
show "agent/card_ops_agent.py --as khalid --on-behalf-of khalid.supervisor \"…\""
python3 -I agent/card_ops_agent.py --as khalid --on-behalf-of khalid.supervisor \
  "Confirmed stolen by the customer on a recorded call. Block card 4242 for customer CUST-1001."
printf '  %scard 4242 is now: %s%s\n' "$D" "$(curl -s localhost:18080/cards/4242/status | jq -r .status)" "$R"

step "Every tool call authenticated and audited: which agent, on behalf of whom, which tool, allowed or denied."
show "docker compose logs kong-dp | jq …  (MCP audit → your SIEM in production)"
audit_mcp "$T_START"

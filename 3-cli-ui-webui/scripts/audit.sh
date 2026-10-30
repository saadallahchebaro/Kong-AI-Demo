#!/usr/bin/env bash
# The audit trail behind GNB Assist: one line per call (who, use case, model, tokens, cost, PII, verdict), then the MCP tool calls.
#   audit.sh [minutes]   (default 10)
. "$(dirname "$0")/lib.sh"
since=$(( $(date +%s) * 1000 - ${1:-10} * 60000 ))
banner "AUDIT" "one line per call · no prompt text"
show "docker compose logs kong-dp | jq …  (file-log policy → your SIEM in production)"; audit "$since"
show "MCP tool calls"; audit_mcp "$since"

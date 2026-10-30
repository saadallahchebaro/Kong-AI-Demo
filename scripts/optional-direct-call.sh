#!/usr/bin/env bash
# Optional buffer beat: the agent calls block_card directly, bypassing its own tool list. Kong refuses.
. "$(dirname "$0")/lib/common.sh"
step "Even if the agent tried block_card directly:"
show "MCP tools/call block_card {path_card_id: 4242}  as card-ops-agent-01"
python3 -I - "$KEY_CARD_OPS_AGENT" <<'PY'
import sys; sys.path.insert(0, "agent")
from mcp_client import MCP, MCPHTTPError
c = MCP("http://localhost:8000/mcp/card-services", sys.argv[1], end_user="noura.cardops"); c.initialize()
try:
    c.call_tool("block_card", {"path_card_id": "4242"}); print("  \033[31munexpected: allowed\033[0m")
except MCPHTTPError as e:
    print(f"  \033[31m← {e.status} Forbidden\033[0m · the call never reached the bank API")
PY

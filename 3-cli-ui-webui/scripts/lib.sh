# Helpers for scenario 3 (GNB Assist). Sources the shared stack's helpers read-only (and cd's to the repo root, like them).
# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)/common.sh"
SCEN="$ROOT/3-cli-ui-webui"
WEBUI_DIR="$SCEN/webui"

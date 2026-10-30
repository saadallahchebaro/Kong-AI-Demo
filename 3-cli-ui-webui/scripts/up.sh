#!/usr/bin/env bash
# Start GNB Assist (Open WebUI, branded) and configure it: personas, assistants, agents, the GNB AI Gateway pipe. Safe to re-run.
#   3-cli-ui-webui/scripts/up.sh            then  3-cli-ui-webui/scripts/open.sh aisha   (a signed-in window per persona)
set -euo pipefail
. "$(dirname "$0")/lib.sh"
[ -f "$WEBUI_DIR/.personas.env" ] || python3 "$WEBUI_DIR/personas.py"
python3 "$WEBUI_DIR/login.py"   # the sign-in page's persona picker
docker compose -f "$WEBUI_DIR/docker-compose.yml" up -d --build 2>&1 | grep -E "Started|Running|Built|Error" || true
python3 "$WEBUI_DIR/setup.py"
printf '\n%sGNB Assist: http://localhost:3000%s · personas: aisha layla omar noura khalid (scripts/open.sh <persona>)\n' "$B" "$R"

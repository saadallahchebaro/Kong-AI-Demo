#!/usr/bin/env bash
# Shut the demo down (the Run tab's "Shut down"): the stage windows, the architecture page, GNB Assist, the Docker stack and the
# factory. Nothing is deleted: containers are stopped, not removed; chats, config and the Konnect sign-in stay.
# The panes server stops last, so the Run tab can show this; double-click "GNB demo" in the main folder to start again.
. "$(dirname "$0")/lib.sh"
echo "▶ stage windows";    pkill -f "user-data-dir=$ROOT/run/gnb-assist/" && echo "  closed" || echo "  none open"
echo "▶ architecture page"; pkill -f "arch/live.py" && echo "  stopped" || echo "  not running"
echo "▶ GNB Assist";       "$SCEN/scripts/down.sh" 2>&1 | sed 's/^/  /'
echo "▶ docker stack";     docker compose stop 2>&1 | sed 's/^/  /'
echo "▶ factory";          scripts/factory.sh stop all 2>&1 | sed 's/^/  /'
printf '\n%s✓ demo shut down%s · nothing deleted · double-click "GNB demo" to start again\n' "$GRN" "$R"
if [ "${1:-}" != "--keep-panes" ]; then   # the panes server stops 3 s after this script ends, so the Run tab sees it finish
  (sleep 3; pkill -f "3-cli-ui-webui/panes/panes.py") >/dev/null 2>&1 &
fi

#!/usr/bin/env bash
# The live panes beside GNB Assist: DC1, DC2 and the GNB AI Gateway (Kong), updating the moment each call happens.
#   panes.sh            start the panes server (http://localhost:8098) in the background, if it isn't running
#   panes.sh --open [x,y,w,h]   … and open the Live view as its own window, for the shared screen (stage.sh places it)
#   panes.sh --run              … and open the Run tab (the shortcuts) in your default browser: keep that one off the shared screen
#   panes.sh --stop     stop the server
. "$(dirname "$0")/lib.sh"
LOG="$ROOT/run/gnb-assist/panes.log"; mkdir -p "$ROOT/run/gnb-assist"
up() { curl -s -o /dev/null http://localhost:8098/events?since=0; }
case "${1:-}" in
  --stop) pkill -f "3-cli-ui-webui/panes/panes.py" && echo "panes stopped"; exit 0 ;;
esac
if ! up; then
  nohup python3 "$SCEN/panes/panes.py" >> "$LOG" 2>&1 &
  for _ in $(seq 1 30); do up && break; sleep 0.2; done
fi
up && echo "Live panes: http://localhost:8098  · the shortcuts: http://localhost:8098/?run" || { echo "panes didn't start (see $LOG)"; exit 1; }
if [ "${1:-}" = "--open" ]; then
  node "$SCEN/scripts/window.mjs" panes 9349 "http://localhost:8098/?live" ${2:-} --exact
fi
[ "${1:-}" = "--run" ] && open "http://localhost:8098/?run"
exit 0

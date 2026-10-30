#!/usr/bin/env bash
# The architecture page on the stage (the Run tab's "Architecture page"): its live server (arch/live.py, :8099) if it isn't
# running, then the page in its own window at GNB Assist's spot, in front. A persona shortcut brings the chat back.
. "$(dirname "$0")/lib.sh"
up() { curl -s -o /dev/null --max-time 1 http://127.0.0.1:8099/; }
if ! up; then
  nohup python3 arch/live.py >> "$ROOT/run/arch-live.log" 2>&1 &
  for _ in $(seq 1 160); do up && break; sleep 0.25; done   # it builds the page from the deployed config first (~15 s)
fi
up || { echo "the architecture page didn't start (see run/arch-live.log)"; exit 1; }
AT=$(python3 -c 'import json; print(",".join(map(str, json.load(open("run/gnb-assist/stage.json"))["assist"])))' 2>/dev/null)
node "$SCEN/scripts/window.mjs" arch 9347 http://localhost:8099/ ${AT:-} --exact --front && echo "architecture page in front"

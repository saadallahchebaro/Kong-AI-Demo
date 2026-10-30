#!/usr/bin/env bash
# Start the demo from nothing (the Run tab's "Start the demo"): Docker Desktop if it's closed, the factory and the Docker stack
# at baseline (the shared reset), GNB Assist (up.sh), then the stage windows (stage.sh). Safe to re-run.
#   start.sh [persona]     default aisha
. "$(dirname "$0")/lib.sh"
if ! docker info >/dev/null 2>&1; then
  echo "▶ Docker Desktop"; open -a Docker
  for _ in $(seq 1 90); do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker info >/dev/null 2>&1 && echo "  ${GRN}✓ running${R}" || { echo "  ${RED}✗ Docker didn't start${R}"; exit 1; }
fi
scripts/reset.sh || exit 1
echo "▶ GNB Assist"; "$SCEN/scripts/up.sh" | sed 's/^/  /' || exit 1
echo "▶ stage windows"; "$SCEN/scripts/stage.sh" "${1:-aisha}" | sed 's/^/  /'
printf '\n%s✓ demo started%s · next: Pre-flight\n' "$GRN" "$R"

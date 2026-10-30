#!/usr/bin/env bash
# Cut or restore "GNB data centre → Konnect" by stopping/starting the egress proxy.
# Only the data plane's control-plane and telemetry connections use it; AI traffic never does.
# Usage: scripts/konnect-cut.sh stop|start|status
set -uo pipefail
cd "$(dirname "$0")/.."
case "${1:-status}" in
  stop)
    docker compose stop konnect-egress >/dev/null 2>&1 && echo "Konnect link CUT at $(date +%T)" ;;
  start)
    docker compose start konnect-egress >/dev/null 2>&1 && echo "Konnect link restored at $(date +%T); waiting for the data plane to reconnect…"
    for i in $(seq 1 40); do
      docker compose logs --no-log-prefix --since 60s konnect-egress 2>/dev/null | grep -q "OPEN .*\.cp\.konghq\.com" && { echo "reconnected after ${i}s"; exit 0; }
      sleep 1
    done
    echo "WARNING: no reconnect seen after 40 s" ;;
  status)
    docker compose ps --format '{{.Service}} {{.State}}' konnect-egress ;;
esac

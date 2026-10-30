#!/usr/bin/env bash
# ACT 1 in GNB Assist: take the primary site down (dc1.sh down), then bring it back (dc1.sh up). Aisha keeps chatting.
. "$(dirname "$0")/lib.sh"
case "${1:-}" in
  down) banner "ACT 1 · CONNECT THE FACTORY" "DC1 down · the same chat keeps working"; show "scripts/factory.sh stop dc1"; scripts/factory.sh stop dc1 ;;
  up)   show "scripts/factory.sh start dc1"; scripts/factory.sh start dc1; printf '  %sthe circuit breaker lets DC1 back in after about 10 s%s\n' "$D" "$R" ;;
  *)    echo "usage: dc1.sh down|up"; exit 2 ;;
esac

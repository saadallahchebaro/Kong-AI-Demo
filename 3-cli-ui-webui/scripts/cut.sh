#!/usr/bin/env bash
# FINALE in GNB Assist: cut the data centre's only route to Konnect (cut.sh), chat on, then restore it (cut.sh restore).
. "$(dirname "$0")/lib.sh"
cp_connected() { curl -s "$STATUS/metrics" | awk '/^kong_control_plane_connected/ {print $2}'; }
case "${1:-stop}" in
  stop)
    banner "FINALE · UNPLUG KONNECT" "the controls run in your data centre, not in the SaaS"
    show "scripts/konnect-cut.sh stop"; printf '  %s%s%s\n' "$RED" "$(scripts/konnect-cut.sh stop)" "$R"
    sleep 1; h=$(curl -s "$STATUS/status" | jq -r .configuration_hash)
    printf '  kong_control_plane_connected %s%s%s %s· configuration %s… (last-known, cached on the data plane)%s\n' "$B" "$(cp_connected)" "$R" "$D" "${h:0:8}" "$R" ;;
  restore)
    h0=$(curl -s "$STATUS/status" | jq -r .configuration_hash)
    show "scripts/konnect-cut.sh start"; scripts/konnect-cut.sh start | sed 's/^/  /'
    h1=$(curl -s "$STATUS/status" | jq -r .configuration_hash); [ "$h1" = "$h0" ] && note=unchanged || note="updated from Konnect"
    printf '  kong_control_plane_connected %s%s%s %s· configuration %s… (%s)%s\n' "$B" "$(cp_connected)" "$R" "$D" "${h1:0:8}" "$note" "$R" ;;
  *) echo "usage: cut.sh [stop|restore]"; exit 2 ;;
esac

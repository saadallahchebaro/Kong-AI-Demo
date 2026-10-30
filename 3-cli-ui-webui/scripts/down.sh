#!/usr/bin/env bash
# Stop GNB Assist (its data stays in the gnb-assist_gnb-assist-data volume).
. "$(dirname "$0")/lib.sh"
docker compose -f "$WEBUI_DIR/docker-compose.yml" stop

#!/usr/bin/env bash
# Pre-flight for scenario 3: the shared pre-flight (stack, factory, Kong, Konnect, MCP), then GNB Assist's own checks.
. "$(dirname "$0")/lib.sh"
scripts/preflight.sh || exit 1
printf '\n%s▶ GNB Assist%s\n' "$B" "$R"
python3 "$SCEN/scripts/check.py" --quick

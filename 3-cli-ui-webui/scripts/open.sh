#!/usr/bin/env bash
# Open GNB Assist as a persona, in its own Chrome window (own profile, already signed in). One window per persona on stage.
#   open.sh aisha|layla|omar|noura|khalid [x,y,w,h]
. "$(dirname "$0")/lib.sh"
node "$SCEN/scripts/open-persona.mjs" "${1:?usage: open.sh aisha|layla|omar|noura|khalid [x,y,w,h]}" ${2:-}

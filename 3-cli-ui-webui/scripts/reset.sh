#!/usr/bin/env bash
# Back to the baseline for scenario 3: the shared reset (bundle off, 13th use case removed, budgets and cache cleared,
# card 4242 active, models warm), then every persona's chats cleared so GNB Assist starts empty.
. "$(dirname "$0")/lib.sh"
git checkout -q -- kong/40-models.yaml   # an Act 1 round-robin left on: back to Git before the reset syncs kong/
scripts/reset.sh
python3 "$WEBUI_DIR/setup.py" --clear-chats
node "$SCEN/scripts/refresh-personas.mjs" || true   # open persona windows start on a new, empty chat

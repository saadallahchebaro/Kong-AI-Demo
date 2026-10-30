#!/usr/bin/env bash
# Build "GNB demo.app" in the main folder from GNB demo.applescript, with the GNB mark as its icon (macOS tools only:
# osacompile, sips, iconutil, codesign). Re-run after editing the script. The app is git-ignored; this script and the source are not.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"; APP="$ROOT/GNB demo.app"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
rm -rf "$APP"; osacompile -o "$APP" "$HERE/GNB demo.applescript"
SRC="$ROOT/3-cli-ui-webui/webui/brand/static/favicon.png"; SET="$TMP/gnb.iconset"; mkdir "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$SRC" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$SRC" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o "$APP/Contents/Resources/applet.icns"
codesign --force --sign - "$APP" 2>/dev/null   # re-seal it locally (the new icon changed its resources)
touch "$APP"   # so Finder shows the new icon
echo "✓ $(basename "$APP") in the main folder: double-click it to open the Run tab"

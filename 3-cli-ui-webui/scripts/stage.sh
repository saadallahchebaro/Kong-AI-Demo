#!/usr/bin/env bash
# The stage layout on one screen: GNB Assist as the persona on the left, the live panes (DC1, DC2, Kong) on the right. Share that screen;
# on a screen wider than 16:9 the stage is a 16:9 area at its top-left: share that portion, so viewers' text stays readable.
# The Konnect window sits behind GNB Assist, at the same spot; the Run tab's Konnect shortcuts bring it forward, a persona shortcut sends it back.
#   stage.sh aisha [screen]      default: the widest display (share that one; keep the Run tab on another). screen: 0 = the main
#                                display, 1 = the next one …; a screen given here is remembered until "stage.sh aisha auto"
#   Switch persona: stage.sh noura   (the same spot; each persona keeps its own window and chat)
#   GNB_MODEL=gnb_gateway.retail-copilot stage.sh aisha   … and start a new chat with that assistant (the Run tab's chat steps)
. "$(dirname "$0")/lib.sh"
WHO="${1:?usage: stage.sh aisha|layla|omar|noura|khalid [screen]}"
SAVED="$ROOT/run/gnb-assist/stage.screen"; mkdir -p "$ROOT/run/gnb-assist"
case "${2:-}" in auto) rm -f "$SAVED"; SCREEN=widest ;; "") SCREEN="$(cat "$SAVED" 2>/dev/null || echo widest)" ;; *) SCREEN="$2"; echo "$2" > "$SAVED" ;; esac
# each screen's usable area (below the menu bar, above the Dock) as x,y,w,h in Chrome's top-left coordinates
# (a display can report no menu bar in its usable area while macOS still keeps windows below it: then the main display's applies)
FRAMES=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); const S = $.NSScreen.screens, M = S.objectAtIndex(0), H = M.frame.size.height, o = [];
  const bar = (M.frame.origin.y + M.frame.size.height) - (M.visibleFrame.origin.y + M.visibleFrame.size.height);
  for (let i = 0; i < S.count; i++) { const f = S.objectAtIndex(i).frame, v = S.objectAtIndex(i).visibleFrame;
    const top = Math.max((f.origin.y + f.size.height) - (v.origin.y + v.size.height), bar), vt = f.origin.y + f.size.height - top;
    o.push([v.origin.x, H - vt, v.size.width, vt - v.origin.y].map(Math.round).join(",")); } o.join(" ")')
read -r -a F <<< "$FRAMES"
if [ "$SCREEN" = widest ]; then  # the widest display (on one display: that one)
  SCREEN=0; for i in "${!F[@]}"; do IFS=, read -r _ _ w _ <<< "${F[$i]}"; IFS=, read -r _ _ bw _ <<< "${F[$SCREEN]}"; [ "$w" -gt "$bw" ] && SCREEN=$i; done
fi
[ -n "${F[$SCREEN]:-}" ] || { echo "no screen $SCREEN (screens: $FRAMES)"; exit 1; }
IFS=, read -r X Y W H <<< "${F[$SCREEN]}"
SW=$W; [ $(( W * 9 )) -gt $(( H * 16 )) ] && W=$(( H * 16 / 9 ))   # wider than 16:9 (an ultrawide): a 16:9 area at its left, to share
AW=$(( W * 62 / 100 ))
echo "screen $SCREEN: ${SW}×${H} · stage area ${W}×${H} at its top-left$([ "$W" != "$SW" ] && echo ' (16:9: share this portion)') · GNB Assist ${AW} wide, live panes $(( W - AW )) wide"
printf '{"assist": [%s,%s,%s,%s], "panes": [%s,%s,%s,%s]}\n' "$X" "$Y" "$AW" "$H" "$(( X + AW ))" "$Y" "$(( W - AW ))" "$H" > "$ROOT/run/gnb-assist/stage.json"
"$SCEN/scripts/panes.sh" --open "$(( X + AW )),$Y,$(( W - AW )),$H" >/dev/null
node "$SCEN/scripts/konnect.mjs" >/dev/null || echo "  the Konnect window is on Konnect's sign-in page: sign in there once"
curl -s -o /dev/null --max-time 1 http://127.0.0.1:9347/json/version && node "$SCEN/scripts/window.mjs" arch 9347 http://localhost:8099/ "$X,$Y,$AW,$H"   # the architecture window, if open
node "$SCEN/scripts/open-persona.mjs" "$WHO" "$X,$Y,$AW,$H" ${GNB_MODEL:+"$GNB_MODEL"}   # GNB_MODEL: open a new chat with that assistant

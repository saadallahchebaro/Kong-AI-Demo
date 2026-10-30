#!/usr/bin/env bash
# ACT 1 in GNB Assist, after the failover: active load balancing between the sites, then back.
#   lb.sh round-robin   DC1 and DC2 share the GNB Assistant's traffic 50/50 (a Git change: the balancer, and DC2's weight)
#   lb.sh failover      back to the Git baseline: priority, DC1 serves and DC2 waits (reset.sh restores it too)
. "$(dirname "$0")/lib.sh"
FILE=kong/40-models.yaml; FILES=(-f kong/10-providers.yaml -f kong/20-auth.yaml -f "$FILE" -f kong/50-policies.yaml)   # what the models refer to
case "${1:-}" in
  round-robin)
    banner "ACT 1 · ACTIVE-ACTIVE" "DC1 and DC2 share the traffic: round-robin"
    if git diff --quiet -- "$FILE"; then
      python3 -I - "$FILE" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = s.index("  - ref: gnb-assistant"); b = s.index("  - ref: gnb-copilot")   # only the GNB Assistant's block
blk = s[a:b]
for old, new in (("        algorithm: priority", "        algorithm: round-robin"),
                 ("        weight: 10\n", "        weight: 100\n")):   # DC2: same weight as DC1, so 50/50
    assert blk.count(old) == 1, f"not found once: {old.strip()}"; blk = blk.replace(old, new)
open(p, "w").write(s[:a] + blk + s[b:])
PY
    else printf '  %sthe balancer is already changed in %s%s\n' "$D" "$FILE" "$R"; fi ;;
  failover)
    banner "ACT 1 · BACK TO FAILOVER" "priority: DC1 serves, DC2 is the DR site"
    git diff --quiet -- "$FILE" && printf '  %s%s already matches Git%s\n' "$D" "$FILE" "$R"
    show "git diff $FILE (what goes back)"; git --no-pager diff --color=always -R "$FILE" | sed -n '5,$p'
    git checkout -q -- "$FILE" ;;
  *) echo "usage: lb.sh round-robin|failover"; exit 2 ;;
esac
[ "$1" = round-robin ] && { show "git diff $FILE"; git --no-pager diff --color=always "$FILE" | sed -n '5,$p'; }
show "kongctl diff --mode apply -f $FILE"; scripts/kctl diff --mode apply "${FILES[@]}" 2>&1 | grep -E "^\s+[~+-]|will be|No changes" | head -6
h0=$(curl -s "$STATUS/status" | jq -r .configuration_hash); t0=$(now_ms)
show "kongctl apply -f $FILE"; scripts/kctl apply "${FILES[@]}" --auto-approve 2>&1 | grep -E "✓|✗|Error" | sed 's/^/  /'
t1=$(now_ms); if wait_config "$h0"; then sleep 2   # let both workers pick it up
  printf '  %s✓ applied in %.1fs · live on the data plane %.1fs later%s\n' "$GRN" "$(echo "($t1-$t0)/1000" | bc -l)" "$(echo "($(now_ms)-$t1)/1000" | bc -l)" "$R"
else printf '  %s! config not seen on the data plane yet (or nothing changed)%s\n' "$YEL" "$R"; fi

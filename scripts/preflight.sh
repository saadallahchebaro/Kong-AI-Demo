#!/usr/bin/env bash
# Pre-flight before every rehearsal and on panel day (T-45, and again after reset.sh at T-15).
# Read-only apart from three tiny probe calls (as Layla and the card-ops agent, hidden from the audit view);
# the semantic cache they touch is flushed again at the end. Every check green, or it exits 1.
. "$(dirname "$0")/lib/common.sh"
fails=0; warns=0
ok()   { printf '  %s✓%s %s\n' "$GRN" "$R" "$1"; }
bad()  { printf '  %s✗ %s%s%s\n' "$RED" "$1" "${2:+ · $2}" "$R"; fails=$((fails+1)); }
warn() { printf '  %s⚠ %s%s\n' "$YEL" "$1" "$R"; warns=$((warns+1)); }
chk()  { local what="$1" hint="$2"; shift 2; if "$@" >/dev/null 2>&1; then ok "$what"; else bad "$what" "$hint"; fi; }
probe() {  # probe <key-var> <model> [json-extra]: one chat call via Kong; prints "code model" and keeps the body in run/probe.json
  local extra="${3:-}"; [ -n "$extra" ] || extra='{}'
  curl -s -m 60 -D run/probe.h -o run/probe.json -w '%{http_code}' "$GW/v1/chat/completions" -H 'Content-Type: application/json' \
    -H "apikey: ${!1}" -H 'X-End-User: readiness-probe' -d "$(jq -n --arg m "$2" --argjson x "$extra" \
    '{model:$m,messages:[{role:"user",content:"Preflight check. Reply with the single word OK."}]} + $x')"
  printf ' %s' "$(grep -i '^x-kong-llm-model:' run/probe.h | cut -d' ' -f2- | tr -d '\r')"
}

banner "PRE-FLIGHT" "every check green before the panel"

echo "▶ the Mac"
for s in kong-dp konnect-egress redis pii-service card-services; do
  chk "container $s running" "docker compose up -d" test "$(docker compose ps --format '{{.State}}' "$s")" = running
done
for n in ollama dc1 dc2; do chk "factory: $n up" "scripts/factory.sh start all" sh -c "scripts/factory.sh status $n | grep -q ': up'"; done
loaded=$(curl -s -m 5 http://127.0.0.1:11434/api/ps | jq -r '[.models[].name] | join(" ")')
for m in qwen2.5:7b qwen2.5:1.5b nomic-embed-text; do
  [[ " $loaded " == *" $m"* ]] && ok "model $m warm (loaded in Ollama)" || bad "model $m not loaded" "scripts/reset.sh warms it"
done
free=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/ {print $2+0}')
[ -n "$free" ] && { [ "$free" -ge 15 ] && ok "memory: ${free}% free" || warn "memory: only ${free}% free · close apps (call app: test at T-90)"; }

echo "▶ data plane and Konnect"
chk "data plane status endpoint" "docker compose up -d kong-dp" curl -sf -m 3 "$STATUS/status"
v=$(curl -s -m 3 "$STATUS/metrics" | sed -n 's/^kong_node_info{.*version="\([^"]*\)".*/\1/p')
[ "$v" = 2.2.0 ] && ok "data plane version 2.2.0" || bad "data plane version is '${v:-?}'" "must stay 2.2.0 (matches the control plane)"
[ "$(curl -s -m 3 "$STATUS/metrics" | awk '/^kong_control_plane_connected/ {print $2}')" = 1 ] \
  && ok "connected to Konnect (kong_control_plane_connected 1)" || bad "not connected to Konnect" "scripts/konnect-cut.sh start"
git diff --quiet -- kong/ onboard/ && ok "kong/ and onboard/ match Git (bundle off in the file)" || bad "uncommitted changes in kong/ or onboard/" "scripts/reset.sh restores kong/36-retail-copilot.yaml"
d=$(scripts/kctl diff -f kong/ 2>&1 | tail -1)
[[ "$d" == *"No changes detected"* ]] && ok "Konnect matches Git exactly (kongctl diff -f kong/)" || bad "Konnect differs from Git: $d" "scripts/reset.sh"

echo "▶ policies' dependencies"
[ "$(docker compose exec -T redis redis-cli ping 2>/dev/null | tr -d '\r')" = PONG ] && ok "Redis answers" || bad "Redis down" "docker compose up -d redis"
dims=$(curl -s -m 20 http://127.0.0.1:11434/api/embed -d '{"model":"nomic-embed-text","input":"ok","keep_alive":-1}' | jq '.embeddings[0] | length')
[ "$dims" = 768 ] && ok "embeddings answer (768 dimensions)" || bad "embeddings failed" "the semantic guards fail closed without them"
st=$(docker compose exec -T pii-service python3 -c "import urllib.request as u; print(u.urlopen('http://localhost:8080/llm/v1/status', timeout=5).read().decode())" 2>/dev/null)
[[ "$st" == *'"ok"'* ]] && ok "PII service ok" || bad "PII service not ok" "docker compose restart pii-service"
c=$(curl -s -m 5 localhost:18080/cards/4242/status | jq -r .status)
[ "$c" = active ] && ok "card-services mock: card 4242 active" || bad "card 4242 is '${c:-?}'" "scripts/reset.sh"

echo "▶ through Kong"
r=$(probe KEY_LAYLA gnb-assistant); [[ "$r" == "200 "*qwen2.5:7b* ]] && ok "gnb-assistant answers on DC1 ($r)" || bad "gnb-assistant: $r"
r=$(probe KEY_LAYLA gnb-copilot); [[ "$r" == "200 "* ]] && ok "gnb-copilot answers ($r)" || bad "gnb-copilot: $r"
tool='{"tools":[{"type":"function","function":{"name":"get_card_status","description":"Get a card status","parameters":{"type":"object","properties":{"path_card_id":{"type":"string"}},"required":["path_card_id"]}}}],"messages":[{"role":"user","content":"What is the status of card 4242?"}]}'
r=$(probe KEY_CARD_OPS_AGENT gnb-agent-llm "$tool"); n=$(jq '.choices[0].message.tool_calls | length' run/probe.json 2>/dev/null)
if [[ "$r" == "200 "*gpt-5.5* ]] && [ "${n:-0}" -ge 1 ]; then ok "gnb-agent-llm calls a tool on gpt-5.5 ($r)"
elif [[ "$r" == "200 "* ]]; then warn "gnb-agent-llm answered on the fallback ($r, $n tool calls) · OpenAI unreachable? Say so in Act 4"
else bad "gnb-agent-llm: $r"; fi
t=$(tools "agent" KEY_CARD_OPS_AGENT | sed 's/\x1b\[[0-9;]*m//g')
[[ "$t" == *": escalate_to_supervisor, get_card_status, get_kyc_status" ]] && ok "MCP: the agent sees 3 tools, no block_card" || bad "MCP agent tools: ${t#*: }"
t=$(tools "khalid" KEY_KHALID | sed 's/\x1b\[[0-9;]*m//g')
[[ "$t" == *": block_card, escalate_to_supervisor, get_card_status, get_kyc_status" ]] && ok "MCP: the supervisor sees 4 tools" || bad "MCP supervisor tools: ${t#*: }"
docker compose exec -T redis sh -c "redis-cli --scan --pattern 'semantic_cache:*' | xargs -r redis-cli del" >/dev/null 2>&1
ok "semantic cache flushed again after the probes"

echo "▶ backups"
missing=""; for f in act1 act2 act3 act4 onboard; do [ -s "recordings/$f.mov" ] || missing="$missing $f.mov"; done
[ -z "$missing" ] && ok "recordings present" || warn "recordings missing:$missing"

echo
if [ "$fails" = 0 ]; then printf '%s✓ PRE-FLIGHT GREEN%s · %s warning(s)\n' "$B$GRN" "$R" "$warns"; exit 0
else printf '%s✗ PRE-FLIGHT FAILED: %s check(s)%s · %s warning(s)\n' "$B$RED" "$fails" "$R" "$warns"; exit 1; fi

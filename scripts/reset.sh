#!/usr/bin/env bash
# Back to the demo baseline: factory up, Konnect link up, budget counters and cache cleared, 13th use case removed,
# bundle off, models warm.
. "$(dirname "$0")/lib/common.sh"
FILE=kong/36-retail-copilot.yaml
echo "▶ factory";        scripts/factory.sh start all | sed 's/^/  /'
echo "▶ docker stack";   docker compose up -d >/dev/null 2>&1 && docker compose ps --format '  {{.Service}}: {{.State}}'
echo "▶ Konnect link";   [ "$(docker compose ps --format '{{.State}}' konnect-egress)" = running ] && echo "  up" || scripts/konnect-cut.sh start
echo "▶ budget counters (restart data plane) and semantic cache"
docker compose restart kong-dp >/dev/null 2>&1
for i in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$STATUS/status")" = 200 ] && break; sleep 1; done
for i in $(seq 1 40); do docker compose logs --no-log-prefix --since 60s konnect-egress 2>/dev/null | grep -q "OPEN .*\.cp\.konghq\.com" && break; sleep 1; done
sleep 3; echo "  data plane restarted and reconnected"
n=$(docker compose exec -T redis sh -c "redis-cli --scan --pattern 'semantic_cache:*' | wc -l" | tr -d ' ')
docker compose exec -T redis sh -c "redis-cli --scan --pattern 'semantic_cache:*' | xargs -r redis-cli del" >/dev/null; echo "  flushed $n cache entries (routing and guard indexes kept)"
echo "▶ mock card-services (card 4242 active again)"
curl -s -m 5 -X POST localhost:18080/admin/reset >/dev/null && echo "  reset"
echo "▶ config back to Git: bundle off, 13th use case removed (kongctl sync -f kong/, reviewed plan)"
git checkout -q -- "$FILE"
h0=$(curl -s "$STATUS/status" | jq -r .configuration_hash); PLAN=run/reset-plan.json
scripts/kctl plan --mode sync -f kong/ --output-file "$PLAN" >/dev/null 2>&1 || { echo "  ! kongctl plan failed"; exit 1; }
# sync deletes whatever isn't in kong/: refuse unless the only deletions are the 13th use case's own objects
extra=$(jq -r '.changes[] | select(.action == "DELETE") | "\(.resource_type):\(.resource_ref)"
  | select(. != "ai_gateway_consumer:omar" and . != "ai_gateway_consumer_group:complaints-copilot")' "$PLAN")
[ -n "$extra" ] && { echo "  ! sync would also delete: $extra · aborted, nothing changed"; exit 1; }
n=$(jq '.changes | length' "$PLAN")
if [ "$n" -gt 0 ]; then
  jq -r '.changes[] | "  \(.action | ascii_downcase) \(.resource_type | sub("ai_gateway_"; "")) \(.resource_ref)"' "$PLAN"
  scripts/kctl sync --plan "$PLAN" --auto-approve >/dev/null 2>&1 && wait_config "$h0" && echo "  applied" || { echo "  ! sync failed"; exit 1; }
else echo "  already at baseline"; fi
echo "▶ warm models (DC1 7B, DR 1.5B, embeddings)"
for m in qwen2.5:7b qwen2.5:1.5b; do
  curl -s -m 60 http://127.0.0.1:11434/api/generate -d "{\"model\":\"$m\",\"prompt\":\"ok\",\"stream\":false,\"keep_alive\":-1,\"options\":{\"num_predict\":1}}" >/dev/null && echo "  $m warm"
done
curl -s -m 30 http://127.0.0.1:11434/api/embed -d '{"model":"nomic-embed-text","input":"ok","keep_alive":-1}' >/dev/null && echo "  nomic-embed-text warm"
echo "✓ baseline ready"

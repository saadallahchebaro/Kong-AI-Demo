#!/usr/bin/env bash
# One-time setup on a Mac: checks the tools, writes .env and the demo's API keys, checks the data plane certificate and
# your Konnect AI Gateway, pulls the models and builds the "GNB demo" launcher. Safe to re-run: it keeps what's there.
#   ./setup.sh
# Values can also come from the environment for a run without prompts: KONNECT_TOKEN=… AI_GATEWAY_ID=… ./setup.sh
set -uo pipefail
cd "$(dirname "$0")"
B=$'\e[1m'; R=$'\e[0m'; GRN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m'
FAIL=0
ok()   { echo "  ${GRN}✓${R} $*"; }
bad()  { echo "  ${RED}✗${R} $*"; FAIL=1; }
warn() { echo "  ${YEL}!${R} $*"; }
OLLAMA=/opt/homebrew/opt/ollama/bin/ollama   # the one scripts/factory.sh runs
MODELS="qwen2.5:7b qwen2.5:1.5b nomic-embed-text"
KEYS="AISHA LAYLA CARD_OPS_AGENT KHALID CREDIT_MEMO KNOWLEDGE OMAR"   # one per app or identity (kong/30-consumers.yaml)

echo "${B}▶ tools${R}"
[ "$(uname)" = Darwin ] && ok "macOS" || bad "macOS only: the stage windows and the launcher use AppleScript"
docker info >/dev/null 2>&1 && ok "Docker running" || bad "Docker Desktop: install it and start it (docker.com/products/docker-desktop)"
[ -x "$OLLAMA" ] && ok "Ollama" || bad "Ollama: brew install ollama"
v=$(kongctl version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -n "$v" ] && [ "$(printf '%s\n' 1.20.2 "$v" | sort -V | head -1)" = 1.20.2 ] && ok "kongctl $v" \
  || bad "kongctl 1.20.2 or later: brew install --formula kong/kongctl/kongctl"
python3 -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>/dev/null && ok "Python $(python3 -c 'import platform; print(platform.python_version())')" \
  || bad "Python 3.9 or later: brew install python"
n=$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null)
[ "${n:-0}" -ge 22 ] && ok "Node $(node -v)" || bad "Node 22 or later (its built-in WebSocket drives Chrome): brew install node"
[ -d "/Applications/Google Chrome.app" ] && ok "Google Chrome" || bad "Google Chrome in /Applications: the stage windows are Chrome windows"
[ "$FAIL" = 0 ] || { printf '\n%s✗ install what is missing, then run ./setup.sh again%s\n' "$RED" "$R"; exit 1; }

echo "${B}▶ .env${R}"
[ -f .env ] || { cp .env.example .env; ok "created .env from .env.example"; }
get() { sed -nE "s/^$1=(.*)$/\1/p" .env | tail -1; }
put() {  # set KEY=value in .env, keeping everything else
  python3 -I -c 'import pathlib, re, sys
p, (k, v) = pathlib.Path(".env"), sys.argv[1:]
s, line = p.read_text(), f"{k}={v}"
s = re.sub(rf"(?m)^{k}=.*$", lambda m: line, s) if re.search(rf"(?m)^{k}=", s) else s.rstrip("\n") + "\n" + line + "\n"
p.write_text(s)' "$1" "$2"
}
ask() {  # ask KEY "what it is" [secret]: keep a value already in .env, else take it from the environment, else ask
  local k=$1 v; [ -n "$(get "$k")" ] && { ok "$k is set"; return 0; }
  v="${!k:-}"
  if [ -z "$v" ] && [ -t 0 ]; then
    if [ "${3:-}" = secret ]; then read -rsp "  $2: " v; echo; else read -rp "  $2: " v; fi
  fi
  [ -n "$v" ] || return 1
  put "$k" "$v"; ok "$k saved"
}
ask KONNECT_TOKEN "Konnect personal access token (kpat_…)" secret || bad "KONNECT_TOKEN: create one in Konnect → your account → Personal access tokens"
ask AI_GATEWAY_ID "Your AI Gateway's id (in its Konnect URL: …/gateways/<id>)" || bad "AI_GATEWAY_ID: create an AI Gateway in Konnect (runtime 2.2) and copy its id"
if [ -z "$(get KONNECT_CP_HOST)" ]; then   # host name only, whatever was pasted
  cp_host="${KONNECT_CP_HOST:-}"
  [ -z "$cp_host" ] && [ -t 0 ] && read -rp "  Control plane endpoint (your AI Gateway → Data plane nodes, e.g. 1a2b3c4d5e.eu.cp.konghq.com): " cp_host
  cp_host=$(printf '%s' "$cp_host" | sed -E 's#^[a-z]+://##; s#[:/].*$##')
  if [[ "$cp_host" =~ ^[a-z0-9-]+\.[a-z]+\.cp\.konghq\.com$ ]]; then put KONNECT_CP_HOST "$cp_host"; ok "KONNECT_CP_HOST saved"
  else bad "KONNECT_CP_HOST: expected <id>.<region>.cp.konghq.com, from your AI Gateway's data plane node page"; fi
else ok "KONNECT_CP_HOST is set"; fi
cp_host=$(get KONNECT_CP_HOST)
if [ -n "$cp_host" ]; then   # the telemetry endpoint and the region follow from it
  [ -n "$(get KONNECT_TP_HOST)" ] || { put KONNECT_TP_HOST "${cp_host/.cp./.tp.}"; ok "KONNECT_TP_HOST saved (${cp_host/.cp./.tp.})"; }
  [ -n "$(get KONGCTL_DEFAULT_KONNECT_REGION)" ] || { put KONGCTL_DEFAULT_KONNECT_REGION "$(echo "$cp_host" | cut -d. -f2)"; ok "region: $(get KONGCTL_DEFAULT_KONNECT_REGION)"; }
fi
ask OPENAI_API_KEY "OpenAI API key, for the agent in Act 4 (Enter to skip)" secret || warn "OPENAI_API_KEY empty: Act 4's agent won't answer until you add it to .env"
for dc in DC1 DC2; do
  [ -n "$(get "GNB_NODE_$dc")" ] || put "GNB_NODE_$dc" "$(echo "$dc" | tr 'A-Z' 'a-z')-$(openssl rand -hex 8)"
done
ok "factory node headers"

echo "${B}▶ demo API keys (.env.demo-keys)${R}"
touch .env.demo-keys
for k in $KEYS; do grep -q "^KEY_$k=" .env.demo-keys || echo "KEY_$k=gnb-$(openssl rand -hex 16)" >> .env.demo-keys; done
ok "$(echo $KEYS | wc -w | tr -d ' ') keys, kept between runs (Kong stores each one when the consumer is created)"

echo "${B}▶ data plane certificate (certs/)${R}"
mkdir -p certs run
if [ -s certs/cluster.crt ] && [ -s certs/cluster.key ]; then
  end=$(openssl x509 -noout -enddate -in certs/cluster.crt 2>/dev/null | cut -d= -f2)
  if [ -z "$end" ]; then bad "certs/cluster.crt isn't a PEM certificate"
  elif [ "$(openssl x509 -noout -pubkey -in certs/cluster.crt | openssl sha256)" != "$(openssl pkey -in certs/cluster.key -pubout 2>/dev/null | openssl sha256)" ]; then
    bad "certs/cluster.key doesn't match certs/cluster.crt"
  elif ! openssl x509 -checkend 0 -noout -in certs/cluster.crt >/dev/null; then bad "certs/cluster.crt expired on $end"
  else ok "certificate and key match, valid until $end"; fi
else
  bad "no certificate yet. In Konnect, open your AI Gateway → Data plane nodes and add a node: Konnect generates a certificate and key.
     Save the certificate as certs/cluster.crt and the private key as certs/cluster.key, then run ./setup.sh again."
fi

echo "${B}▶ Konnect${R}"
token=$(get KONNECT_TOKEN); gw=$(get AI_GATEWAY_ID); region=$(get KONGCTL_DEFAULT_KONNECT_REGION)
if [ -n "$token" ] && [ -n "$gw" ]; then
  body=$(mktemp); trap 'rm -f "$body"' EXIT
  code=$(curl -s -o "$body" -w '%{http_code}' -H "Authorization: Bearer $token" "https://${region:-eu}.api.konghq.com/v1/ai-gateways/$gw")
  if [ "$code" = 200 ]; then
    gwf() { python3 -I -c 'import json, sys; g = json.load(open(sys.argv[1])); print(g.get(sys.argv[2]) or "")' "$body" "$1"; }
    ok "AI Gateway \"$(gwf display_name)\", runtime $(gwf min_runtime_version)"
    [[ "$(gwf min_runtime_version)" == 2.2* ]] \
      || warn "the data plane image is 2.2.0 (docker-compose.yml): set the gateway's runtime version to 2.2 so they match"
  else bad "Konnect answered $code for gateway $gw in region ${region:-eu}: check KONNECT_TOKEN, AI_GATEWAY_ID and the region in .env"; fi
else bad "Konnect not checked: KONNECT_TOKEN and AI_GATEWAY_ID are needed"; fi

echo "${B}▶ models (Ollama)${R}"
if [ -x "$OLLAMA" ]; then
  scripts/factory.sh start ollama | sed 's/^/  /'
  for _ in $(seq 1 40); do curl -s -m 1 http://127.0.0.1:11434/api/version >/dev/null && break; sleep 0.5; done
  have() { "$OLLAMA" list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qxE "$1(:latest)?"; }
  for m in $MODELS; do
    if have "$m"; then ok "$m"; else echo "  pulling $m"; "$OLLAMA" pull "$m" && ok "$m" || bad "couldn't pull $m"; fi
  done
fi

echo "${B}▶ GNB demo launcher${R}"
3-cli-ui-webui/launcher/build.sh >/dev/null 2>&1 && ok "\"GNB demo\" in this folder: double-click it to open the Run tab" \
  || warn "launcher not built: run 3-cli-ui-webui/launcher/build.sh"

echo
if [ "$FAIL" = 0 ]; then
  echo "${GRN}✓ set up${R} · next: double-click ${B}GNB demo${R}, then ${B}Start the demo${R} and ${B}Pre-flight${R} in the Run tab"
  echo "  (or 3-cli-ui-webui/scripts/start.sh). The first start downloads the container images and applies kong/ to Konnect."
else
  echo "${RED}✗ fix the items marked ✗, then run ./setup.sh again${R}"; exit 1
fi

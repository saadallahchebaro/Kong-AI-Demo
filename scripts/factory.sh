#!/usr/bin/env bash
# GNB "AI factory" on the laptop: Ollama (native, Metal GPU) plus the DC1/DC2 node endpoints.
# Usage: scripts/factory.sh start|stop|status [ollama|dc1|dc2|all]   (default: all)
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p run
OLLAMA=/opt/homebrew/opt/ollama/bin/ollama

pidfile() { echo "run/$1.pid"; }
running() { [ -f "$(pidfile "$1")" ] && kill -0 "$(cat "$(pidfile "$1")")" 2>/dev/null; }

start_one() {
  running "$1" && { echo "$1: already running"; return; }
  case "$1" in
    ollama)
      if curl -s -m 2 http://127.0.0.1:11434/api/version >/dev/null; then echo "ollama: already up (external)"; return; fi
      OLLAMA_HOST=0.0.0.0:11434 OLLAMA_KEEP_ALIVE=-1 OLLAMA_MAX_LOADED_MODELS=3 OLLAMA_FLASH_ATTENTION=1 OLLAMA_KV_CACHE_TYPE=q8_0 \
        nohup "$OLLAMA" serve >> run/ollama.log 2>&1 &
      echo $! > "$(pidfile ollama)" ;;
    dc1) nohup python3 -u factory/node.py DC1 11501 >> run/node-dc1.log 2>&1 & echo $! > "$(pidfile dc1)" ;;
    dc2) nohup python3 -u factory/node.py DC2 11502 >> run/node-dc2.log 2>&1 & echo $! > "$(pidfile dc2)" ;;
  esac
  sleep 0.5; running "$1" && echo "$1: started" || echo "$1: FAILED to start"
}

stop_one() {
  if running "$1"; then kill "$(cat "$(pidfile "$1")")" && rm -f "$(pidfile "$1")" && echo "$1: stopped"
  else
    # also stop instances started outside this script (e.g. earlier sessions)
    case "$1" in
      dc1) pkill -f "factory/node.py DC1" && echo "dc1: stopped" || echo "dc1: not running" ;;
      dc2) pkill -f "factory/node.py DC2" && echo "dc2: stopped" || echo "dc2: not running" ;;
      ollama) echo "ollama: not started by this script (leaving it)" ;;
    esac
  fi
}

status_one() {
  case "$1" in
    ollama) curl -s -m 2 http://127.0.0.1:11434/api/version >/dev/null && echo "ollama: up" || echo "ollama: DOWN" ;;
    dc1) curl -s -m 2 http://127.0.0.1:11501/api/version >/dev/null && echo "dc1: up" || echo "dc1: DOWN" ;;
    dc2) curl -s -m 2 http://127.0.0.1:11502/api/version >/dev/null && echo "dc2: up" || echo "dc2: DOWN" ;;
  esac
}

cmd="${1:-status}"; target="${2:-all}"
[ "$target" = all ] && targets=(ollama dc1 dc2) || targets=("$target")
for t in "${targets[@]}"; do "${cmd}_one" "$t"; done

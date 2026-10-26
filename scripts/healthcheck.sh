#!/usr/bin/env bash
# Is every layer of your stack actually up?
#
# Walks the stack bottom-up and does a REAL request at each layer, so you find
# out where it breaks instead of guessing. Safe to run at any time — it only
# reads.
#
#   ./scripts/healthcheck.sh
#
# Layers:  weights on disk → engine (:8080) → manager (:8090) → gateway (:4000)
#
# Override ports:  ENGINE_PORT=18080 ./scripts/healthcheck.sh

set -uo pipefail

ENGINE_PORT="${ENGINE_PORT:-8080}"
SWAP_PORT="${SWAP_PORT:-8090}"
PROXY_PORT="${PROXY_PORT:-4000}"
PROXY_KEY="${LITELLM_API_KEY:-}"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"

green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; bold=$'\033[1m'; dim=$'\033[2m'; off=$'\033[0m'
[ -t 1 ] || { green=""; yellow=""; red=""; bold=""; dim=""; off=""; }

pass() { printf '  %s✓%s %s\n' "$green" "$off" "$1"; }
note() { printf '  %s!%s %s\n' "$yellow" "$off" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$red" "$off" "$1"; }
info() { printf '    %s%s%s\n' "$dim" "$1" "$off"; }
head_(){ printf '\n%s%s%s\n' "$bold" "$1" "$off"; }

# GET a URL; print body, return curl's exit code. Quiet, short timeout.
get() { curl -s --max-time "${2:-8}" "$1" 2>/dev/null; }

# Is something listening on a port?
listening() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then ss -ltn 2>/dev/null | grep -q ":$p "; return $?; fi
  if command -v lsof >/dev/null 2>&1; then lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; return $?; fi
  # Fall back to just trying the port.
  curl -s --max-time 3 -o /dev/null "http://127.0.0.1:$p/" 2>/dev/null
  [ $? -ne 7 ]
}

# A real chat completion. Prints the assistant text on success.
chat() { # base_url model
  local base="$1" model="$2" auth=() body resp
  [ -n "$PROXY_KEY" ] && auth=(-H "Authorization: Bearer $PROXY_KEY")
  resp="$(curl -s --max-time 120 "${auth[@]}" \
    -H "Content-Type: application/json" \
    "$base/v1/chat/completions" \
    -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK\"}],\"max_tokens\":16,\"temperature\":0}" 2>/dev/null)"
  if [ -z "$resp" ]; then echo ""; return 1; fi
  # Prefer jq; fall back to grep so this works without it.
  if command -v jq >/dev/null 2>&1; then
    echo "$resp" | jq -r '.choices[0].message.content // .error.message // empty' 2>/dev/null
  else
    echo "$resp" | grep -oE '"content":"[^"]*"' | head -1 | sed 's/"content":"//;s/"$//'
  fi
}

models_at() { # base_url [auth]
  local body auth=()
  # Pass "auth" for the gateway layer. Once LiteLLM has a master_key it enforces
  # it on EVERY key-bearing endpoint, /v1/models included — so an unauthenticated
  # probe 401s against a perfectly healthy proxy and this script used to report
  # that as "did not respond". llama.cpp and llama-swap need no header.
  [ "${2:-}" = "auth" ] && [ -n "$PROXY_KEY" ] && auth=(-H "Authorization: Bearer $PROXY_KEY")
  body="$(curl -s --max-time 10 "${auth[@]}" "$1/v1/models" 2>/dev/null)"
  [ -z "$body" ] && { echo ""; return 1; }
  if command -v jq >/dev/null 2>&1; then
    echo "$body" | jq -r '.data[]?.id' 2>/dev/null | tr '\n' ' '
  else
    echo "$body" | grep -oE '"id":"[^"]*"' | sed 's/"id":"//;s/"$//' | tr '\n' ' '
  fi
}

echo "${bold}AI Workshop — stack healthcheck${off}"
echo "${dim}engine :$ENGINE_PORT · llama-swap :$SWAP_PORT · LiteLLM :$PROXY_PORT${off}"

# ── Layer 1: weights on disk ─────────────────────────────────────────────────
head_ "1. Weights  ($MODEL_DIR)"
if [ -d "$MODEL_DIR" ]; then
  n="$(find "$MODEL_DIR" -name '*.gguf' -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n" -gt 0 ]; then
    pass "$n gguf file(s)"
    while IFS= read -r f; do
      sz="$(du -h "$f" | cut -f1)"
      if [ "$(head -c 4 "$f" 2>/dev/null)" = "GGUF" ]; then
        info "$sz  $(basename "$f")"
      else
        bad "CORRUPT (bad magic bytes): $f — delete and re-download"
      fi
    done < <(find "$MODEL_DIR" -name '*.gguf' -type f 2>/dev/null | head -10)
  else
    bad "no .gguf files — run ./scripts/download-models.sh"
  fi
else
  note "$MODEL_DIR missing — fine if you let llama.cpp download via -hf"
fi

# ── Layer 2: engine ──────────────────────────────────────────────────────────
head_ "2. Engine  (llama.cpp :$ENGINE_PORT)"
if listening "$ENGINE_PORT"; then
  m="$(models_at "http://127.0.0.1:$ENGINE_PORT")"
  if [ -n "$m" ]; then
    pass "/v1/models responds: $m"
    first="$(echo "$m" | awk '{print $1}')"
    r="$(chat "http://127.0.0.1:$ENGINE_PORT" "$first")"
    if [ -n "$r" ]; then pass "chat completion works — model replied: ${r:0:60}"
    else bad "listed models but chat completion failed — check the llama-server log"; fi
  else
    bad "port open but /v1/models did not respond."
    info "Either it is still loading, or something ELSE owns :$ENGINE_PORT that is not an"
    info "LLM server (a dev server, a database UI, another workshop). Check which:"
    info "  ss -ltnp | grep :$ENGINE_PORT      # Linux/WSL2"
    info "  lsof -iTCP:$ENGINE_PORT -sTCP:LISTEN   # macOS"
  fi
else
  note "nothing on :$ENGINE_PORT — not running, or you went straight to llama-swap (that is fine)"
fi

# ── Layer 3: manager ─────────────────────────────────────────────────────────
head_ "3. Manager  (llama-swap :$SWAP_PORT)"
if listening "$SWAP_PORT"; then
  m="$(models_at "http://127.0.0.1:$SWAP_PORT")"
  if [ -n "$m" ]; then
    pass "/v1/models responds"
    info "$m"
    running="$(get "http://127.0.0.1:$SWAP_PORT/running" 8)"
    [ -n "$running" ] && { pass "/running responds"; info "$running"; }
    first="$(echo "$m" | awk '{print $1}')"
    echo "  ${dim}first request may be slow — llama-swap cold-loads the engine${off}"
    r="$(chat "http://127.0.0.1:$SWAP_PORT" "$first")"
    if [ -n "$r" ]; then pass "chat completion through llama-swap: ${r:0:60}"
    else bad "chat completion failed — the model's 'cmd' in config.yaml probably cannot start. Run llama-swap in the foreground and read the log."; fi
  else
    bad "port open but /v1/models did not respond — is that llama-swap, or something else on :$SWAP_PORT?"
  fi
else
  note "nothing on :$SWAP_PORT — optional layer, skip it if you are running the engine directly"
fi

# ── Layer 4: gateway ─────────────────────────────────────────────────────────
head_ "4. Gateway  (LiteLLM :$PROXY_PORT)"
if listening "$PROXY_PORT"; then
  hdr=(-H "Content-Type: application/json")
  [ -n "$PROXY_KEY" ] && hdr+=(-H "Authorization: Bearer $PROXY_KEY")

  live="$(curl -s --max-time 8 "${hdr[@]}" "http://127.0.0.1:$PROXY_PORT/health/liveliness" 2>/dev/null)"
  [ -n "$live" ] && pass "/health/liveliness: ${live:0:40}" || note "/health/liveliness did not respond (may need auth)"

  m="$(models_at "http://127.0.0.1:$PROXY_PORT" auth)"
  if [ -n "$m" ]; then
    pass "/v1/models responds"
    info "$m"
    first="$(echo "$m" | awk '{print $1}')"
    r="$(chat "http://127.0.0.1:$PROXY_PORT" "$first")"
    if [ -n "$r" ]; then
      pass "end-to-end chat completion through the proxy: ${r:0:60}"
      echo
      printf '  %sYour stack works. Point a client at http://127.0.0.1:%s/v1%s\n' "$green" "$PROXY_PORT" "$off"
    else
      bad "chat completion through the proxy failed."
      info "usual cause: LiteLLM is in Docker and cannot reach the host. Check that"
      info "docker-compose.yml has extra_hosts: host.docker.internal:host-gateway and"
      info "that api_base in config.yaml uses host.docker.internal, not 127.0.0.1."
      info "then: docker logs litellm --tail 40"
    fi
  else
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "${hdr[@]}" \
      "http://127.0.0.1:$PROXY_PORT/v1/models" 2>/dev/null)"
    if [ "$code" = "401" ]; then
      bad "/v1/models returned 401. The gateway is UP and enforcing auth — the key did not match."
      if [ -z "$PROXY_KEY" ]; then
        info "LITELLM_API_KEY is not set in THIS shell. configs/litellm/.env is read by the"
        info "container, not by your terminal, so setting it there does nothing here. Load it:"
        info "  set -a; . configs/litellm/.env; set +a"
        info "then re-run this script."
      else
        info "the key you sent was rejected. It must equal LITELLM_MASTER_KEY in"
        info "configs/litellm/.env exactly, including the sk- prefix."
      fi
    else
      bad "port open but /v1/models did not respond${code:+ (HTTP $code)}."
      info "docker logs litellm --tail 40"
    fi
  fi
else
  note "nothing on :$PROXY_PORT — LiteLLM not running. cd configs/litellm && docker compose up -d"
fi

head_ "Reference"
info "docker logs litellm --tail 50          # gateway problems"
info "llama-swap --config configs/llama-swap/config.yaml   # run in foreground to see engine errors"
info "curl -s http://127.0.0.1:$SWAP_PORT/logs | tail -30   # llama-swap's own log endpoint"
info "docs/troubleshooting.md                # when the above is not enough"

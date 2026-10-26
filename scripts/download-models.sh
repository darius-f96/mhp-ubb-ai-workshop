#!/usr/bin/env bash
# Download the workshop model set.
#
# Tries three transports in order: a LAN mirror (if one is reachable), the `hf`
# CLI (resumable), and plain curl. Whichever works first wins.
#
# Usage:
#   ./download-models.sh              # the core set (~2.6 GB)
#   ./download-models.sh --all        # everything in the catalogue (~14 GB)
#   ./download-models.sh --list       # show what each tier contains
#   MIRROR=http://192.168.1.50:8000 ./download-models.sh   # force a mirror
#
# Models land in $MODEL_DIR (default: ~/models).

set -uo pipefail

MODEL_DIR="${MODEL_DIR:-$HOME/models}"
MIRROR="${MIRROR:-}"
TIER="core"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  --all)  TIER="all" ;;
  --list) TIER="list" ;;
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
# The catalogue. Format: "<repo>|<file>|<tier>"
# Sizes verified against the Hugging Face API on 2026-10-26.
# ─────────────────────────────────────────────────────────────────────────────
CATALOGUE=(
  # core — enough for every exercise in the workshop (2.55 GB)
  "ggml-org/Qwen3-1.7B-GGUF|Qwen3-1.7B-Q4_K_M.gguf|core"
  "Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF|qwen2.5-coder-1.5b-instruct-q4_k_m.gguf|core"
  "nomic-ai/nomic-embed-text-v1.5-GGUF|nomic-embed-text-v1.5.Q8_0.gguf|core"

  # extras — added by --all
  "ggml-org/Qwen3-0.6B-GGUF|Qwen3-0.6B-Q4_0.gguf|extra"
  "unsloth/SmolLM2-135M-Instruct-GGUF|SmolLM2-135M-Instruct-Q4_K_M.gguf|extra"
  "ggml-org/Qwen3-4B-GGUF|Qwen3-4B-Q4_K_M.gguf|extra"
  "ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF|qwen3-reranker-0.6b-q8_0.gguf|extra"
  "Qwen/Qwen3-VL-2B-Instruct-GGUF|Qwen3VL-2B-Instruct-Q4_K_M.gguf|extra"
  "Qwen/Qwen3-VL-2B-Instruct-GGUF|mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf|extra"
  "LiquidAI/LFM2.5-1.2B-Instruct-GGUF|LFM2.5-1.2B-Instruct-Q4_K_M.gguf|extra"
  "unsloth/SmolLM3-3B-GGUF|SmolLM3-3B-Q4_K_M.gguf|extra"
  "Qwen/Qwen2.5-Coder-3B-Instruct-GGUF|qwen2.5-coder-3b-instruct-q4_k_m.gguf|extra"
  "bartowski/Qwen2.5-Math-1.5B-Instruct-GGUF|Qwen2.5-Math-1.5B-Instruct-Q4_K_M.gguf|extra"
  "Qwen/Qwen3-Embedding-0.6B-GGUF|Qwen3-Embedding-0.6B-Q8_0.gguf|extra"
)

selected() {
  local entry tier
  for entry in "${CATALOGUE[@]}"; do
    tier="${entry##*|}"
    case "$TIER" in
      core) [ "$tier" = "core" ] && printf '%s\n' "$entry" ;;
      all)  [ "$tier" != "list" ] && printf '%s\n' "$entry" ;;
    esac
  done
}

if [ "$TIER" = "list" ]; then
  printf '%-46s %s\n' "REPO" "FILE"
  for entry in "${CATALOGUE[@]}"; do
    repo="${entry%%|*}"; rest="${entry#*|}"; file="${rest%%|*}"; tier="${rest##*|}"
    printf '%-46s %s [%s]\n' "$repo" "$file" "$tier"
  done
  exit 0
fi

have() { command -v "$1" >/dev/null 2>&1; }

# Resolve a transport once, up front.
transport=""
if [ -n "$MIRROR" ]; then
  if curl -sf --max-time 5 -o /dev/null "$MIRROR/"; then
    transport="mirror"
  else
    echo "!! MIRROR=$MIRROR is not reachable; falling back." >&2
  fi
fi
[ -z "$transport" ] && have hf && transport="hf"
[ -z "$transport" ] && have curl && transport="curl"

if [ -z "$transport" ]; then
  echo "!! No transport available. Install the HF CLI or curl:" >&2
  echo "     pip install -U huggingface_hub" >&2
  exit 1
fi

mkdir -p "$MODEL_DIR"
echo "Transport : $transport"
echo "Directory : $MODEL_DIR"
[ "$transport" = "mirror" ] && echo "Mirror    : $MIRROR"
echo

failures=()

fetch_one() {
  local repo="$1" file="$2" dest="$MODEL_DIR/$2" url

  # Skip anything already present and looking like a complete GGUF.
  if [ -f "$dest" ] && [ "$(head -c 4 "$dest" 2>/dev/null)" = "GGUF" ]; then
    echo "== $file — already present, skipping"
    return 0
  fi

  echo "== $repo/$file"
  case "$transport" in
    mirror)
      # The mirror serves $MODEL_DIR as its document root. This script FLATTENS
      # what it downloads (see the hf branch below), so a cache built by running
      # download-models.sh holds <file>.gguf at the top level — while a mirror
      # assembled by hand may follow <org>/<repo>/<file>.gguf. Try nested first,
      # then flat, so either layout works.
      curl -L --fail --retry 3 --progress-bar -o "$dest" "$MIRROR/$repo/$file" \
        || curl -L --fail --retry 3 --progress-bar -o "$dest" "$MIRROR/$file" \
        || return 1
      ;;
    hf)
      hf download "$repo" "$file" --local-dir "$MODEL_DIR" || return 1
      # hf nests files under the repo path; flatten so configs can use one dir.
      if [ -f "$MODEL_DIR/$repo/$file" ]; then
        mv -f "$MODEL_DIR/$repo/$file" "$dest"
        rm -rf "$MODEL_DIR/$repo" 2>/dev/null
      fi
      ;;
    curl)
      url="https://huggingface.co/$repo/resolve/main/$file"
      curl -L --fail --retry 3 --continue-at - --progress-bar -o "$dest" "$url" || return 1
      ;;
  esac

  if [ "$(head -c 4 "$dest" 2>/dev/null)" != "GGUF" ]; then
    echo "   !! $dest is not a valid GGUF (bad magic bytes) — removing" >&2
    rm -f "$dest"
    return 1
  fi
  echo "   ok  $(du -h "$dest" | cut -f1)  $dest"
}

while IFS='|' read -r repo file tier; do
  [ -z "$repo" ] && continue
  fetch_one "$repo" "$file" || failures+=("$repo/$file")
done < <(selected)

echo
if [ ${#failures[@]} -gt 0 ]; then
  echo "FAILED (${#failures[@]}):" >&2
  printf '  %s\n' "${failures[@]}" >&2
  cat >&2 <<'HINT'

What to try:
  * Re-run this script — both hf and curl resume partial downloads.
  * 401 Unauthorized means the repo is GATED (Llama, Mistral). Log in to
    huggingface.co, accept the licence on the model page, then `hf auth login`.
  * No internet at the venue? Ask the instructor for the MIRROR address and run:
      MIRROR=http://INSTRUCTOR-IP:8000 ./download-models.sh
HINT
  exit 1
fi

echo "All downloads verified. Next: docs/02-llama-cpp.md"

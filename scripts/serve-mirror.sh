#!/usr/bin/env bash
# Serve a local model cache to a whole room over plain HTTP.
#
# Run this on whichever machine holds the models and has a routable IP —
# typically one laptop in the room, so everyone else pulls weights from it
# instead of from Hugging Face. Saves the venue Wi-Fi, which is the single
# most common way a hands-on session dies.
#
# Usage:
#   ./serve-mirror.sh                    # serve ~/models on :8000
#   MODEL_DIR=/data/models PORT=9000 ./serve-mirror.sh
#
# Clients then run:
#   MIRROR=http://YOUR-IP:8000 ./scripts/download-models.sh
#
# Directory layout expected (what download-models.sh produces, mirrored per repo):
#   $MODEL_DIR/<org>/<repo>/<file>.gguf      preferred
#   $MODEL_DIR/<file>.gguf                   also works, see "flat" note below

set -euo pipefail

MODEL_DIR="${MODEL_DIR:-$HOME/models}"
PORT="${PORT:-8000}"

if [ ! -d "$MODEL_DIR" ]; then
  echo "!! $MODEL_DIR does not exist. Download the models first:" >&2
  echo "     ./download-models.sh --all" >&2
  exit 1
fi

# Which interface are we on? Students need a routable IP, not 127.0.0.1.
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$IP" ] && IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
[ -z "$IP" ] && IP="$(ifconfig 2>/dev/null | awk '/inet /{if($2!="127.0.0.1"){print $2; exit}}')"
[ -z "$IP" ] && IP="YOUR-IP"

SIZE="$(du -sh "$MODEL_DIR" 2>/dev/null | cut -f1)"
COUNT="$(find "$MODEL_DIR" -name '*.gguf' -type f 2>/dev/null | wc -l | tr -d ' ')"

cat <<BANNER
─────────────────────────────────────────────────────────────
 Model mirror
   directory : $MODEL_DIR  ($SIZE, $COUNT gguf files)
   listening : http://$IP:$PORT
   download with:
     MIRROR=http://$IP:$PORT ./scripts/download-models.sh
─────────────────────────────────────────────────────────────
 Ctrl-C stops the mirror.
BANNER

if [ "$COUNT" -eq 0 ]; then
  echo
  echo "!! No .gguf files found in $MODEL_DIR — students will get 404s." >&2
  echo "   Run ./download-models.sh --all first." >&2
  exit 1
fi

# Python is the only dependency, and every OS in the workshop has it.
if command -v python3 >/dev/null 2>&1; then
  cd "$MODEL_DIR"
  exec python3 -m http.server "$PORT" --bind 0.0.0.0
fi

echo "!! python3 not found — cannot start the mirror." >&2
echo "   Alternatives: 'npx serve -l $PORT $MODEL_DIR' or 'caddy file-server --listen :$PORT --root $MODEL_DIR'" >&2
exit 1

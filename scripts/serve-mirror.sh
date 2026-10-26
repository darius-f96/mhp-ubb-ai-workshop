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
# Directory layout: download-models.sh FLATTENS what it downloads, so a cache it
# built holds $MODEL_DIR/<file>.gguf. A mirror assembled by hand may instead use
# $MODEL_DIR/<org>/<repo>/<file>.gguf. Both work — download-models.sh tries the
# nested path first and falls back to the flat one. The pre-flight below reports
# which shape your directory actually serves, so a layout mismatch is caught
# here rather than by a room full of students at once.

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

# ── Pre-flight ────────────────────────────────────────────────────────────────
# Actually fetch a file the way download-models.sh will, over loopback, BEFORE
# handing the address out. A layout mismatch is invisible in the directory
# listing above — it only shows up as a room full of simultaneous 404s.
preflight() {
  local sample rel flat probe code_flat code_nested
  sample="$(find "$MODEL_DIR" -name '*.gguf' -type f 2>/dev/null | head -1 || true)"
  [ -z "$sample" ] && return 0
  rel="${sample#"$MODEL_DIR"/}"
  flat="$(basename "$rel")"

  # --directory, not a cd: this probe must serve the same tree the real server
  # will, and the script's CWD is wherever the instructor ran it from.
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$MODEL_DIR" >/dev/null 2>&1 &
  probe=$!
  sleep 1
  if ! kill -0 "$probe" 2>/dev/null; then
    echo "   pre-flight  skipped — is :$PORT already in use?"
    return 0
  fi

  # HEAD, not GET: python's http.server supports it, so probing costs no
  # bandwidth even against a 2.5 GB file.
  code_flat="$(curl -s -I -o /dev/null -w '%{http_code}' --max-time 10 \
    "http://127.0.0.1:$PORT/$flat" 2>/dev/null || echo 000)"
  code_nested="$(curl -s -I -o /dev/null -w '%{http_code}' --max-time 10 \
    "http://127.0.0.1:$PORT/$rel" 2>/dev/null || echo 000)"

  kill "$probe" 2>/dev/null || true
  wait "$probe" 2>/dev/null || true
  sleep 0.3

  echo "   pre-flight  /$flat -> HTTP $code_flat"
  [ "$rel" != "$flat" ] && echo "               /$rel -> HTTP $code_nested"

  if [ "$code_flat" != "200" ] && [ "$code_nested" != "200" ]; then
    echo
    echo "!! Neither URL shape resolved — students would get 404s from this mirror." >&2
    echo "   MODEL_DIR is $MODEL_DIR; check the .gguf files are really in it." >&2
    return 1
  fi
  echo "   layout OK   download-models.sh will find these files."
  return 0
}

command -v python3 >/dev/null 2>&1 && { preflight || exit 1; }

# Python is the only dependency, and every OS in the workshop has it.
if command -v python3 >/dev/null 2>&1; then
  cd "$MODEL_DIR"
  exec python3 -m http.server "$PORT" --bind 0.0.0.0
fi

echo "!! python3 not found — cannot start the mirror." >&2
echo "   Alternatives: 'npx serve -l $PORT $MODEL_DIR' or 'caddy file-server --listen :$PORT --root $MODEL_DIR'" >&2
exit 1

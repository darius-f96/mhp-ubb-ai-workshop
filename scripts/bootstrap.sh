#!/usr/bin/env bash
# Check that your machine is ready for the workshop.
#
# Run this BEFORE the session. It reports what is missing and how to fix it,
# and exits non-zero if anything blocking is wrong.
#
#   ./scripts/bootstrap.sh
#
# Nothing here installs or changes anything — it only reads.

set -uo pipefail

ok=0; warn=0; fail=0
green=$'\033[32m'; yellow=$'\033[33m'; red=$'\033[31m'; bold=$'\033[1m'; off=$'\033[0m'
[ -t 1 ] || { green=""; yellow=""; red=""; bold=""; off=""; }

pass() { printf '  %s✓%s %s\n' "$green" "$off" "$1"; ok=$((ok+1)); }
note() { printf '  %s!%s %s\n' "$yellow" "$off" "$1"; warn=$((warn+1)); }
bad()  { printf '  %s✗%s %s\n' "$red" "$off" "$1"; fail=$((fail+1)); }
head_(){ printf '\n%s%s%s\n' "$bold" "$1" "$off"; }

# A required command, with the fix to suggest when it is missing.
need() { # name, min_version_major, hint
  local cmd="$1" min="${2:-0}" hint="$3" v
  if ! command -v "$cmd" >/dev/null 2>&1; then
    bad "$cmd not found — $hint"
    return 1
  fi
  v="$("$cmd" --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
  if [ "${min:-0}" != "0" ] && [ -n "$v" ]; then
    local major="${v%%.*}"
    if [ "$major" -lt "$min" ] 2>/dev/null; then
      bad "$cmd is $v, need >= $min — $hint"
      return 1
    fi
  fi
  pass "$cmd ${v:-}"
  return 0
}

# A tool whose --version output is not a plain X.Y number (llama.cpp prints a
# build id, llama-swap a vNNN tag), so print the first line verbatim instead.
# sev=bad blocks the session; sev=note only warns.
have_bin() { # name, sev, hint
  local cmd="$1" sev="$2" hint="$3" v
  if command -v "$cmd" >/dev/null 2>&1; then
    v="$("$cmd" --version 2>&1 | head -1)"
    pass "$cmd — ${v:-installed}"
  elif [ "$sev" = "bad" ]; then
    bad "$cmd not found — $hint"
  else
    note "$cmd not found — $hint"
  fi
}

echo "${bold}AI Workshop — machine check${off}"
echo "Host: $(uname -srmo 2>/dev/null || uname -a)"

# ── OS-specific context ──────────────────────────────────────────────────────
head_ "Platform"
OS="$(uname -s)"
case "$OS" in
  Darwin)
    pass "macOS $(sw_vers -productVersion 2>/dev/null)"
    case "$(uname -m)" in
      arm64) pass "Apple Silicon — llama.cpp will use Metal (GPU). Nice." ;;
      x86_64) note "Intel Mac — CPU only, expect slower inference." ;;
    esac
    ;;
  Linux)
    if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null; then
      pass "WSL2 (Windows Subsystem for Linux)"
      note "Check .wslconfig gives WSL enough RAM — see docs/00-prerequisites.md"
    else
      pass "Linux"
    fi
    ;;
  *) note "Unrecognised OS: $OS — the guides assume macOS, Linux or WSL2" ;;
esac

if grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null || [ "$OS" = "Darwin" ]; then :; fi

# ── Required tools ───────────────────────────────────────────────────────────
head_ "Required tools"
need git  2 "install: https://git-scm.com/downloads"
need node 22 "Qwen Code requires Node >=22. Install via nvm: see docs/00-prerequisites.md"
need npm  0 "comes with Node.js"
need curl 0 "macOS: xcode-select --install / Ubuntu: sudo apt install curl"
need python3 3 "https://www.python.org/downloads/"

if command -v jq >/dev/null 2>&1; then
  pass "jq"
else
  note "jq not found — used to pretty-print JSON in the guides. brew install jq / sudo apt install jq"
fi

# ── Docker ───────────────────────────────────────────────────────────────────
head_ "Docker"
if command -v docker >/dev/null 2>&1; then
  pass "docker $(docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if docker info >/dev/null 2>&1; then
    pass "docker daemon is running"
    if docker compose version >/dev/null 2>&1; then
      pass "docker compose"
    else
      bad "docker compose missing — LiteLLM needs it. Update Docker, or install docker-compose-plugin."
    fi

    # The memory ceiling decides how big a model you can run in a container.
    mem="$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)"
    memgb="$(awk -v m="$mem" 'BEGIN{printf "%.1f", m/1024/1024/1024}')"
    if [ "${mem:-0}" -gt 0 ] 2>/dev/null; then
      if awk -v g="$memgb" 'BEGIN{exit !(g>=6)}'; then
        pass "docker memory limit: ${memgb} GB"
      elif awk -v g="$memgb" 'BEGIN{exit !(g>=4)}'; then
        note "docker memory limit is only ${memgb} GB — raise it to 6-8 GB (Docker Desktop → Settings → Resources → Memory)"
      else
        bad "docker memory limit is ${memgb} GB — far too low. Raise it to at least 6 GB."
      fi
    fi

    # Can a container reach a server on the host? LiteLLM needs this.
    if docker run --rm --add-host=host.docker.internal:host-gateway alpine:3 \
         sh -c 'getent hosts host.docker.internal >/dev/null 2>&1' 2>/dev/null; then
      pass "host.docker.internal resolves inside containers"
    else
      note "could not verify host.docker.internal — Linux needs extra_hosts: host-gateway in compose (the provided config has it)"
    fi
  else
    bad "docker daemon is NOT running — start Docker Desktop / run 'colima start' / 'sudo systemctl start docker'"
  fi
else
  bad "docker not found — see docs/00-prerequisites.md#3-docker"
fi

# ── Workshop binaries ────────────────────────────────────────────────────────
# These are the ones that cost real session time if missing: llama.cpp has to be
# COMPILED on Ubuntu/WSL2, and there is no slot for that in the 45-minute
# hands-on. The two agents are only needed later (Exercise 6), so a miss there is
# a warning you can fix over lunch rather than a blocker.
head_ "Workshop binaries"
have_bin llama-server bad  "the inference engine; the hands-on cannot start without it. Install NOW: docs/00-prerequisites.md#5-llamacpp"
have_bin llama-swap   bad  "the model manager; needed for the second half. Install NOW: docs/00-prerequisites.md#6-llama-swap"
have_bin qwen         note "needed for Exercise 6, not the hands-on. npm i -g @qwen-code/qwen-code (Node >= 22): docs/05-qwen-code.md"
have_bin opencode     note "needed for Exercise 6, not the hands-on. npm i -g opencode-ai: docs/06-opencode.md"

# ── Hardware ─────────────────────────────────────────────────────────────────
head_ "Hardware"
case "$OS" in
  Darwin) ram_bytes=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) )) ;;
  Linux)  ram_bytes=$(( $(awk '/MemTotal/{print $2*1024}' /proc/meminfo 2>/dev/null || echo 0) )) ;;
  *)      ram_bytes=0 ;;
esac
ram_gb="$(awk -v b="$ram_bytes" 'BEGIN{printf "%.0f", b/1024/1024/1024}')"
if [ "$ram_gb" -ge 16 ] 2>/dev/null; then
  pass "RAM: ${ram_gb} GB — matches the workshop baseline"
elif [ "$ram_gb" -ge 12 ] 2>/dev/null; then
  note "RAM: ${ram_gb} GB — workable, but stick to the 1.7B model and -c 4096"
elif [ "$ram_gb" -gt 0 ] 2>/dev/null; then
  bad "RAM: ${ram_gb} GB — too little to self-host comfortably. Use the cloud fallback path; tell an instructor."
fi

cores="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 0)"
[ "$cores" -ge 4 ] 2>/dev/null && pass "CPU cores: $cores" || note "CPU cores: $cores — inference will be slow"

# Disk in the home directory, where models go.
free_gb="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2{printf "%.0f", $4/1024/1024}')"
if [ "${free_gb:-0}" -ge 10 ] 2>/dev/null; then
  pass "free disk in \$HOME: ${free_gb} GB"
elif [ "${free_gb:-0}" -ge 5 ] 2>/dev/null; then
  note "free disk in \$HOME: ${free_gb} GB — enough for the core set only, skip --all"
else
  bad "free disk in \$HOME: ${free_gb} GB — you need 10 GB. Free up space."
fi

# GPU — informational only; the workshop does not need one.
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  gpu="$(nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null | head -1)"
  pass "NVIDIA GPU detected: $gpu — you can attempt the vLLM stretch path"
else
  note "no NVIDIA GPU (or drivers missing) — expected. CPU-only is the workshop default."
fi

# ── Ports ────────────────────────────────────────────────────────────────────
head_ "Ports"
# A busy port is a warning, not a failure: once you are part-way through the
# workshop these are occupied by YOUR OWN stack, which is the expected state.
check_port() {
  local p="$1" what="$2"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | grep -q ":$p " && { note ":$p in use ($what) — expected if your stack is already running, otherwise find it with: ss -ltnp | grep :$p"; return; }
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 && { note ":$p in use ($what) — expected if your stack is already running, otherwise: lsof -iTCP:$p -sTCP:LISTEN"; return; }
  else
    return
  fi
  pass ":$p free ($what)"
}
check_port 8080 "llama.cpp"
check_port 8090 "llama-swap"
check_port 4000 "LiteLLM"
check_port 4170 "qwen serve"

# ── Models ───────────────────────────────────────────────────────────────────
head_ "Models"
MODEL_DIR="${MODEL_DIR:-$HOME/models}"
if [ -d "$MODEL_DIR" ]; then
  n="$(find "$MODEL_DIR" -name '*.gguf' -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n" -gt 0 ]; then
    pass "$n gguf file(s) in $MODEL_DIR"
    bad_magic=0
    while IFS= read -r f; do
      [ "$(head -c 4 "$f" 2>/dev/null)" = "GGUF" ] || { note "  corrupt/truncated: $f"; bad_magic=$((bad_magic+1)); }
    done < <(find "$MODEL_DIR" -name '*.gguf' -type f 2>/dev/null)
    [ "$bad_magic" -eq 0 ] && pass "  all pass the GGUF magic-byte check"
  else
    note "$MODEL_DIR exists but holds no .gguf files — run ./scripts/download-models.sh"
  fi
else
  note "$MODEL_DIR does not exist yet — run ./scripts/download-models.sh"
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n%s────────────────────────────────%s\n' "$bold" "$off"
printf '  %s%d passed%s   %s%d warnings%s   %s%d failed%s\n' \
  "$green" "$ok" "$off" "$yellow" "$warn" "$off" "$red" "$fail" "$off"
printf '%s────────────────────────────────%s\n' "$bold" "$off"

if [ "$fail" -gt 0 ]; then
  echo
  echo "Fix the ✗ items above, then re-run. Docs: docs/00-prerequisites.md"
  exit 1
fi
if [ "$warn" -gt 0 ]; then
  echo
  echo "No blockers. Review the ! items — they will slow you down but not stop you."
  exit 0
fi
echo
echo "Everything checks out. Next: docs/models.md"

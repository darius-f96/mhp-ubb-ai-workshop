# Offline models — surviving a room with no internet

Twenty-five laptops pulling 2 GB from Hugging Face at the same moment will saturate almost any venue network. This page is how we avoid that, and how you cope if the network dies anyway.

---

## The three fallbacks, in order

1. **The instructor's LAN mirror** — fastest, no internet needed.
2. **A USB stick** — works when there is no network at all.
3. **Hugging Face directly** — the normal path, and the one that breaks under load.

---

## Option 1 — the LAN mirror (what we will use)

The instructor runs [`scripts/serve-mirror.sh`](../scripts/serve-mirror.sh), which serves their model cache over plain HTTP on the venue network.

**Instructor:**

```bash
./scripts/serve-mirror.sh
```

It prints the address to announce:

```
─────────────────────────────────────────────────────────────
 Model mirror
   directory : /home/instructor/models  (16G, 14 gguf files)
   listening : http://192.168.1.50:8000
   tell the class to run:
     MIRROR=http://192.168.1.50:8000 ./scripts/download-models.sh
─────────────────────────────────────────────────────────────
```

**Students:**

```bash
MIRROR=http://INSTRUCTOR-IP:8000 ./scripts/download-models.sh
```

That is it. The script uses the mirror for everything and falls back to Hugging Face if the mirror is unreachable.

Check the mirror is up before blaming anything else:

```bash
curl -s http://INSTRUCTOR-IP:8000/ | head -20
```

You should see an HTML directory listing. If it hangs, you are on a different network (guest Wi-Fi isolation is common) — tell the instructor.

### Building your own mirror

Any static file server will do. Layout is `MODEL_DIR/<org>/<repo>/<file>.gguf`.

```bash
# Python — zero dependencies, works on every OS in the workshop
cd ~/models && python3 -m http.server 8000 --bind 0.0.0.0

# or Node
npx serve -l 8000 ~/models

# or Caddy — best for a big room, handles concurrent downloads far better
caddy file-server --listen :8000 --root ~/models
```

> **For a room of 25+:** `python3 -m http.server` is single-threaded and will be slow under real concurrency. Use Caddy or nginx if you have it. Either is fine for a demo or a small group.

---

## Option 2 — USB stick

**Before the workshop**, the instructor copies the model set to USB sticks. If you have one, plug it in and copy:

```bash
# macOS / Linux — the stick appears under /Volumes/NAME or /media/$USER/NAME
ls /Volumes/*/models 2>/dev/null || ls /media/$USER/*/models 2>/dev/null

mkdir -p ~/models
cp /Volumes/WORKSHOP/models/*.gguf ~/models/
```

```bash
# Windows / WSL2 — drives are under /mnt/<letter>
ls /mnt/d/models
mkdir -p ~/models
cp /mnt/d/models/*.gguf ~/models/
```

Then verify, because USB copies get interrupted:

```bash
cd ~/models && for f in *.gguf; do printf '%-50s ' "$f"; head -c 4 "$f"; echo; done
```

Every line must print `GGUF`. Anything else is a truncated copy — delete it and re-copy.

---

## Option 3 — Hugging Face, when you have bandwidth

```bash
pip install -U huggingface_hub
./scripts/download-models.sh
```

Prefer this over a browser download: both `hf` and `curl -C -` **resume**. If the venue Wi-Fi drops, re-run the script and it continues where it left off.

Throttle yourself if you are being a good citizen on a shared network:

```bash
curl -L --limit-rate 2M -o ~/models/model.gguf https://huggingface.co/REPO/resolve/main/FILE.gguf
```

---

## Letting the engine download for you

llama.cpp and llama-swap can fetch from Hugging Face on first use, so you never manage a file at all:

```bash
llama-server -hf ggml-org/Qwen3-1.7B-GGUF:Q4_K_M --port 8080
```

Convenient, but note what it means in a classroom: **every student triggers their own download at the same moment**, from a server with no cache and no resume coordination. Fine at home; a bad idea for a venue. Download once, deliberately, beforehand.

---

## Pointing the engines at a local file

Nothing in the rest of this workshop needs the internet once the `.gguf` is on disk. Everywhere you see a model path, use yours:

```bash
export MODEL=~/models/Qwen3-1.7B-Q4_K_M.gguf
llama-server -m "$MODEL" -c 8192 --port 8080
```

If you want llama.cpp to find models without full paths, put them all in one directory and export it:

```bash
echo 'export MODEL_DIR=$HOME/models' >> ~/.bashrc    # or ~/.zshrc on macOS
source ~/.bashrc
```

---

## Fully offline for the rest of the stack

Two things besides weights normally want the network:

**Docker images.** Pull them *before* the workshop, not during:

```bash
docker pull ghcr.io/berriai/litellm:main-stable
docker images | grep litellm
```

**npm packages.** Same story:

```bash
npm install -g @qwen-code/qwen-code
```

If you must work with no internet at all, see [troubleshooting.md](troubleshooting.md#offline-mode).

---

## Troubleshooting downloads

| Symptom | Cause | Fix |
|---------|-------|-----|
| `401 Unauthorized` | The repo is **gated** (Llama, Mistral) | Accept the licence on the model page while logged in, then `hf auth login` |
| `404 Not Found` on a file | Wrong filename — case-sensitive, and `Qwen/` repos use lowercase while `ggml-org/` does not | Copy the exact filename from [models.md](models.md) |
| Download stalls at a percentage | Flaky network | Re-run — both transports resume |
| File present but engine says "invalid model" | Truncated download | Check `head -c 4 FILE.gguf` prints `GGUF`; if not, delete and retry |
| Mirror hangs | Guest-Wi-Fi client isolation | Ask the instructor; or use the USB/HF path |
| `hf: command not found` | huggingface_hub not installed, or `~/.local/bin` not on PATH | `pip install -U huggingface_hub`, then check `echo $PATH` |

---

**Back to:** [the model catalogue](models.md)

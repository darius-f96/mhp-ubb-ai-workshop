# 3 — llama-swap: several models, one port

You have one engine slot and four models. Loading a model costs gigabytes of RAM and several seconds. Running four `llama-server` processes on a 16 GB laptop is not going to work.

**llama-swap** puts one API in front of all of them and starts engines on demand. Ask for `coder` and it boots the code model. Ask for `chat` and it stops the coder and boots the chat model. Idle models are killed after a TTL and your RAM comes back.

That is what makes a *specialised* local setup practical — and specialisation is how small models become genuinely useful.

By the end of this page you will have four models behind `:8090`, with only one in memory at a time.

---

## What it is

One Go binary, one YAML file, no dependencies. It speaks the OpenAI-compatible API on the front and starts any OpenAI-compatible server on the back — llama.cpp, vLLM, whisper.cpp, stable-diffusion.cpp. You can upgrade the engines underneath without changing anything above.

Current release: **v267** (published 2026-10-26).

---

## Install

### macOS / Linux — Homebrew

```bash
brew tap mostlygeek/llama-swap
brew install llama-swap
llama-swap --version
```

### Any OS — pre-built binary

Releases are published for Linux, macOS, Windows and FreeBSD: <https://github.com/mostlygeek/llama-swap/releases>

Asset names for **v267** (verified):

| Platform | Asset | Size |
|----------|-------|------|
| Linux x86-64 | `llama-swap_267_linux_amd64.tar.gz` | 24.0 MB |
| Linux ARM64 | `llama-swap_267_linux_arm64.tar.gz` | 22.4 MB |
| macOS Apple Silicon | `llama-swap_267_darwin_arm64.tar.gz` | 22.8 MB |
| macOS Intel | `llama-swap_267_darwin_amd64.tar.gz` | 23.8 MB |
| Windows x86-64 | `llama-swap_267_windows_amd64.zip` | 23.9 MB |

```bash
# Linux / macOS — adjust OS and ARCH for your machine
curl -L -o llama-swap.tar.gz \
  https://github.com/mostlygeek/llama-swap/releases/download/v267/llama-swap_267_linux_amd64.tar.gz
tar xzf llama-swap.tar.gz
sudo mv llama-swap /usr/local/bin/
llama-swap --version
```

### Docker — includes the engine

Useful if you do not want to build llama.cpp at all. The image ships `llama-server` alongside llama-swap.

```bash
docker pull ghcr.io/mostlygeek/llama-swap:cpu     # ← CPU-only: the one students want
docker pull ghcr.io/mostlygeek/llama-swap:cuda    # NVIDIA
docker pull ghcr.io/mostlygeek/llama-swap:vulkan
docker pull ghcr.io/mostlygeek/llama-swap:unified-cuda   # CUDA or Vulkan only; bundles
                                                          # whisper.cpp + stable-diffusion.cpp too
```

```bash
docker run -it --rm -p 9292:8080 \
  -v ~/models:/models \
  -v ./configs/llama-swap/config.yaml:/etc/llama-swap/config/config.yaml \
  ghcr.io/mostlygeek/llama-swap:unified-cuda
```

Note the image listens on **8080 inside the container**, so `-p 9292:8080` publishes it as `:9292` on your machine. The legacy `:cpu`/`:cuda` images mount config at `/app/config.yaml` instead — check the docs for the image you pick.

### Windows — WinGet

```powershell
winget install llama-swap
```

Community-maintained, not official upstream. Prefer WSL2 for this workshop.

### From source

Needs Go and Node.js (Node is for the web UI):

```bash
git clone https://github.com/mostlygeek/llama-swap.git
cd llama-swap
make clean all
./build/llama-swap --version
```

---

## The minimum viable config

This is genuinely all llama-swap needs — quoted from upstream:

```yaml
models:
  model1:
    cmd: llama-server --port ${PORT} --model /path/to/model.gguf
```

Four things to understand:

1. **`models`** is the only **required** top-level key.
2. **`model1`** is the id clients put in `"model": "model1"`.
3. **`cmd`** is the only required key *inside* a model — the command that starts the engine.
4. **`${PORT}`** is substituted automatically with a free port.

Everything else is optional. Add settings one at a time as you need them.

---

## Macros — define paths once

Repeating a long binary path in every model is how configs rot. `macros:` is text substitution:

```yaml
macros:
  model-dir: "/home/YOURNAME/models"
  llama-server-path: "llama-server"
  common-args: "--host 127.0.0.1 --port ${PORT} --jinja"

models:
  chat:
    cmd: >
      ${llama-server-path}
      -m ${model-dir}/Qwen3-1.7B-Q4_K_M.gguf
      ${common-args}
      -c 8192
```

Three rules, all verified against llama-swap's own source:

- **`${PORT}` and `${MODEL_ID}` are reserved.** Defining them is an error: `macro name 'PORT' is reserved`.
- **An unknown macro is a hard failure**, not a silent empty string: `unknown macro '${foo}' found in chat.cmd`. That is a feature — typos surface at startup instead of running a broken command.
- **Environment variables are not macros.** `${HOME}` will *not* work; you will get the unknown-macro error. This is why the workshop config has you edit `model-dir` once.

Per-model macros override global ones:

```yaml
macros:
  quant: "Q4_K_M"
models:
  big:
    macros:
      quant: "Q8_0"       # this model only
    cmd: llama-server --port ${PORT} -m /models/x-${quant}.gguf
```

---

## The workshop config

Use [`configs/llama-swap/config.yaml`](../configs/llama-swap/config.yaml). It defines four models — `chat`, `coder`, `embed`, `tiny` — sized for a 16 GB CPU-only laptop.

**Edit the three macros at the top first:** `model-dir`, `llama-server-path`, and `ngl` (`0` for CPU, `999` if you have a GPU).

Then run it in the foreground, so you can read what it is doing:

```bash
llama-swap --config configs/llama-swap/config.yaml
```

Default listen address is `:8080` (or `:8443` with TLS). To be explicit, or to avoid a clash:

```bash
llama-swap --config configs/llama-swap/config.yaml --listen 127.0.0.1:8090
```

**Validate the config before running it** — it checks the YAML and exits without starting anything:

```bash
llama-swap --config configs/llama-swap/config.yaml --validate
```

This is the fastest feedback loop there is for a macro typo or a bad key, and it costs nothing. (Needs **v252 or newer**; older builds have no `-validate`.)

Also worth knowing while learning: **`-watch-config`** reloads the YAML when you save it, so you can add a model live without restarting — and without evicting the ones already loaded.

```bash
llama-swap --config configs/llama-swap/config.yaml --watch-config
```

Go's flag package accepts single or double dashes, so `-config` and `--config` are the same flag.

> **Run it in the foreground during the workshop.** When a model fails to start, the reason appears in this log. Daemonising it early means debugging blind, and `upstream command exited prematurely` tells you nothing about *why*.

---

## Verify it

In a second terminal:

```bash
# what COULD run (this starts nothing)
curl -s http://127.0.0.1:8090/v1/models | jq -r '.data[].id'

# what IS running right now
curl -s http://127.0.0.1:8090/running | jq
```

`/v1/models` lists everything in your config. `/running` starts out empty — **listing a model is not proof it works.** Only a real request proves that.

```bash
time curl -s http://127.0.0.1:8090/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"chat","messages":[{"role":"user","content":"Say OK"}],"max_tokens":8}' \
  | jq -r '.choices[0].message.content'
```

The first call is slow — that is the cold load. Run it again and compare the `time`. Then:

```bash
curl -s http://127.0.0.1:8090/running | jq
```

Now ask for a *different* model and check `/running` again. You should see the first one gone. That eviction is the entire point of llama-swap, and Exercise 4 makes you watch it happen.

---

## Per-model settings

All verified against llama-swap's `config-schema.json`. Only `cmd` is required.

| Key | Default | Purpose |
|-----|---------|---------|
| `cmd` | **required** | Command that starts the engine |
| `cmdStop` | — | Command to stop it, if killing the process is not enough (e.g. `docker stop ${MODEL_ID}`) |
| `proxy` | `http://localhost:${PORT}` | Where to forward. Omit it unless your engine listens somewhere unusual |
| `ttl` | `-1` | Seconds idle before unloading. `-1` = use `globalTTL` |
| `aliases` | `[]` | Extra names that resolve to this model |
| `env` | `[]` | Environment variables for the child process |
| `macros` | `{}` | Overrides the global `macros:` for this model |
| `checkEndpoint` | `/health` | Path probed to decide the engine is ready |
| `unlisted` | `false` | Hide from `/v1/models` while still serving it |
| `concurrencyLimit` | `0` | Cap simultaneous requests to this model |
| `name`, `description` | — | Metadata shown in the `/ui` |
| `useModelName` | — | Rewrite the model name sent upstream |
| `filters` | `{}` | Modify requests in flight (e.g. `stripParams`) |
| `metadata` | `{}` | Arbitrary data, macros expanded |
| `sendLoadingState` | — | Per-model override of the global setting |

A rule worth remembering: **`proxy` may only use `${PORT}` if `cmd` uses it too.** Otherwise you get `proxy uses ${PORT} but cmd does not - ${PORT} is only available when used in cmd`.

---

## Top-level settings

| Key | Default | Purpose |
|-----|---------|---------|
| `models` | **required** | Your model definitions |
| `healthCheckTimeout` | `120` | Seconds to wait for an engine to become healthy; **minimum 15** (lower is clamped up). **Raise this** — a cold load that has to *download* a model blows past 120 easily. The workshop config uses `300` |
| `startPort` | `5800` | First port handed out to engines, incremented per model |
| `globalTTL` | `0` | Idle seconds before unloading any model; per-model `ttl` overrides |
| `logLevel` | `info` | Verbosity |
| `logToStdout` | `proxy` | What goes to stdout |
| `logTimeFormat` | `""` | Timestamp format |
| `sendLoadingState` | `true` | Tell clients a model is loading instead of hanging silently |
| `includeAliasesInList` | `false` | Show aliases in `/v1/models` |
| `macros` | — | Global text substitution |
| `apiKeys` | — | Require auth on llama-swap itself |
| `groups` | — | Run several models concurrently |
| `timeouts` | — | connect / keepalive / responseHeader / tlsHandshake / idleConn |
| `performance` | — | Profiling |
| `metricsMaxInMemory`, `captureBuffer` | `1000`, `15` | Metrics retention |
| `hooks` | — | e.g. `on_startup.preload` — warm models at boot |
| `matrix` | — | Concurrent models with a custom swap-policy DSL |
| `peers` | — | Peer instances |

---

## Groups — when you need two models at once

Embeddings plus chat is the classic case: a RAG pipeline needs both, and you do not want them evicting each other on every call.

```yaml
groups:
  rag:
    swap: false          # members do NOT evict each other
    members:
      - chat
      - embed
```

Then address the group like a model:

```bash
curl -s http://127.0.0.1:8090/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"rag","messages":[{"role":"user","content":"hi"}]}' | jq
```

Group keys (verified): `swap`, `exclusive`, `persistent`, `members`.

**The cost is RAM** — every member stays loaded. On 16 GB keep groups to two small models. `persistent: true` keeps a group always warm, which is worth it for something you hit constantly and cheap enough to leave resident.

---

## Its HTTP surface

| Endpoint | What it does |
|----------|--------------|
| `GET /v1/models` | Lists configured models — **starts nothing** |
| `POST /v1/chat/completions` | Chat; cold-loads the model if needed |
| `POST /v1/completions` | Raw completion |
| `POST /v1/embeddings` | Embeddings |
| `POST /v1/responses` | OpenAI Responses API |
| `POST /v1/messages` | **Anthropic** API shape |
| `POST /v1/rerank` | Reranking (llama.cpp backend) |
| `POST /v1/audio/transcriptions` | Speech-to-text |
| `POST /v1/images/generations` | Image generation (stable-diffusion.cpp) |
| `GET /running` | Models currently loaded |
| `GET /ui` | Web UI |
| `GET /logs` | Buffered logs (HTML `Accept` redirects to `/ui/`) |
| `GET /logs/stream` | Live log stream; `?no-history` skips the backlog |
| `POST /api/models/unload` | Unload everything |
| `POST /api/models/unload/:model_id` | Unload one |
| `GET /upstream/:model_id` | Direct passthrough to that engine |

Two of these are genuinely useful while debugging: `/logs/stream` shows you what the engine is doing in real time, and `/api/models/unload` gets your RAM back without restarting anything.

---

## Letting it download models for you

No local files at all:

```yaml
models:
  chat:
    cmd: >
      llama-server
      -hf ggml-org/Qwen3-1.7B-GGUF:Q4_K_M
      --host 127.0.0.1 --port ${PORT} -c 8192
```

Or use `${MODEL_ID}` so the id doubles as the HF repo:

```yaml
models:
  ggml-org/Qwen3-1.7B-GGUF:Q4_K_M:
    cmd: llama-server -hf ${MODEL_ID} --port ${PORT}
```

**Do not do this in a classroom.** Every student triggers their own multi-GB download at the same moment, with no coordination and no shared cache. Pre-download with [`scripts/download-models.sh`](../scripts/download-models.sh), or use the instructor's mirror — see [offline-models.md](offline-models.md).

---

## Debugging

**`{"src":"llama-swap","error":"unspecific error: upstream command exited prematurely"}`**

llama-swap is fine; the engine died. Take the `cmd` from your config, replace `${PORT}` with a real number, and **run it by hand**:

```bash
llama-server -m /home/YOURNAME/models/Qwen3-1.7B-Q4_K_M.gguf \
  --host 127.0.0.1 --port 18080 -c 8192
```

Now you get a real error instead of a one-line summary. Usually: wrong binary path, wrong model path, out of memory, or a flag the engine does not recognise.

**Config changed but nothing happened**

Restart llama-swap, or run it with `-watch-config` so edits reload on save. Be aware that a plain restart **evicts every loaded model**, so the next request pays a cold load — `-watch-config` avoids that.

**Validate before you debug**

```bash
llama-swap --config configs/llama-swap/config.yaml --validate
```

Catches macro typos and unknown keys without starting anything. Requires v252+.

**Macro errors at startup**

Read them — they name the model and the field: `unknown macro '${foo}' found in chat.cmd`. Remember `${HOME}` is not a macro; define `model-dir` instead.

**Model never becomes healthy**

Raise `healthCheckTimeout`. The upstream default is only **120 seconds**, and a first run that has to *download* the model will exceed it. The workshop config sets `300`.

> One nuance if you are chasing a timeout: when an upstream reports `progress` on its health endpoint, **each change restarts the countdown**, so the timeout limits time *without progress* rather than total time. `llama-server`'s loading response does **not** report progress, so for llama.cpp it remains a hard total.

Full list in [troubleshooting.md](troubleshooting.md#llama-swap).

---

## Why bother, when you could just run llama-server?

Fair question, and for a single model you should not bother. llama-swap earns its place when:

- You have **several** models and one machine
- You want **specialists** — a coder, a chatter, an embedder — without paying RAM for all three at once
- You want **one stable URL** for everything above it, so LiteLLM and your agents never change when you swap a model
- You want **idle models to give memory back** automatically

That last one is the killer feature on a laptop. It is the difference between "I can run one model" and "I have a local model service".

---

**Next:** [04 — LiteLLM: one gateway, local and cloud](04-litellm.md)

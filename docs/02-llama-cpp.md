# 2 — llama.cpp: run a model on your laptop

This is the layer that does the actual work. Everything above it — llama-swap, LiteLLM, your coding agent — is convenience. Get this working first and you have self-hosted an LLM.

By the end of this page you will have a model answering HTTP requests on `:8080`, and you will know what your own machine can do.

---

## What llama.cpp is

A C/C++ inference engine for GGUF model files. No Python, no dependencies, no GPU required. It runs on a laptop CPU, on Apple Silicon's Metal, on NVIDIA and AMD GPUs, and on a Raspberry Pi.

It ships several binaries. Three matter here:

| Binary | Purpose |
|--------|---------|
| **`llama-server`** | HTTP server with an OpenAI-compatible API. What you will use. |
| **`llama-cli`** | Chat in your terminal. A quick sanity check that avoids all networking. |
| **`llama-bench`** | Measures your hardware. Run this first — see below. |

---

## Install

Pick one path for your OS.

### macOS — Homebrew

```bash
brew install llama.cpp
llama-server --version
```

Apple Silicon gets Metal support in this build, so models offload to the GPU automatically.

### Ubuntu / WSL2 — build from source

There is no good apt package; building takes a few minutes and is worth doing once so you understand where the binary came from.

```bash
sudo apt update && sudo apt install -y build-essential cmake git
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build
cmake --build build --config Release -j"$(nproc)"
```

The binaries land in `build/bin/`. Put them on your PATH:

```bash
echo 'export PATH="$HOME/llama.cpp/build/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
llama-server --version
```

> **NVIDIA GPU on Linux?** Add `-DGGML_CUDA=ON` to the `cmake -B build` line. You will need the CUDA toolkit. The workshop does not require this.

### Windows (native, if you refused WSL2)

Download a prebuilt release from <https://github.com/ggml-org/llama.cpp/releases>. Pick the `cudart-llama-bin-win-…` asset for NVIDIA, or the plain `llama-…-bin-win-…` one for CPU. Unzip and run `llama-server.exe` from that folder.

Prefer WSL2 — every command in this repo is written for a POSIX shell.

### Verify

```bash
llama-server --version
```

You should see a build number, for example `version: 9761 (721354fbd)`. Write yours down; behaviour differs between builds and instructors will ask.

---

## Step 1 — measure your machine before choosing a model

Do this first. It takes a minute and it replaces every guess you were about to make.

```bash
llama-bench -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -ngl 0
```

You get a markdown table. The two columns that matter:

- **`pp512`** — prefill, tokens/second. How fast it *digests your prompt*. Drives time-to-first-token.
- **`tg128`** — decode, tokens/second. How fast it *writes the answer*. Drives how long you wait.

Useful variations:

```bash
llama-bench -m MODEL.gguf -ngl 0 -r 3      # 3 repetitions instead of the default 5 (faster)
llama-bench -m MODEL.gguf -ngl 0 -o csv    # machine-readable
llama-bench --list-devices                 # what hardware llama.cpp can see
llama-bench -hf ggml-org/Qwen3-1.7B-GGUF:Q4_K_M   # bench without downloading by hand
```

Defaults, verified: `-p/--n-prompt 512`, `-n/--n-gen 128`, `-r 5` repetitions, `-o md` output.

**Read your `tg128` number and set expectations now.** Under ~5 tok/s is painful for chat; 10–20 is comfortable; 40+ is instant-feeling. Exercise 1 makes you do this properly.

---

## Step 2 — serve a model

The command you will use all day:

```bash
llama-server \
  -m ~/models/Qwen3-1.7B-Q4_K_M.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  -c 8192 \
  -np 1
```

Watch the startup log. You want to see it load the model and then say it is listening on the port. Leave this terminal open — `Ctrl-C` stops it.

Then, in a **second** terminal:

```bash
curl -s http://127.0.0.1:8080/v1/models | jq
```

If that lists a model, you are serving an LLM. Now talk to it:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen",
    "messages": [{"role": "user", "content": "Explain quantisation in one sentence."}],
    "max_tokens": 200
  }' | jq -r '.choices[0].message.content'
```

The `"model"` value does not have to match anything — llama-server ignores it and serves whatever is loaded. LiteLLM above it is what cares about names.

---

## Flag reference

Every flag below was verified against `llama-server --help`.

### The ones you need

| Flag | Default | Notes |
|------|---------|-------|
| `-m, --model FNAME` | — | Path to the `.gguf`. Env: `LLAMA_ARG_MODEL` |
| `--host HOST` | `127.0.0.1` | Bind address. Ends in `.sock` → a UNIX socket instead |
| `--port PORT` | `8080` | Env: `LLAMA_ARG_PORT` |
| `-c, --ctx-size N` | `0` | **`0` means "load the model's own context"** — not zero. On a 128k model that is a huge KV cache. Always set this explicitly |
| `-ngl, --n-gpu-layers N` | `auto` | Layers in VRAM. Accepts a number, `auto`, or `all`. `0` forces CPU |
| `-np, --parallel N` | `-1` (auto) | Server slots. Auto chose **4** in testing — see the context warning below |
| `-t, --threads N` | `-1` | CPU threads. Set to your *physical* core count; more hurts |
| `-hf, --hf-repo <user>/<model>[:quant]` | unused | Download from Hugging Face on start |

### Quality and behaviour

| Flag | Default | Notes |
|------|---------|-------|
| `--jinja` / `--no-jinja` | **enabled** | Use the chat template embedded in the GGUF. On by default in current builds; older builds needed it explicitly. Required for tool calling |
| `--temp N` | `0.80` | Randomness. Code and tool calls want `0.0`–`0.3` |
| `--top-p N` | `0.95` | `1.0` disables |
| `--top-k N` | `40` | `0` disables |
| `--min-p N` | `0.05` | `0.0` disables |
| `--reasoning-budget N` | — | Thinking-token budget. `-1` unrestricted, **`0` ends thinking immediately** |
| `--reasoning-format FMT` | — | `none` leaves thoughts in `message.content`; `deepseek` puts them in `message.reasoning_content` |
| `--cache-prompt` | enabled | Reuse prompt KV across turns |

### Memory

| Flag | Default | Notes |
|------|---------|-------|
| `-fa, --flash-attn [on\|off\|auto]` | `auto` | Flash Attention |
| `-ctk, --cache-type-k TYPE` | `f16` | KV cache K dtype |
| `-ctv, --cache-type-v TYPE` | `f16` | KV cache V dtype |

Allowed `-ctk`/`-ctv` values: `f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1`. Using `q8_0` roughly halves the KV cache.

### Specialised modes

| Flag | Notes |
|------|-------|
| `--embedding` | Restrict the server to embeddings only. Use with a dedicated embedding model; serve `/v1/embeddings` |
| `--pooling {none,mean,cls,last,rank}` | Embedding pooling. Model default if unspecified |
| `-mm, --mmproj FILE` | Multimodal projector for vision models. **Downloaded automatically when you use `-hf`** |
| `--api-key KEY` | Require a bearer token. Comma-separated for several. Env: `LLAMA_API_KEY` |
| `--warmup` / `--no-warmup` | Default enabled. Warmup runs an empty pass so the first real request is not slow |

---

## The context / parallel trap

This one catches everyone, and it is worth understanding properly.

`-np` defaults to *auto*, which picked **4** slots in testing. What `-c` then means depends on whether you set `-np` yourself. Measured on build 9761, same model each run:

| Flags | `n_ctx_seq` reported | Meaning |
|-------|----------------------|---------|
| `-c 4096` (auto) | **4096** | auto enables a *unified* KV cache — slots share one pool |
| `-c 4096 -np 1` | **4096** | one slot, full context |
| `-c 4096 -np 4` | **1024** | explicit parallel **divides** the context: 4096 ÷ 4 |

So typing `-np 4` yourself gives each request a *quarter* of the context you asked for. If you want four concurrent slots at 4096 each, request `-c 16384 -np 4`.

**For this workshop, use `-np 1`.** You are one person. Four idle slots cost you RAM and context for nothing.

`-c` also cannot exceed the model's trained context — beyond it you get `possible training context overflow`. SmolLM2-135M is trained to 8192, so `-c 16384` warns.

---

## Downloading without managing files

Skip `hf download` entirely and let the engine fetch it:

```bash
llama-server -hf ggml-org/Qwen3-1.7B-GGUF:Q4_K_M --port 8080
```

Verified behaviour of `-hf <user>/<model>[:quant]`:

- The `:quant` suffix is **optional and case-insensitive**
- Defaults to **`Q4_K_M`**, and falls back to the first file in the repo if that quant does not exist
- **`mmproj` is downloaded automatically** when present, so vision models just work
- Gated repos need `--hf-token` or the `HF_TOKEN` environment variable

Convenient at home. **Bad in a classroom** — twenty-five students each trigger a multi-GB download simultaneously. Pre-download instead; see [offline-models.md](offline-models.md).

---

## Embeddings

A different mode, and the highest-value thing to self-host. Tiny models, genuinely good results, zero cost.

```bash
llama-server -m ~/models/nomic-embed-text-v1.5.Q8_0.gguf \
  --host 127.0.0.1 --port 8081 -c 2048 -np 1 --embedding
```

```bash
curl -s http://127.0.0.1:8081/v1/embeddings \
  -H "Content-Type: application/json" \
  -d '{"model":"nomic","input":"the quick brown fox"}' \
  | jq '.data[0].embedding | length'
```

That number is your vector dimension. Now you can search your own documents by cosine similarity, entirely offline.

Note `--embedding` **restricts** the server to embeddings — it will not do chat. Run chat and embeddings as two servers on two ports, which is exactly what llama-swap automates in [the next chapter](03-llama-swap.md).

---

## Vision

Two files: the model, and a projector (`mmproj`) that encodes the image.

```bash
llama-server \
  -m ~/models/Qwen3VL-2B-Instruct-Q4_K_M.gguf \
  --mmproj ~/models/mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf \
  --host 127.0.0.1 --port 8082 -c 4096 -np 1
```

With `-hf` you can omit `--mmproj` — it is fetched automatically.

Expect 10–30 seconds per image on a CPU. Fine for a demo, not for a workflow.

---

## A quick check without any HTTP

When something is wrong, remove networking from the equation:

```bash
llama-cli -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -c 2048 -ngl 0 \
  -p "Explain in one sentence why models are quantised."
```

If that works and `llama-server` does not, the problem is your server flags or a port conflict — not the model.

---

## Sanity-checking your work

```bash
# is it listening?
curl -s http://127.0.0.1:8080/health

# what is loaded?
curl -s http://127.0.0.1:8080/v1/models | jq -r '.data[].id'

# does a completion actually return?
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"m","messages":[{"role":"user","content":"Say OK"}],"max_tokens":8}' | jq
```

If the third one returns an empty `content`, check `reasoning_content` — a thinking model may have spent the whole `max_tokens` budget on reasoning. Either raise `max_tokens` or pass `--reasoning-budget 0`.

---

## Common failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Address already in use` | Something owns `:8080` | Change `--port`, or find it: `ss -ltnp \| grep :8080` |
| Process vanishes, no error | Out of memory | Lower `-c`; see [troubleshooting](troubleshooting.md#out-of-memory) |
| Gibberish or repetition | Wrong chat template | You passed `--no-jinja`, or your build predates jinja-by-default |
| Empty `content`, huge `reasoning_content` | Thinking model ate the budget | Raise `max_tokens`, or `--reasoning-budget 0` |
| `possible training context overflow` | `-c` above the model's trained ceiling | Lower `-c` to the model card's value |
| Slower than expected | Threads set too high, or `-ngl 0` on a GPU box | `-t $(nproc)`; drop `-ngl 0` |
| Tool calls malformed | Model too small | Not a flag problem — see [Exercise 2](../exercises/README.md#exercise-2--break-a-tiny-model-on-purpose) |

Full details in [troubleshooting.md](troubleshooting.md).

---

**Next:** [03 — llama-swap: several models, one port](03-llama-swap.md)

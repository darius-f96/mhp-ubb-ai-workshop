# Model catalogue — what to actually download

Every model on this page was verified against the Hugging Face API on **2026-10-26**: the repo ID exists, the file exists, and the size shown is that file's real byte count. Nothing here is guessed.

**Your baseline:** a 16 GB laptop, no discrete GPU. That is the constraint every recommendation below respects.

---

## The short answer

If you want to stop reading and just get going, download these three and you can do every exercise in this workshop:

```bash
mkdir -p ~/models && cd ~/models

# 1. The workhorse: small, fast, genuinely useful on CPU      (1.28 GB)
hf download ggml-org/Qwen3-1.7B-GGUF Qwen3-1.7B-Q4_K_M.gguf --local-dir .

# 2. A code specialist                                          (1.12 GB)
hf download Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF qwen2.5-coder-1.5b-instruct-q4_k_m.gguf --local-dir .

# 3. An embedding model for retrieval                           (0.15 GB)
hf download nomic-ai/nomic-embed-text-v1.5-GGUF nomic-embed-text-v1.5.Q8_0.gguf --local-dir .
```

Total: **2.55 GB**. If your disk or the venue Wi-Fi is tight, do just #1 — it is enough for most of the day.

> No `hf` command? Install it with `pip install -U huggingface_hub`, or use [the download script](../scripts/download-models.sh) which falls back to plain `curl`.

---

## Understanding the numbers

Two numbers decide whether a model runs on your laptop.

**File size** is what the weights occupy in RAM once loaded. A quantised model is stored at reduced precision, and the suffix in the filename tells you how far it was reduced:

| Suffix | Bits per weight | Quality | Use it when |
|--------|-----------------|---------|-------------|
| `Q8_0` | 8 | Near-lossless | You have RAM to spare |
| `Q6_K` | 6 | Excellent | Good default on 16 GB |
| `Q5_K_M` | 5 | Very good | Balancing act |
| **`Q4_K_M`** | **4** | **Good** | **← the workshop default. Best quality-per-GB on a laptop** |
| `Q3_K_M` | 3 | Noticeably worse | You are desperate for RAM |
| `Q2_K`, `IQ2_*` | 2 | Poor | Demos of what quantisation destroys |

Rule of thumb: **RAM for weights ≈ file size + 10–20%.**

**Context size** (`-c`) is how many tokens the model can hold in one conversation — your prompt plus its reply plus everything before it. Context is *not* free; it allocates a **KV cache** whose size grows linearly with `-c`. This is the thing that kills laptops, not the model file.

llama.cpp reports what it allocated — read the startup log rather than guessing:

```bash
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -c 32768 --port 8080 2>&1 \
  | grep -iE 'kv|n_ctx|model size'
```

Look for the KV cache size in MiB and the `n_ctx` line saying what context you actually got. Wording varies between llama.cpp versions; the numbers are what matter. If the KV figure is more than you can afford, lower `-c`. Two cheap wins:

```bash
-ctk q8_0 -ctv q8_0    # quantise the KV cache — roughly halves it vs the f16 default
-fa on                 # Flash Attention
# long forms: --cache-type-k / --cache-type-v / --flash-attn
```

Allowed `-ctk`/`-ctv` values (verified): `f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1`; default `f16`.

### Two context traps worth knowing before you start

**`-c 0` means "use the model's own context", not zero.** That is the default. On a model trained for 128k it will try to allocate a KV cache for 128k and take your laptop with it. Always set `-c` explicitly.

**Parallel slots eat your context.** `-np/--parallel` now defaults to *auto*, which chose **4** slots in testing. How `-c` interacts with that depends on whether you set `-np` yourself. Measured on llama.cpp build 9761, same model each time:

| Flags | `n_ctx_seq` reported | What happened |
|-------|----------------------|---------------|
| `-c 4096` (auto) | **4096** | auto turns on a *unified* KV cache, so slots share one pool |
| `-c 4096 -np 1` | **4096** | one slot, full context |
| `-c 4096 -np 4` | **1024** | explicit parallel **divides** it: 4096 ÷ 4 |

Setting `-np 4` by hand therefore gives each request *less* context than leaving it alone. Want four concurrent slots at 4096 each? Ask for `-c 16384 -np 4`.

**`-c` cannot exceed what the model was trained on.** Going past it does not silently work — you get `possible training context overflow`. SmolLM2-135M is trained to 8192, so `-c 16384` warns. Check the model card for the trained ceiling.

### Realistic budgets on a 16 GB laptop

Your OS, browser, Docker and IDE already eat 6–8 GB. Treat **~6 GB as your total model budget** and you will be fine.

| Configuration | Weights | KV cache | Total | Verdict |
|---------------|---------|----------|-------|---------|
| Qwen3-1.7B Q4_K_M, `-c 8192` | 1.3 GB | ~0.2 GB | **~1.5 GB** | Comfortable. Use this. |
| Qwen3-4B Q4_K_M, `-c 8192` | 2.5 GB | ~0.3 GB | **~2.8 GB** | Fine. Slower, much smarter. |
| Qwen3-4B Q4_K_M, `-c 32768` | 2.5 GB | ~1.2 GB | **~3.7 GB** | Works if you close things. |
| Qwen3-8B Q4_K_M, `-c 8192` | 4.9 GB | ~0.5 GB | **~5.4 GB** | Tight, and slow on CPU. |
| Anything 14B+, or `-c 131072` | — | — | — | **No.** You will swap and it will crawl. |

Speed expectation for CPU-only inference: a 1.7B Q4 model gives roughly **8–20 tokens/second** on a modern laptop CPU; a 4B gives **4–10**. That is readable, not instant. Measure your own machine with `llama-bench` (see [the llama.cpp guide](02-llama-cpp.md)).

---

## The catalogue

Sorted by what each model is *for*. Sizes are the Q4_K_M file unless noted.

### General chat and instruction following

The all-rounders. Pick one; you do not need several.

| Model | HF repo | File | Size | Notes |
|-------|---------|------|------|-------|
| **Qwen3-1.7B** ⭐ | `ggml-org/Qwen3-1.7B-GGUF` | `Qwen3-1.7B-Q4_K_M.gguf` | **1.28 GB** | The workshop default. Good tool calling, hybrid thinking mode. |
| Qwen3-4B | `ggml-org/Qwen3-4B-GGUF` | `Qwen3-4B-Q4_K_M.gguf` | 2.50 GB | The best you can comfortably run. Use it if your laptop is not struggling. |
| Qwen3-0.6B | `ggml-org/Qwen3-0.6B-GGUF` | `Qwen3-0.6B-Q4_0.gguf` | 0.43 GB | Very fast, very weak. Good for proving plumbing works. |
| Gemma 3 1B | `ggml-org/gemma-3-1b-it-GGUF` | `gemma-3-1b-it-Q4_K_M.gguf` | 0.81 GB | Google's small model. Solid prose. |
| Gemma 3 4B | `ggml-org/gemma-3-4b-it-GGUF` | `gemma-3-4b-it-Q4_K_M.gguf` | 2.49 GB | **Has vision** — needs the `mmproj-model-f16.gguf` (0.85 GB) too. |
| Llama 3.2 3B | `unsloth/Llama-3.2-3B-Instruct-GGUF` | `Llama-3.2-3B-Instruct-Q4_K_M.gguf` | 2.02 GB | Meta's small model. Widely known, decent. |
| SmolLM3 3B | `unsloth/SmolLM3-3B-GGUF` | `SmolLM3-3B-Q4_K_M.gguf` | 1.92 GB | Hugging Face's own. **Open weights, Apache-style licence, no gating.** |
| Ministral 3 3B | `mistralai/Ministral-3-3B-Instruct-2512-GGUF` | `Ministral-3-3B-Instruct-2512-Q4_K_M.gguf` | 2.15 GB | Mistral's small model, with vision (`-BF16-mmproj.gguf`, 0.84 GB). |
| Phi-4-mini | `unsloth/Phi-4-mini-instruct-GGUF` | `Phi-4-mini-instruct-Q4_K_M.gguf` | 2.49 GB | Microsoft. Punches above its weight on reasoning. |
| Granite 4.0 micro | `ibm-granite/granite-4.0-micro-GGUF` | `granite-4.0-micro-Q4_K_M.gguf` | 2.10 GB | IBM. Apache 2.0, commercially friendly. |
| LFM2.5 1.2B | `LiquidAI/LFM2.5-1.2B-Instruct-GGUF` | `LFM2.5-1.2B-Instruct-Q4_K_M.gguf` | 0.73 GB | Non-transformer architecture — **notably fast on CPU**. Interesting to compare. |

### Code

General models are mediocre at code. These are trained for it.

| Model | HF repo | File | Size | Notes |
|-------|---------|------|------|-------|
| **Qwen2.5-Coder 1.5B** ⭐ | `Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF` | `qwen2.5-coder-1.5b-instruct-q4_k_m.gguf` | **1.12 GB** | Surprisingly good. The one to pair with a coding agent. |
| Qwen2.5-Coder 3B | `Qwen/Qwen2.5-Coder-3B-Instruct-GGUF` | `qwen2.5-coder-3b-instruct-q4_k_m.gguf` | 2.10 GB | Better, still runnable. |

> Note the filenames in the `Qwen/` repos are **lowercase**, unlike `ggml-org/`. That is a real source of 404s — copy them exactly.

### Embeddings (retrieval / RAG)

Turn text into vectors so you can search it. Tiny and fast; you should always run these locally.

| Model | HF repo | File | Size | Notes |
|-------|---------|------|------|-------|
| **nomic-embed-text v1.5** ⭐ | `nomic-ai/nomic-embed-text-v1.5-GGUF` | `nomic-embed-text-v1.5.Q8_0.gguf` | **0.15 GB** | The classic. 768 dims, Matryoshka (truncatable). |
| Qwen3-Embedding 0.6B | `Qwen/Qwen3-Embedding-0.6B-GGUF` | `Qwen3-Embedding-0.6B-Q8_0.gguf` | 0.64 GB | Stronger, multilingual. |
| bge-small-en v1.5 | `unsloth/bge-small-en-v1.5-GGUF` | `bge-small-en-v1.5-f16.gguf` | 0.07 GB | 33M params. Absurdly small, English only. |
| Qwen3-Embedding 4B | `Qwen/Qwen3-Embedding-4B-GGUF` | `Qwen3-Embedding-4B-Q4_K_M.gguf` | 2.50 GB | Best quality here — but too big to run alongside a chat model. |

Embedding models need a different server flag: `--embedding` (and `--pooling cls` for bge). See [the llama.cpp guide](02-llama-cpp.md#embeddings).

### Reranking (retrieval quality)

Re-scores your top-N search results so the best one is actually first. Pairs with an embedding model.

| Model | HF repo | File | Size |
|-------|---------|------|------|
| Qwen3-Reranker 0.6B | `ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF` | `qwen3-reranker-0.6b-q8_0.gguf` | 0.64 GB |

Served by llama.cpp's `/v1/rerank` endpoint.

### Vision (images in, text out)

These need **two** files: the model, plus an `mmproj` projector that encodes the image. Pass the projector with `--mmproj`.

| Model | HF repo | Model file | Size | mmproj file | mmproj size |
|-------|---------|-----------|------|-------------|-------------|
| **Qwen3-VL 2B** ⭐ | `Qwen/Qwen3-VL-2B-Instruct-GGUF` | `Qwen3VL-2B-Instruct-Q4_K_M.gguf` | 1.11 GB | `mmproj-Qwen3VL-2B-Instruct-Q8_0.gguf` | 0.45 GB |
| SmolVLM2 2.2B | `ggml-org/SmolVLM2-2.2B-Instruct-GGUF` | `SmolVLM2-2.2B-Instruct-Q4_K_M.gguf` | 1.11 GB | `mmproj-SmolVLM2-2.2B-Instruct-Q8_0.gguf` | 0.59 GB |
| Gemma 3 4B | `ggml-org/gemma-3-4b-it-GGUF` | `gemma-3-4b-it-Q4_K_M.gguf` | 2.49 GB | `mmproj-model-f16.gguf` | 0.85 GB |

Vision on CPU is slow — expect 10–30 seconds per image. Fine for a demo, not for a workflow.

### Speech-to-text

| Model | HF repo | File | Size | Notes |
|-------|---------|------|------|-------|
| Qwen3-ASR 0.6B | `ggml-org/Qwen3-ASR-0.6B-GGUF` | `Qwen3-ASR-0.6B-Q8_0.gguf` | 0.80 GB | Plus `mmproj-Qwen3-ASR-0.6B-Q8_0.gguf` (0.21 GB). |

### Math

| Model | HF repo | File | Size |
|-------|---------|------|------|
| Qwen2.5-Math 1.5B | `bartowski/Qwen2.5-Math-1.5B-Instruct-GGUF` | `Qwen2.5-Math-1.5B-Instruct-Q4_K_M.gguf` | 0.99 GB |

### The deliberately terrible model

| Model | HF repo | File | Size |
|-------|---------|------|------|
| SmolLM2 135M | `unsloth/SmolLM2-135M-Instruct-GGUF` | `SmolLM2-135M-Instruct-Q4_K_M.gguf` | **0.11 GB** |

Download this one. It is 135 million parameters — roughly 13× smaller than the workhorse. Ask it the same question you asked Qwen3-1.7B and compare. This is the single most instructive five minutes of the workshop: it makes the relationship between scale, quantisation and capability something you have *seen* rather than been told.

Also useful for load-testing: it starts instantly and uses no RAM, so you can verify your whole llama-swap → LiteLLM → agent chain end to end without waiting.

---

## Licences — read this once

"Open weights" is not one thing. Roughly:

- **Permissive** (Apache 2.0 / MIT — use it commercially, no conditions): SmolLM family, Granite 4.0, nomic-embed-text, bge, LFM2.5.
- **Qwen licence** — free including commercial use, but has an acceptable-use policy and (for very large deployments) registration terms.
- **Gated** — Meta's Llama 3.2 and Mistral's Ministral require you to log in to Hugging Face and click through a licence before the download works. `hf download` will fail with `401 Unauthorized` until you do, and then need `hf auth login`.

For a workshop, prefer the ungated permissive models — no student should spend ten minutes on a licence form. That is one reason Qwen3 and SmolLM are the defaults here.

Check any model's licence before shipping something on it:

```bash
hf download REPO_ID --include "LICENSE*" --local-dir /tmp/licence-check && ls /tmp/licence-check
```

---

## Where models come from

You have four ways to get a file onto your disk. Learn all four; the venue will decide which one you use.

### 1. The `hf` CLI (best)

```bash
pip install -U huggingface_hub
hf download ggml-org/Qwen3-1.7B-GGUF Qwen3-1.7B-Q4_K_M.gguf --local-dir ~/models
```

Resumable — if the Wi-Fi dies, re-run it and it continues. That alone makes it worth using over a browser.

### 2. Let llama.cpp download it

Skip the file management entirely:

```bash
llama-server -hf ggml-org/Qwen3-1.7B-GGUF:Q4_K_M --port 8080
```

The `:Q4_K_M` suffix selects the quant. llama-swap can do the same thing from its config, so a fresh machine needs no manual downloads at all — see [the llama-swap guide](03-llama-swap.md).

### 3. Plain `curl`

No Python, no tools, works anywhere:

```bash
curl -L -o ~/models/Qwen3-1.7B-Q4_K_M.gguf \
  https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf
```

### 4. Offline — USB stick or the instructor's LAN mirror

A whole class downloading 2 GB at once will saturate any venue Wi-Fi. The instructor will have a mirror running; see [offline-models.md](offline-models.md) for how to point your tools at it, and how to build one yourself.

---

## Verify a download

GGUF files fail confusingly when truncated. Check the magic bytes and the size:

```bash
cd ~/models
head -c 4 Qwen3-1.7B-Q4_K_M.gguf; echo     # must print: GGUF
ls -lh *.gguf
```

If `head -c 4` does not print `GGUF`, the file is corrupt or still downloading — delete and retry.

Then check it actually loads:

```bash
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -c 2048 --port 8080
```

Watch for a line like `load: ... model size = 1234.5 MiB`. If it prints that and then `HTTP server listening`, you are done.

---

**Next:** [01 — What you are actually building](01-concepts.md)

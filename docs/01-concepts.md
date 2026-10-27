# 1 — What you are actually building

Before any commands, the shape of the thing. If you understand this page, every tool in the workshop slots into a box you already have in your head.

---

## Why self-host at all?

You can call an API and get a better model than anything your laptop can run. So why not?

| Reason | What it means in practice |
|--------|---------------------------|
| **Privacy** | Your code, your documents, your medical records never leave the machine. For a lot of work this is not a preference, it is the law. |
| **Cost** | A local model has zero marginal cost per token. An API bill grows forever; a laptop you already own does not. |
| **No rate limits** | Nothing throttles you at 3 a.m. Nothing 429s. Run 10 000 documents through an embedding model and pay nothing. |
| **Availability** | Works on a plane, in a basement, at a venue with broken Wi-Fi. The model is a file. |
| **Control** | You choose the exact weights, the exact quantisation, the context window, the sampling. You can fine-tune. |
| **Understanding** | The real reason for this workshop. Once you have watched a 1.7B model fail at tool calling, you understand what you are buying when you pay for a frontier model — and what you are giving up. |

And the honest counter-argument: **a local small model is much worse than a hosted frontier model.** It will be slower, dumber, and it will confidently make things up. Self-hosting is a trade, not an upgrade. Knowing *when* the trade is worth it is the skill.

---

## The stack

Five layers. Every tool in this workshop lives in exactly one of them.

```
┌───────────────────────────────────────────────────────────────┐
│ 5. CLIENT        Qwen Code · OpenCode · your Python script    │
│                  "do something useful with the model"         │
├───────────────────────────────────────────────────────────────┤
│ 4. GATEWAY       LiteLLM          :4000                       │
│                  one API, many backends, keys, routing,       │
│                  fallback to the cloud when local fails       │
├───────────────────────────────────────────────────────────────┤
│ 3. MANAGER       llama-swap       :8090                       │
│                  "load this model now, unload that one"       │
│                  starts and stops engines on demand           │
├───────────────────────────────────────────────────────────────┤
│ 2. ENGINE        llama.cpp · vLLM                             │
│                  actually does the matrix multiplications     │
│                  serves an OpenAI-compatible HTTP API         │
├───────────────────────────────────────────────────────────────┤
│ 1. WEIGHTS       .gguf files · safetensors · Hugging Face     │
│                  a few GB of numbers on your disk             │
└───────────────────────────────────────────────────────────────┘
```

**You do not need all five.** The minimum working setup is layers 1, 2 and 5: a model file, an engine, and something to talk to it. Layers 3 and 4 are conveniences that pay off once you have more than one model or more than one client.

That is the order this workshop teaches them in, and it is the order you should build in. Adding a layer you do not yet need is how people end up debugging a proxy at 2 a.m. for a model they could have run directly.

---

## Layer 1 — Weights

A model is a file of numbers. That is genuinely all it is: a large tensor of floating-point parameters, plus metadata describing how to arrange them.

**Where they come from:** [Hugging Face](https://huggingface.co) is the de facto registry — think npm or Docker Hub, for models. Also worth knowing: [Ollama's library](https://ollama.com/search), [models.dev](https://models.dev) (a catalogue of *API* models), and vendor sites.

**Two file formats matter:**

- **`safetensors`** — the native format. Full precision, large, needs Python/PyTorch or vLLM to run.
- **`GGUF`** — a single self-contained file designed for llama.cpp. Includes the tokenizer, the chat template and the weights. Usually quantised. **This is what you will use.**

**Quantisation** is compressing those numbers. A model trained at 16 bits per weight can run at 4 bits with modest quality loss — 4× smaller, and on a CPU often *faster*, because you are moving less data. The suffix tells you the level; see [models.md](models.md) for the full table. `Q4_K_M` is the sweet spot for a laptop.

**Naming:** HF repos are `owner/name`. Quantised re-uploads conventionally end in `-GGUF`. So `Qwen/Qwen3-4B` is the original and `ggml-org/Qwen3-4B-GGUF` is the llama.cpp-ready one. Prefer the model author's own GGUF, then `ggml-org` (the llama.cpp team), then `unsloth` or `bartowski` (reliable community quantisers).

> **Licences are not uniform.** "Open weights" ranges from Apache 2.0 to gated agreements requiring registration. Read the licence before shipping anything. Details in [models.md](models.md#licences--read-this-once).

---

## Layer 2 — Engines

The engine loads weights and does inference. Two dominate.

### llama.cpp

C/C++, no dependencies, runs on **anything** — CPU, Apple Metal, NVIDIA, AMD, even a phone. Uses GGUF. This is the engine for your laptop, and it is what the whole workshop is built on.

It ships several binaries:

- **`llama-server`** — an HTTP server with an OpenAI-compatible API. What you want.
- **`llama-cli`** — chat in your terminal. Useful for a quick sanity check.
- **`llama-bench`** — measures your hardware. Run this first and you will know what to expect instead of guessing.

### vLLM

Python, built for **throughput on GPUs**. Its headline feature is PagedAttention — it manages KV cache memory like an OS manages virtual memory, which lets it batch many concurrent requests efficiently. On a GPU it is dramatically faster than llama.cpp under load.

**On a CPU it is not worth your time**, and on a 16 GB laptop with no GPU it is effectively not an option. We cover it in [07-vllm.md](07-vllm.md) so you know what it is and can follow the instructor's demo, but do not plan to run it yourself.

### Which one?

| | llama.cpp | vLLM |
|---|---|---|
| Hardware | CPU, Metal, any GPU | NVIDIA GPU (best), some others |
| Format | GGUF | safetensors |
| Strength | Runs everywhere, one user | Many concurrent users, high throughput |
| Laptop with no GPU | **Yes** | No |

If you are a student in this room: **llama.cpp**.

---

## The thing that makes it all interoperate

Every engine above speaks the **OpenAI-compatible API**. This is the single most important idea in the workshop.

It is a de facto standard: a couple of HTTP endpoints with a known JSON shape.

```bash
curl http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-1.7b",
    "messages": [{"role": "user", "content": "Say hello in one word."}]
  }'
```

Because llama.cpp, vLLM, LiteLLM, llama-swap and Ollama all speak it, **any client works with any server**. Your coding agent does not know or care whether the model behind that URL is a 1.7B file on your laptop or a frontier model in a data centre. Swap the URL, keep the tool.

The endpoints you will actually use:

| Endpoint | Purpose |
|----------|---------|
| `GET /v1/models` | What is available. **Your first debugging tool** — if this fails, nothing else will work. |
| `POST /v1/chat/completions` | Chat, and tool calling. The main one. |
| `POST /v1/embeddings` | Text → vectors, for search and RAG. |
| `POST /v1/rerank` | Re-score search results. |
| `GET /health` | Is it up? |

Memorise this pattern. For the rest of the workshop, whenever something does not work, the first question is always: *can I curl `/v1/models` on it?*

---

## Layer 3 — Model managers

You have one engine slot and several models. Loading a model takes seconds and costs gigabytes of RAM. You do not want four `llama-server` processes competing for 16 GB.

**llama-swap** solves this: it presents one API, and starts/stops engines behind it on demand. Ask for model A and it boots A; ask for model B and it unloads A and boots B. Idle models are killed after a TTL, freeing your RAM.

This is what makes a *specialised* local setup practical — a coder model, a chat model, an embedding model, all on one laptop, only one resident at a time.

See [03-llama-swap.md](03-llama-swap.md).

---

## Layer 4 — Gateways

Now you have several backends: your local llama-swap, maybe a colleague's GPU box, maybe OpenRouter, maybe Google's free tier. Each has a different URL and a different key.

**LiteLLM** puts one endpoint in front of all of them. Clients talk to `:4000` and never learn where the tokens actually came from. You get:

- **Routing** — send `fast-model` local, `big-model` to the cloud.
- **Fallback** — local model died? Retry against the cloud. This is what makes a workshop survivable.
- **Keys and budgets** — issue API keys, cap spend.
- **A uniform API** — over 100 providers behind OpenAI-shaped endpoints.

See [04-litellm.md](04-litellm.md).

---

## Layer 5 — Clients

The point of all this. Two agentic coding CLIs, both pointed at your local stack:

- **Qwen Code** — Alibaba's fork of Gemini CLI. Terminal agent that reads your repo, edits files, runs commands. Has a `qwen serve` mode that turns it into a daemon with a browser UI.
- **OpenCode** — a similar terminal agent, provider-agnostic by design.

Both are configured by giving them a base URL and a model name. Point them at `http://127.0.0.1:4000` and they will use whatever LiteLLM routes to.

See [05-qwen-code.md](05-qwen-code.md) and [06-opencode.md](06-opencode.md).

---

## Concepts you need to be able to reason about

### Tokens

Models do not see characters or words; they see **tokens** — chunks of text, roughly ¾ of an English word. Everything is measured in tokens: context size, price, speed.

```bash
# Rough mental model: 1 token ≈ 4 characters ≈ 0.75 words
echo -n "The quick brown fox" | wc -c   # 19 chars ≈ 5 tokens
```

### Context window

The maximum number of tokens the model can attend to at once — **your prompt plus its reply plus the whole conversation so far**. Exceed it and the start silently falls off the front.

This is the hardest constraint on a laptop. Context is not free: the engine allocates a **KV cache** that grows linearly with context size. A model file is 1.3 GB; at a 128k context the KV cache can be larger than the model.

**Default small.** Start at `-c 4096`, and raise it only when you hit the wall. See the budget table in [models.md](models.md#realistic-budgets-on-a-16-gb-laptop).

### Throughput vs latency

Two different numbers that get conflated:

- **Time to first token (TTFT)** — how long until the first word appears. Dominated by *prefill* (processing your prompt). Feels like responsiveness.
- **Decode speed (tokens/second)** — how fast the rest streams out. Feels like speed.

llama.cpp reports both. Rough expectations on a 16 GB laptop CPU:

| Model | tok/s | Output pace |
|-------|-------|------|
| 135M | 40–80 | Instant |
| 0.6B | 20–40 | Snappy |
| 1.7B | 8–20 | Comfortable to read |
| 4B | 4–10 | Noticeable wait |
| 8B | 2–5 | Painful |

**Batching** is what vLLM is for: serving many requests at once amortises the cost. On a laptop with one user, there is nothing to batch, so llama.cpp's simpler approach wins.

### Temperature and sampling

`temperature` controls randomness. Low (0.0–0.3) is deterministic and best for code and tool calls; high (0.8–1.2) is varied and best for prose. `top_p` and `top_k` truncate the candidate list.

A real trap: **many models have a recommended sampling recipe**, and ignoring it degrades quality noticeably. Qwen3 in particular wants specific settings, and its thinking mode should often be disabled for tool use. Read the model card.

### Reasoning / thinking models

Some models emit a private chain-of-thought before answering. It improves quality on hard problems and costs a *lot* of tokens — a thinking model can burn 4 000 tokens of reasoning to write 200 words of answer.

Two consequences on a laptop: it is slow, and if your `max_tokens` is too small the model spends the entire budget thinking and returns **an empty reply**. That looks like a crash and is not. Either disable thinking (llama.cpp: `--reasoning-budget 0`) or send a large `max_tokens`.

### Tool calling / function calling

The model emits structured JSON saying "call this function with these arguments"; your code runs it and feeds the result back. This is what turns a chatbot into an **agent**, and it is what makes coding CLIs work.

It is also **the first thing that breaks on small models**. Reliable tool calling needs a big model. A 1.7B will fumble the JSON; a 4B is marginal; expect to need 7B+ for dependable agents. llama.cpp requires `--jinja` so it uses the model's own tool-call template.

Plan for this: use the local model to learn, and a cloud model for anything you actually need to work.

### RAG

Retrieval-Augmented Generation: instead of hoping the model knows something, you *look it up* and put it in the prompt.

```
documents → embedding model → vectors → store
query     → embedding model → vector  → nearest neighbours → top-k chunks
top-k chunks + query → chat model → answer
```

Every piece of that runs locally on your laptop, and the embedding models are tiny (0.15 GB). RAG is the highest-value thing you can self-host: it is where a small model plus good retrieval beats a big model guessing.

---

## What good looks like

By the end of the workshop you should have this running and understand every arrow:

```
your coding agent ──→ LiteLLM :4000 ──→ llama-swap :8090 ──→ llama-server ──→ Qwen3-1.7B.gguf
                            │
                            └──fallback──→ a cloud API (when local is not good enough)
```

Build it one layer at a time, and **verify each layer before adding the next**. Every layer has a curl. Use it.

---

## Beyond the laptop: from agent to pipeline

Everything so far ends with *you* driving one agent through one session. A **dev pipeline** is what you get when you stop being the loop: the job is split into phases — spec, plan, exec, verify, review — each run as its own agent session, often with a different model per phase, and each phase's output checked by a gate the model cannot argue with: a test suite, a reviewer model, a diff-size check. Only when the gates pass does a pull request get opened.

The distinction changes what you blame. An agent that fails is a model problem. A pipeline that fails is usually a *gate* problem — a missing check, a budget that ran out, or a serving layer below every harness misparsing tool calls.

Real numbers from one such pipeline, 56 jobs on entirely local models: verification passed on the first attempt for **41%** of jobs, and for **88%** after the fix-and-re-review loop. The gap between those two numbers is the entire value of the pipeline — and the reason "the model said it worked" is never accepted as evidence.

You will not build one today; on your laptop the model is the constraint, not the orchestration. But [Exercise 7](../exercises/README.md#exercise-7--build-the-smallest-possible-pipeline-stretch) builds the smallest version — agent, verify gate, retry budget — in twenty lines of bash.

---

**Next:** [02 — llama.cpp: run a model on your laptop](02-llama-cpp.md)

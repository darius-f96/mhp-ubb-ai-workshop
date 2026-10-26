# MHP · UBB — AI Workshop: Self-Hosted LLMs

Run your own language models on your own laptop. No API keys, no per-token bill, nothing leaving the machine.

By the end of the day you will have a local model served over an OpenAI-compatible API, a gateway that can fall back to the cloud, and a coding agent pointed at the whole thing — and you will understand every layer in between.

```
git clone https://github.com/darius-f96/mhp-ubb-ai-workshop.git
cd mhp-ubb-ai-workshop
```

---

## Before you arrive

**Do the [prerequisites](docs/00-prerequisites.md) at home.** Installing Docker in a room of thirty people is how a two-hour session becomes a four-hour one.

You need:

- [ ] A terminal you are comfortable in — **Windows users: WSL2, not PowerShell**
- [ ] Git
- [ ] Docker, with at least 6 GB allocated to it
- [ ] Node.js ≥ 20
- [ ] VS Code or IntelliJ
- [ ] ~10 GB free disk

Check yourself in one command:

```bash
for t in git docker node npm curl jq; do printf '%-8s ' "$t"; command -v $t >/dev/null && $t --version 2>&1 | head -1 || echo "MISSING"; done
```

**Your hardware baseline for this workshop:** 16 GB RAM, no discrete GPU. Everything here is written for that. If you have a beefier machine, the stretch paths are marked.

---

## The path through the material

Work through these in order. Each one ends with something running that you can curl.

| # | Guide | What you end up with |
|---|-------|----------------------|
| 0 | [Prerequisites](docs/00-prerequisites.md) | A machine that is ready |
| 1 | [What you are actually building](docs/01-concepts.md) | The mental model — read this even if you skip everything else |
| — | [Models: what to download](docs/models.md) | 3.8 GB of weights, chosen for a 16 GB laptop |
| 2 | [llama.cpp](docs/02-llama-cpp.md) | A model serving HTTP on `:8080` |
| 3 | [llama-swap](docs/03-llama-swap.md) | Several models, one port, loaded on demand |
| 4 | [LiteLLM](docs/04-litellm.md) | One gateway on `:4000`, with cloud fallback |
| 5 | [Qwen Code](docs/05-qwen-code.md) | A coding agent using your local model |
| 6 | [OpenCode](docs/06-opencode.md) | A second agent, same backend |

Then, once the core stack works:

| # | Guide | What it covers |
|---|-------|----------------|
| 7 | [vLLM](docs/07-vllm.md) | What production GPU serving looks like *(instructor demo / stretch)* |
| 8 | [qwen serve](docs/08-qwen-serve.md) | Your agent as a daemon with a browser UI |

Supporting material:

- [Offline models](docs/offline-models.md) — when the venue Wi-Fi dies
- [Troubleshooting](docs/troubleshooting.md) — read the error, then read this
- [Exercises](exercises/) — the graded bits, including a dependency-free [local RAG implementation](exercises/rag/rag.py)
- Slides — open in any browser, no server needed: [concepts](slides/concepts.html) (29 slides, the 1h40 lecture) · [qwen serve](slides/qwen-serve.html) (15 slides)

Teaching this? Start with the [facilitator runbook](docs/facilitator-runbook.md) — timings for the 45-minute hands-on, plus the failure modes ranked by how much of your session each one will eat.

---

## The 15-minute version

Cannot wait? This is the whole workshop compressed. It gets you a model answering questions over HTTP.

```bash
# 1. Install llama.cpp (macOS)
brew install llama.cpp

# 1. (Ubuntu / WSL2 — build it instead)
sudo apt install -y build-essential cmake git
git clone https://github.com/ggml-org/llama.cpp && cd llama.cpp
cmake -B build && cmake --build build --config Release -j$(nproc)

# 2. Get a model (1.3 GB)
pip install -U huggingface_hub
hf download ggml-org/Qwen3-1.7B-GGUF Qwen3-1.7B-Q4_K_M.gguf --local-dir ~/models

# 3. Serve it
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -c 8192 --port 8080

# 4. In a SECOND terminal, talk to it
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen","messages":[{"role":"user","content":"Explain quantisation in one sentence."}]}' \
  | jq -r '.choices[0].message.content'
```

If that prints a sentence, you have self-hosted an LLM. Everything else in this repo is about making it *useful*.

---

## What each tool is for

One line each. If you remember nothing else, remember this table.

| Tool | Layer | One-liner |
|------|-------|-----------|
| **Hugging Face** | weights | Where model files live. Think npm for models. |
| **llama.cpp** | engine | Runs GGUF models anywhere, including your CPU. The workhorse. |
| **vLLM** | engine | Runs models fast on GPUs, for many users at once. Not for laptops. |
| **llama-swap** | manager | One port, many models, loaded on demand and unloaded when idle. |
| **LiteLLM** | gateway | One endpoint in front of everything, with routing, keys and cloud fallback. |
| **Qwen Code** | client | Terminal coding agent that edits your repo. |
| **OpenCode** | client | Another terminal coding agent, provider-agnostic. |

---

## Honest expectations

A 1.7B model on a CPU is **not** ChatGPT. It is slower, weaker, and it will confidently invent things.

That is not a failure of the workshop — it is the lesson. You will see precisely where small local models fall over (tool calling, long context, arithmetic), and you will be able to reason about when self-hosting is the right trade and when it is not.

What small local models *are* genuinely good for:

- **Embeddings and retrieval** — tiny models, excellent results, zero cost. The best thing to self-host.
- **Classification and extraction** — "is this spam?", "pull the dates out of this".
- **Summarisation** of short documents.
- **Anything private** — the point is that it never leaves your machine.
- **Learning** — you cannot understand these systems without having run one.

What they are bad at: writing correct code across many files, reliable tool calling, long reasoning chains, and anything needing current facts.

For those, the stack you build here routes to a cloud model. That is a feature, not a cop-out.

---

## Repository layout

```
.
├── README.md              ← you are here
├── docs/                  the playbooks; numbered, work in order
├── configs/               ready-to-use config files
│   ├── llama-swap/        config.yaml for a 16 GB laptop
│   ├── litellm/           config.yaml + docker-compose.yml
│   └── qwen/              settings.json pointing at your local stack
├── scripts/
│   ├── download-models.sh fetch the model set (mirror → hf → curl)
│   ├── serve-mirror.sh    instructor: serve models to the room
│   ├── bootstrap.sh       check your machine is ready
│   └── healthcheck.sh     is every layer of your stack up?
├── exercises/             the graded work
└── slides/                presentation decks (open in a browser)
```

The files in `configs/` are the same ones the guides walk you through writing. Copy them, or type them out — typing them teaches you more.

---

## For facilitators

### Suggested timing

This repo covers the self-hosting block. A full-day shape that has worked:

| Time | Block | Material |
|------|-------|----------|
| 20 min | Mentimeter — gauge the room | — |
| 1 h 40 | Concepts: the five layers, engines, quantisation, context, tool calling | [01-concepts.md](docs/01-concepts.md) + [slides](slides/) |
| 15 min | Break | — |
| 45 min | **Hands-on:** llama.cpp → llama-swap → LiteLLM | docs 02, 04, 05 |
| — | *lunch* | — |
| 2 h | Agents with Google ADK (self-hosted + cloud alternative) | *Traian* |
| 30 min | Skills / MCP / agentic concepts | *Tudor* |
| 1 h | Harnesses + MCP hands-on | *separate material* |

### Before the day

- [ ] Download the full model set on your machine: `./scripts/download-models.sh --all` (~16 GB)
- [ ] Test `./scripts/serve-mirror.sh` and note the IP you will announce
- [ ] Pre-pull the Docker image so the room is not all pulling at once: `docker pull ghcr.io/berriai/litellm:main-stable`
- [ ] Ask the venue about **client isolation** on guest Wi-Fi — it silently breaks the LAN mirror. Get on the same SSID as the students or bring a travel router.
- [ ] Have a cloud API key ready (OpenRouter or Gemini free tier) for the fallback demo, and for students whose laptops cannot cope
- [ ] Bring USB sticks with the `core` model set as a last resort

### During

- [ ] Run `bootstrap.sh` at the start and have students fix what it flags — far cheaper to find problems now than mid-exercise
- [ ] The mirror is the single highest-leverage thing you can do. Announce the address early, put it on a slide, leave it up.
- [ ] Watch for the two failure modes that consume the most time: **Docker memory limits** (model gets OOM-killed, looks like a crash) and **port conflicts** (`:8080` already in use). Both are in [troubleshooting.md](docs/troubleshooting.md).
- [ ] Students with 8 GB of RAM will not keep up. Pair them with someone, or point them at the cloud fallback. Do not let them burn the session on an impossible config.

### The teaching beats that land

- **SmolLM2-135M vs Qwen3-1.7B, same prompt.** Five minutes, and scale stops being abstract.
- **Ask a 1.7B model to call a tool.** It will fumble the JSON. This is why agents need big models, and no amount of explanation substitutes for watching it fail.
- **`llama-bench` on their own machine.** They stop guessing and start knowing.
- **Watch the KV cache line in llama.cpp's startup log** while raising `-c`. Context cost becomes visible.
- **Kill llama-swap mid-request** and show LiteLLM falling back to the cloud. Resilience is a concept until they see it happen.

---

## Licence and credits

Material in this repo is provided for teaching. Model weights are distributed by their authors under their own licences — check each one before reuse. See [models.md](docs/models.md#licences--read-this-once).

Tools covered here are all open source: [llama.cpp](https://github.com/ggml-org/llama.cpp), [llama-swap](https://github.com/mostlygeek/llama-swap), [LiteLLM](https://github.com/BerriAI/litellm), [vLLM](https://github.com/vllm-project/vllm), [Qwen Code](https://github.com/QwenLM/qwen-code), [OpenCode](https://github.com/anomalyco/opencode).

---

**Start here:** [docs/00-prerequisites.md](docs/00-prerequisites.md)

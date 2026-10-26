# Facilitator runbook — the 45-minute hands-on block

Reference for the self-hosting hands-on that follows the concepts lecture. Trainer material, not student material.

**Prerequisites:** students have completed [00-prerequisites.md](../docs/00-prerequisites.md) at home and have attended the concepts block ([slides/concepts.html](../slides/concepts.html)).

**Outcome:** every student has `curl` → LiteLLM → llama-swap → llama.cpp → a model on disk working on their own machine.

---

## Position in the day

The repo covers the self-hosting block only. Full-day schedule:

| Time | Block | Material |
|------|-------|----------|
| 20 min | Mentimeter — gauge the room | — |
| 1 h 40 | Concepts: the five layers, engines, quantisation, context, tool calling | [01-concepts.md](../docs/01-concepts.md) + [slides/concepts.html](../slides/concepts.html) |
| 15 min | Break | — |
| 45 min | **Hands-on:** llama.cpp → llama-swap → LiteLLM | this runbook; docs 02, 03, 04 |
| — | *lunch* | — |
| 2 h | Agents with Google ADK (self-hosted + cloud alternative) | *Traian* |
| 30 min | Skills / MCP / agentic concepts | *Tudor* |
| 1 h | Harnesses + MCP hands-on | *separate material* |

The ADK session that follows depends on a working LiteLLM gateway on every student machine.

---

## Preparation (day before)

### Trainer machine

```bash
./scripts/download-models.sh --all            # full model set, ~14 GB
docker pull ghcr.io/berriai/litellm:v1.106.4  # pinned tag from configs/litellm/docker-compose.yml
./scripts/bootstrap.sh                        # environment check
hostname -I | awk '{print $1}'                # LAN IP for the mirror
```

- The LiteLLM image is pulled in advance so the room does not pull it simultaneously.
- The pinned tag is the one in `configs/litellm/docker-compose.yml`. `main-latest` is currently stale, and the `main-v…-stable` family stopped being published at v1.83.
- A full run of the student path on a clean user account surfaces most breakages before the session.

### Venue network

- **Client isolation on guest Wi-Fi is the highest-risk item.** Many guest networks block device-to-device traffic, which breaks the LAN mirror silently — it shows up as "connection refused" for every student at once. A travel router with its own network avoids the dependency on the venue SSID.
- `./scripts/serve-mirror.sh` can be verified from a second device on the same network.
- With generous venue bandwidth the mirror may be unnecessary, but it costs nothing to have running.
- The mirror address belongs on a slide that stays visible during the download phase.

### Fallbacks

- **Cloud API key** (OpenRouter or Gemini free tier) in `configs/litellm/.env`. Required for the resilience demo; also a fallback for laptops that cannot run local models.
- **USB sticks** with the `core` model set (2.6 GB each). Last resort when the network is unusable.
- **8 GB RAM machines** cannot keep up with the local stack. Identifying them before the session allows pairing or a cloud-fallback path from the start.

---

## Timings

45 minutes total. The timings assume no repetition of material from the concepts block.

| Time | Duration | Trainer | Students |
|------|----------|---------|----------|
| 0:00 | 5 min | Mirror address on screen | `git clone`, `./scripts/bootstrap.sh` |
| 0:05 | 8 min | Bootstrap support | `./scripts/download-models.sh` |
| 0:13 | 10 min | Projector demo, then students follow | `llama-server` + `curl` a completion |
| 0:23 | 5 min | — | `llama-bench` on their own machine |
| 0:28 | 8 min | Eviction demo via `/running` | `llama-swap` up, request two models |
| 0:36 | 7 min | Kill-the-backend demo | LiteLLM up, `healthcheck.sh` |
| 0:43 | 2 min | Exercises handoff | — |

**When behind schedule:** `llama-bench` (5 min) is the cheapest cut and works as an exercise. The LiteLLM fallback demo is the most memorable part of the session and is not a good cut.

**When ahead of schedule:** Exercise 2 (135M vs 1.7B) works better live than as homework.

---

## Step by step

### 0:00 — Clone and check (5 min)

```bash
git clone https://github.com/darius-f96/mhp-ubb-ai-workshop.git
cd mhp-ubb-ai-workshop
./scripts/bootstrap.sh
```

`bootstrap.sh` reports problems before they cost time later. Red items are blockers; yellow items are warnings.

**Common failures:** Docker not running (most frequent), Docker memory ceiling under 6 GB, Node below 22.

Occupied ports are reported as a **warning, not a failure**, by design: once the stack is running, those ports are expected to be busy.

### 0:05 — Download (8 min)

Mirror (trainer machine), started before students download:

```bash
./scripts/serve-mirror.sh
```

Students:

```bash
./scripts/download-models.sh                                    # core set, 2.6 GB
MIRROR=http://TRAINER-IP:8000 ./scripts/download-models.sh      # via the mirror
```

**Common failures:**

- `401 Unauthorized` — gated repo; requires a HF account and an accepted licence. The core set contains ungated models that avoid this.
- Stalled downloads on weak Wi-Fi — the script resumes, so re-running it is the fix. A failed download does not mean starting over.

**This block is the most likely to overrun.** The llama-server demo needs only one model, so the session can continue with the students who are ready while the rest finish downloading.

### 0:13 — Serve and query a model (10 min)

```bash
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf \
  --host 127.0.0.1 --port 8080 -c 8192 -np 1
```

Second terminal:

```bash
curl -s http://127.0.0.1:8080/v1/models | jq
curl -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen","messages":[{"role":"user","content":"Explain quantisation in one sentence."}]}' \
  | jq -r '.choices[0].message.content'
```

At this point the student is self-hosting an LLM; the remaining layers make it useful.

**Startup log:** two numbers are relevant here:

- the **model size** in MiB
- the **KV cache** size

Raising `-c` to 32768 and restarting makes the KV cache grow visibly — this is where context cost becomes concrete.

**`-np 1`:** without it, auto-parallel picks 4 slots. With `-np 4`, the context is split across slots, so a 4096 context silently becomes 1024 per slot.

**Common failures:**

- `Address already in use` — something else is on 8080. A different port works, but it has to change everywhere it is referenced.
- Process exits with no error — out of memory; lower `-c`.

### 0:23 — Benchmark (5 min)

```bash
llama-bench -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -ngl 0
```

The `tg128` value is generation speed in tokens/second. Across a typical room it varies by around 5× (e.g. a 2019 ultrabook vs an M-series MacBook). These numbers answer "which model can I run" for each machine.

On Apple Silicon, running again without `-ngl 0` shows the Metal GPU speed-up.

### 0:28 — Several models, one port (8 min)

Three macros in `configs/llama-swap/config.yaml` need machine-specific values: `model-dir`, `llama-server-path`, and `ngl`. This is the most error-prone part of the session.

llama-swap substitutes its own macros, **not environment variables** — `${HOME}` does not work. The config **hard-fails on an unknown macro**, so a typo fails at startup instead of running a broken command.

```bash
llama-swap --config configs/llama-swap/config.yaml --listen 127.0.0.1:8090
```

llama-swap runs in the **foreground**: when a model fails to start, the reason appears in this log.

```bash
curl -s http://127.0.0.1:8090/v1/models | jq -r '.data[].id'   # lists every configured model
curl -s http://127.0.0.1:8090/running | jq                     # nothing loaded yet
```

**Listing is not proof of health** — `/v1/models` starts nothing.

Eviction sequence:

1. Request `coder` — cold start, slow.
2. Request `coder` again — warm, fast.
3. Request `chat`, then query `/running` — `coder` has been evicted.

The eviction is what turns "one model" into "a local model service."

**Common failure:** `upstream command exited prematurely` — the #1 llama-swap failure, with an unhelpful message. Diagnosis: take the `cmd` for that model from the config, replace `${PORT}` with a real number, and run it by hand. The real error then appears.

### 0:36 — Gateway and failover (7 min)

```bash
cd configs/litellm
cp .env.example .env
nano .env                    # set LITELLM_MASTER_KEY; cloud key optional
docker compose up -d
cd ../..
set -a; . configs/litellm/.env; set +a     # load the key into the student's shell
./scripts/healthcheck.sh
```

**The `set -a` line is essential and belongs on the slide.** `env_file:` feeds the *container* only; the student's terminal never sees those variables. Every curl in this block and in Exercise 5 sends `$LITELLM_API_KEY`. If it is unset, a healthy gateway returns `401`, `healthcheck.sh` reports the gateway as broken, and LiteLLM appears to be down.

**Failover demo:** stop llama-swap (`Ctrl-C` in its terminal), then:

```bash
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model":"resilient","messages":[{"role":"user","content":"Say OK"}]}' | jq
```

The request still succeeds, served by the cloud backend. After restarting llama-swap, traffic returns to the local model. Client code does not change at any point — that is the purpose of the gateway.

**Common failures:**

- **Container networking** — routes list fine but every completion fails. Cause: missing `extra_hosts: host-gateway`, or `api_base` pointing at `127.0.0.1` instead of `host.docker.internal`. The provided compose file already handles this, so it usually indicates a hand-written one. Diagnosis:

  ```bash
  docker exec litellm getent hosts host.docker.internal
  ```

  No IP printed → the `extra_hosts` line is missing or the container was not recreated.

- **`401` on every request** — `LITELLM_API_KEY` not exported in the shell, or not matching `.env`.
- **`.env` edits not taking effect** — env files are read at container *creation*; `docker compose up -d --force-recreate` is required, not `restart`.

### 0:43 — Exercises (2 min)

Exercises are in `exercises/README.md`: six in total, ending with `answers.md` pushed on a branch (which doubles as a Git exercise).

Highest-value two: **Exercise 2** (135M vs 1.7B) and **Exercise 6** (agent, local vs cloud).

---

## Failure modes, ranked by time cost

Ordered by observed impact, not by likelihood.

| # | Failure | Why it is expensive | Diagnosis / fix |
|---|---------|--------------------|-----------------|
| 1 | **Docker memory ceiling** | Model gets OOM-killed with no error; looks like a crash and leads to reinstalls | `docker info --format '{{.MemTotal}}'`; raise in Settings → Resources |
| 2 | **`host.docker.internal` unresolved** | Routes list fine, every completion fails; LiteLLM looks broken | `docker exec litellm getent hosts host.docker.internal` |
| 3 | **`upstream command exited prematurely`** | Message gives no cause | Run the model's `cmd` by hand with a real port |
| 4 | **Port conflicts** | Vague bind errors | `ss -ltnp \| grep :8080`; change the port *everywhere* |
| 5 | **Gated model → 401** | Needs a HF account and licence acceptance mid-session | Use the ungated core set |
| 6 | **Venue Wi-Fi collapse** | Everyone downloads at once | LAN mirror, address on a slide from the start |
| 7 | **Thinking model → empty reply** | Looks exactly like a crash | Check `reasoning_content`; raise `max_tokens` or use `--reasoning-budget 0` |
| 8 | **Macro typos in llama-swap config** | Hard failure, unfamiliar message | The error names the model and the field |
| 9 | **Client isolation on guest Wi-Fi** | Mirror unreachable, no obvious cause | Travel router, or USB fallback |
| 10 | **Tool calling on a 1.7B** | Not a bug, but looks like a broken setup | Expected behaviour — covered by Exercise 2 |

---

## High-impact demonstrations

Worth protecting even when other parts are cut.

- **SmolLM2-135M vs Qwen3-1.7B, same prompt.** Five minutes; makes model scale concrete. With a JSON-only output request, the 135M does not comply.
- **Killing llama-swap while LiteLLM fails over.** Resilience shown by deliberately breaking a component.
- **`llama-bench` numbers from the room on the whiteboard.** Replaces guessing with measured numbers; the spread across machines is the lesson.
- **Raising `-c` live and reading the KV cache line.** Makes context cost visible.
- **`-np 4` silently dropping context to 1024.** A trap students otherwise hit alone later.
- **`/v1/models` listing a model that then fails to load.** Listing is not health — a debugging habit that generalises.

---

## Diagnosing student machines

Three checks give a clearer picture than asking how it is going:

```bash
./scripts/bootstrap.sh                 # machine readiness
./scripts/healthcheck.sh               # which layer is broken
curl -s http://127.0.0.1:8090/running  # which models are actually loaded
```

`healthcheck.sh` reports the **lowest** broken layer, which is the one to fix — layers above it are usually fine. Students can run it themselves; it resolves most problems without trainer involvement.

**8 GB RAM machines:** pairing with another student, or using the cloud fallback for the concept-focused exercises, avoids spending the session on a configuration that cannot work.

---

## Post-session maintenance

- Failure modes encountered during the session belong in [troubleshooting.md](../docs/troubleshooting.md).
- 45 minutes is optimistic. A block that overruns consistently needs restructuring, not faster delivery.
- Versions were last verified on **2026-10-26**. llama-swap ships weekly and LiteLLM image tags move, so versions need re-checking before each cohort.

---

**Related:** [troubleshooting.md](../docs/troubleshooting.md) is the student-facing troubleshooting guide · the student entry point is [README.md](../README.md)

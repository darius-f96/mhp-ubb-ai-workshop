# Facilitator runbook — the 45-minute hands-on block

This covers the self-hosting hands-on that follows the concepts lecture. It is written for the person at the front of the room, not for students.

**Assumes:** students have completed [00-prerequisites.md](00-prerequisites.md) at home, and have just sat through the concepts block ([slides/concepts.html](../slides/concepts.html)).

**Goal:** every student leaves with `curl` → LiteLLM → llama-swap → llama.cpp → a model on disk, working and understood. Not "seen a demo" — *working on their own machine*.

---

## Before the day

Do all of this the day before, on the venue network if you can get access. Nothing here is optional.

### Your machine

- [ ] `./scripts/download-models.sh --all` — the full set, ~16 GB. Takes a while; start it early.
- [ ] `docker pull ghcr.io/berriai/litellm:main-v1.66.0-stable` — so the room is not all pulling at once
- [ ] Walk the entire student path yourself, on a clean user account if possible. You will find the thing that breaks.
- [ ] `./scripts/bootstrap.sh` — fix everything it flags
- [ ] Note your LAN IP for the mirror: `hostname -I | awk '{print $1}'`

### The room

- [ ] **Ask the venue about client isolation on guest Wi-Fi.** This is the single highest-risk item on this list. Many guest networks block device-to-device traffic, which silently breaks the LAN mirror — and you will discover it only when 25 students report "connection refused" simultaneously. If you cannot get on the same SSID as the students, **bring a travel router** and create your own network.
- [ ] Test `./scripts/serve-mirror.sh` from a second device on that network
- [ ] Confirm the venue's actual bandwidth. If it is generous, you may not need the mirror — but have it ready anyway.
- [ ] Put the mirror address **on a slide** and leave it up. Students will not remember it.

### Fallbacks

- [ ] A cloud API key (OpenRouter or Gemini free tier) in `configs/litellm/.env`. Needed for the resilience demo, and as a lifeboat for students whose laptops cannot cope.
- [ ] USB sticks with the `core` model set (3.8 GB each). Last resort when the network is unusable.
- [ ] Know which students have 8 GB of RAM **before** the session starts. They will not keep up, and finding out at minute 30 wastes their afternoon.

---

## Timings

Total 45 minutes. It is tight; the timings assume you do not explain things the concepts block already covered.

| Time | Block | You do | They do |
|------|-------|--------|---------|
| 0:00 | **0 min** | — | *(arrive with prerequisites done)* |
| 0:00 | **5 min** | Announce the mirror address. Put it on a slide. | `git clone`, `./scripts/bootstrap.sh` |
| 0:05 | **8 min** | Circulate. Fix bootstrap failures. | `./scripts/download-models.sh` |
| 0:13 | **10 min** | Demo on the projector first, then let them follow | `llama-server` + `curl` a completion |
| 0:23 | **5 min** | — | `llama-bench` — **their own numbers** |
| 0:28 | **8 min** | Demo the eviction, make them watch `/running` | `llama-swap` up, request two models |
| 0:36 | **7 min** | The kill-the-backend demo is the highlight — do it loudly | LiteLLM up, `healthcheck.sh` |
| 0:43 | **2 min** | Point at exercises | — |

**If you are running behind:** cut `llama-bench` (5 min) and move it to an exercise. Do **not** cut the LiteLLM fallback demo — it is the single most memorable thing in the session.

**If you are ahead:** let them do Exercise 2 (135M vs 1.7B) in the room. It lands better live than as homework.

---

## Minute-by-minute detail

### 0:00 — Clone and check (5 min)

```bash
git clone https://github.com/darius-f96/mhp-ubb-ai-workshop.git
cd mhp-ubb-ai-workshop
./scripts/bootstrap.sh
```

Say: *"This tells you what is broken before it costs you twenty minutes. Fix the red items now, ask me about the yellow ones."*

**Watch for:** Docker not running (the most common red), Docker memory ceiling under 6 GB, and Node below 22.

Note that bootstrap reports **occupied ports as a warning, not a failure** — deliberately, because once their stack is running those ports *should* be busy. If a student reads that as an error, it is a good teaching moment about what the check is actually for.

### 0:05 — Download (8 min)

```bash
./scripts/download-models.sh                                    # core set, 3.8 GB
MIRROR=http://YOUR-IP:8000 ./scripts/download-models.sh         # if using the mirror
```

Start your mirror **before** you ask them to download:

```bash
./scripts/serve-mirror.sh
```

**Watch for:** `401 Unauthorized` (gated repo — they need a HF account and to accept a licence; steer them to the ungated models in the core set), and downloads stalling on weak Wi-Fi. The script resumes, so "run it again" is usually the whole fix — say that out loud, because students assume a failed download means starting over.

**This is the block most likely to overrun.** If more than a few students are still downloading at 0:13, move on and let the rest catch up — the llama-server demo works on one model, and you can start it with whoever is ready.

### 0:13 — Serve and talk to it (10 min)

Projector first, then they follow:

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

**Pause here.** Say: *"That is it. You are self-hosting an LLM. Everything else today is making it useful."*

Then point at the startup log and make them find two numbers:

- the **model size** in MiB
- the **KV cache** size

Ask someone to read theirs out. Then ask the room what happens if they raise `-c` to 32768 — let them predict, then have someone actually do it. This is where the context-cost concept stops being abstract.

**Mention `-np 1` explicitly** and why: auto-parallel picks 4 slots and, if they set `-np 4` themselves, their 4096 context silently becomes 1024. Students who read ahead will hit this.

**Watch for:** `Address already in use` (something on 8080 — change the port, and remind them to change it *everywhere*), and processes vanishing with no error (out of memory — lower `-c`).

### 0:23 — Measure their own machine (5 min)

```bash
llama-bench -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -ngl 0
```

Have three or four students call out their `tg128` number. Write them on the whiteboard. The spread across the room is itself the lesson — a 2019 ultrabook and an M-series MacBook differ by 5×.

Say: *"Now you know what to expect instead of guessing. Every 'which model should I use' question is answered by these two numbers."*

Apple Silicon users should re-run without `-ngl 0` and compare. That gap is Metal.

### 0:28 — Several models, one port (8 min)

**Before this block, have them edit three macros** in `configs/llama-swap/config.yaml`: `model-dir`, `llama-server-path`, and `ngl`. Do it on the projector. This is the most error-prone two minutes of the session — the config **hard-fails on an unknown macro**, and students will try `${HOME}` because it looks reasonable.

Say explicitly: *"llama-swap substitutes its own macros, not environment variables. `${HOME}` will not work. That is deliberate — a typo fails loudly at startup instead of running a broken command."*

```bash
llama-swap --config configs/llama-swap/config.yaml --listen 127.0.0.1:8090
```

**Foreground, always.** When a model fails to start, the reason is in this log. Daemonising now means debugging blind.

Then make them watch the eviction:

```bash
curl -s http://127.0.0.1:8090/v1/models | jq -r '.data[].id'   # lists everything
curl -s http://127.0.0.1:8090/running | jq                     # nothing loaded yet
```

Point out that **listing is not proof of health** — `/v1/models` starts nothing.

Request `coder`, time it (cold). Request `coder` again, time it (warm). Then request `chat` and immediately check `/running` — the coder is gone.

Say: *"That eviction is the entire point. It is the difference between 'I can run one model' and 'I have a local model service.'"*

**Watch for:** `upstream command exited prematurely`. This is the #1 llama-swap failure and the message is deliberately unhelpful. Teach the fix once, loudly: **take the `cmd` from the config, replace `${PORT}` with a real number, and run it by hand.** Then you get a real error.

### 0:36 — The gateway, and the demo that lands (7 min)

```bash
cd configs/litellm
cp .env.example .env
nano .env                    # set LITELLM_MASTER_KEY; cloud key optional
docker compose up -d
cd ../..
./scripts/healthcheck.sh
```

**The demo:** kill llama-swap (`Ctrl-C` in its terminal), then:

```bash
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model":"resilient","messages":[{"role":"user","content":"Say OK"}]}' | jq
```

It still answers — from the cloud. Restart llama-swap and show it coming back.

Say: *"Your client code did not change. Not one line. That is the whole point of the gateway — and that is why a demo that dies when a service restarts is a bad demo."*

**Watch for:** the container-networking failure — routes list fine but every completion fails. It is almost always a missing `extra_hosts: host-gateway`, or `api_base` pointing at `127.0.0.1` instead of `host.docker.internal`. The fix is in the provided compose file, so this usually means they wrote their own. Diagnose it with:

```bash
docker exec litellm getent hosts host.docker.internal
```

No IP printed → the `extra_hosts` line is missing or the container was not recreated.

Also: `401` on every request means they did not export `LITELLM_API_KEY` to match `.env`. And editing `.env` needs `docker compose up -d --force-recreate`, not `restart` — env files are read at container *creation*.

### 0:43 — Hand off (2 min)

Point at `exercises/README.md`. Six exercises, and they push `answers.md` on a branch at the end — which doubles as a Git exercise.

Name the two that matter most if they only do two: **Exercise 2** (135M vs 1.7B) and **Exercise 6** (agent, local vs cloud).

---

## Failure modes, ranked by how much time they will cost you

These are ordered by observed pain, not by likelihood.

| # | Failure | Why it is expensive | Your move |
|---|---------|--------------------|-----------|
| 1 | **Docker memory ceiling** | Model gets OOM-killed. Looks like a crash, produces no error, and students reinstall things | `docker info --format '{{.MemTotal}}'`; raise it in Settings → Resources |
| 2 | **`host.docker.internal` unresolved** | Routes list fine, every completion fails. Students conclude LiteLLM is broken | `docker exec litellm getent hosts host.docker.internal` |
| 3 | **`upstream command exited prematurely`** | The message says nothing. Students flail | Have them run the `cmd` by hand with a real port |
| 4 | **Port conflicts** | Vague bind errors | `ss -ltnp \| grep :8080`; change it *everywhere* |
| 5 | **Gated model → 401** | Needs a HF account and a licence click, mid-session | Steer them to the ungated core set |
| 6 | **Venue Wi-Fi collapse** | Everyone downloads at once | Mirror. Announce it early, keep it on a slide |
| 7 | **Thinking model → empty reply** | Looks exactly like a crash | Check `reasoning_content`; raise `max_tokens` or `--reasoning-budget 0` |
| 8 | **Macro typos in llama-swap config** | Hard failure, unfamiliar message | The error names the model and field — read it to them once |
| 9 | **Client isolation on guest Wi-Fi** | Mirror unreachable, no obvious cause | Travel router, or fall back to USB |
| 10 | **Tool calling on a 1.7B** | Not a bug; students think their setup is wrong | Pre-empt it: *"this is supposed to fail — that is Exercise 2"* |

---

## Teaching beats that reliably land

Worth protecting time for, even if you cut something else.

- **SmolLM2-135M vs Qwen3-1.7B, same prompt.** Five minutes, and model scale stops being abstract. Ask for JSON-only output; the 135M will not comply.
- **Kill llama-swap and show LiteLLM failing over.** Resilience is a concept until they watch it happen because you broke it on purpose.
- **`llama-bench` on their own machine, numbers on the whiteboard.** They stop guessing and start knowing. The spread across the room does the teaching for you.
- **Raise `-c` live and read the KV cache line.** Context cost becomes visible in a way no diagram achieves.
- **Have someone set `-np 4` and watch their context silently drop to 1024.** A trap they will otherwise hit alone, at home, confused.
- **Show `/v1/models` listing a model that then fails to load.** Listing is not health. This habit generalises to every system they will ever debug.

---

## Deciding who needs help

Circulate with these three checks rather than asking "how's it going?" — students always say fine.

```bash
./scripts/bootstrap.sh                 # is their machine ready?
./scripts/healthcheck.sh               # which layer is broken?
curl -s http://127.0.0.1:8090/running  # is anything actually loaded?
```

`healthcheck.sh` reports the **lowest** broken layer, which is the one to fix — everything above it is usually fine. Teach students to run it themselves before raising a hand; it resolves most of their own problems and frees you for the ones that matter.

**Pair up students with 8 GB of RAM** rather than letting them struggle. Or point them at the cloud fallback and have them do the exercises that are about concepts rather than horsepower. Do not let anyone spend the session on an impossible configuration.

---

## Afterwards

- [ ] Collect the failure modes you actually hit and add them to [troubleshooting.md](troubleshooting.md). The next run should be easier than this one.
- [ ] Note which timings were wrong. 45 minutes is optimistic; if you consistently overrun at a particular block, that block needs restructuring, not more hurrying.
- [ ] Re-verify versions before the next cohort. Everything here was checked on **2026-10-26**; llama-swap ships releases weekly and LiteLLM's image tags move.

---

**Related:** [README.md](../README.md#for-facilitators) has the full-day shape and the pre-day checklist · [troubleshooting.md](troubleshooting.md) is what you send students to

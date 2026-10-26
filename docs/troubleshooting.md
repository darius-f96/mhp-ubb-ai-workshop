# Troubleshooting

Read the error before you read this page. The last three lines of output usually say what is wrong, and most of the time the fix is one of: Docker is not running, you are in the wrong directory, a port is taken, or you ran out of memory.

**The universal first step** — work bottom-up, one layer at a time:

```bash
./scripts/healthcheck.sh
```

It tells you the *lowest* layer that is broken. Fix that one; everything above it is usually fine.

---

## Quick index

| Symptom | Jump to |
|---------|---------|
| `Connection refused` on `:4000` | [Docker](#docker) |
| LiteLLM returns `401 Unauthorized` | [Authentication](#authentication) |
| LiteLLM cannot reach the local model | [Container networking](#container-networking) |
| `upstream command exited prematurely` | [llama-swap](#llama-swap) |
| Model killed / `signal: killed` / silent restart | [Out of memory](#out-of-memory) |
| `Address already in use` | [Ports](#ports) |
| `401` downloading from Hugging Face | [Model downloads](#model-downloads) |
| Reply is empty but the request "succeeded" | [Thinking models](#thinking-models) |
| Gibberish, repetition, ignores instructions | [Chat templates](#chat-templates) |
| Agent cannot call tools | [Tool calling](#tool-calling) |
| Everything is slow | [Performance](#performance) |

---

## Docker

**`Cannot connect to the Docker daemon`**

Docker is not running.

```bash
# macOS: launch Docker Desktop, or if you use Colima:
colima start
# Linux:
sudo systemctl start docker
# WSL2: start Docker Desktop from Windows, it serves WSL
```

**`permission denied` on the docker socket (Linux)**

You are not in the `docker` group.

```bash
sudo usermod -aG docker $USER
```

Then **log out and back in**. This does not take effect in the current shell, and `newgrp docker` is a partial workaround at best.

**`docker compose` not found**

Old Docker. Either update it, or use the legacy hyphenated form `docker-compose up -d`. The compose file in this repo works with both.

**Container starts then immediately exits**

```bash
docker logs litellm --tail 50
```

Read it. Nine times out of ten it is a YAML syntax error in `config.yaml` — usually indentation, or a tab character where spaces belong. YAML forbids tabs entirely.

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('configs/litellm/config.yaml')); print('YAML OK')"
```

---

## Authentication

**LiteLLM returns `401 Unauthorized`**

Every request needs the master key. Verified behaviour: an unauthenticated `GET /v1/models` returns exactly `HTTP 401`.

```bash
export LITELLM_API_KEY=sk-workshop-change-me    # must match .env
curl -s http://127.0.0.1:4000/v1/models -H "Authorization: Bearer $LITELLM_API_KEY" | jq
```

Common causes, in order:

1. You did not send the header at all.
2. The key does not match `LITELLM_MASTER_KEY` in `.env`.
3. You edited `.env` but did not recreate the container — `docker compose up -d` again. Env files are read at container start, not per request.

**llama.cpp and llama-swap return `401`**

Only if you passed `--api-key`. On localhost, do not. If you did, send it:

```bash
curl -s http://127.0.0.1:8090/v1/models -H "Authorization: Bearer YOURKEY"
```

Note that LiteLLM's `api_key: dummy` for local routes is **correct and intentional** — the client must send *something*, and a keyless local server ignores it.

---

## Container networking

The most common LiteLLM failure in this workshop. LiteLLM runs in a container; your model runs on the host.

**Symptom:** `Connection refused`, `Connection error`, or the proxy lists models but every completion fails.

**Cause:** inside a container, `127.0.0.1` means *the container itself*, not your laptop. If `api_base` says `http://127.0.0.1:8090/v1`, LiteLLM is looking for llama-swap inside its own container, where it does not exist.

**Fix — two parts, you need both:**

1. In `config.yaml`, use the host alias, not loopback:

```yaml
api_base: http://host.docker.internal:8090/v1
```

2. In `docker-compose.yml`, make that name resolve. Docker Desktop does this automatically; **Linux and WSL2 do not**:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

**Verify the name actually resolves from inside the container:**

```bash
docker exec litellm getent hosts host.docker.internal
```

Print an IP and you are fine. Print nothing and the `extra_hosts` line is missing or the container was not recreated.

**Then verify the container can reach the host service:**

```bash
docker exec litellm sh -c "python3 -c \"import urllib.request;print(urllib.request.urlopen('http://host.docker.internal:8090/v1/models',timeout=5).read()[:200])\""
```

**If that works but the host cannot:**

```bash
curl -s http://127.0.0.1:8090/v1/models | jq
```

If this fails, the problem is llama-swap, not LiteLLM. Fix the lower layer first.

**WSL2 extra wrinkle:** if llama.cpp listens only on `127.0.0.1` inside WSL and Docker Desktop is on Windows, the container may not reach it. Bind the engine to `0.0.0.0` (`--host 0.0.0.0`) — and understand that this exposes it to your local network, so only do it on a trusted network.

---

## llama-swap

**`{"src":"llama-swap","error":"unspecific error: upstream command exited prematurely"}`**

This exact error means: llama-swap tried to start the engine and **the engine died**. llama-swap is fine; the `cmd` in its config is not.

Almost always one of:

- The binary path in `cmd` is wrong → `command not found`
- The model path is wrong → engine exits immediately
- The engine ran out of memory → killed
- A flag the engine does not understand → exits with usage error

**Diagnose it properly:** run the `cmd` from the config by hand, in your terminal, with `${PORT}` replaced by a real number.

```bash
# whatever your config says, run it directly and READ the output
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf --host 127.0.0.1 --port 18080 -c 8192
```

If it fails standalone, it will fail under llama-swap. Fix it standalone — you get a real error message instead of a one-line "exited prematurely".

**Also check llama-swap's own log stream:**

```bash
curl -s http://127.0.0.1:8090/logs | tail -40
```

Or run it in the foreground, which is what you should do during the workshop anyway:

```bash
llama-swap --config configs/llama-swap/config.yaml
```

**Model listed in `/v1/models` but requests fail**

Normal. `/v1/models` lists what llama-swap *could* run — it does not start anything. Listing is not proof of health. Check what is actually resident:

```bash
curl -s http://127.0.0.1:8090/running | jq
```

**Config changes not taking effect**

Restart llama-swap. But note that **restarting evicts every loaded model**, so the next request pays a cold load. During an exercise that is fine; do not do it to a shared demo mid-request.

---

## Out of memory

The most common cause of "it just stopped working" on a 16 GB laptop.

**Symptoms:**

- Process disappears with no error, or `signal: killed`
- llama-swap says `upstream command exited prematurely`
- The machine becomes unresponsive, then the model is gone
- `dmesg` mentions the OOM killer

**Confirm it:**

```bash
# Linux / WSL2 — look for the OOM killer
dmesg 2>/dev/null | grep -i -E 'killed process|out of memory' | tail -5
# macOS
log show --predicate 'eventMessage contains "memory"' --last 10m 2>/dev/null | tail -20
# what is eating RAM right now
free -h          # Linux
top -o mem       # macOS
```

**Fixes, most effective first:**

1. **Lower the context.** This is usually the whole problem. `-c 32768` → `-c 8192` can free gigabytes. See [models.md](models.md#realistic-budgets-on-a-16-gb-laptop).
2. **Quantise the KV cache:** `--flash-attn on --cache-type-k q8_0 --cache-type-v q8_0`
3. **Use a smaller model.** 4B → 1.7B → 0.6B.
4. **Close things.** A browser with 30 tabs is 4 GB you are not using for inference.
5. **One model at a time.** This is exactly what llama-swap is for.
6. **Docker's ceiling.** In Docker Desktop, the VM has its own memory cap independent of your laptop. Settings → Resources → Memory, or `colima start --memory 8`. Check what you actually have:

```bash
docker info --format '{{.MemTotal}}' | awk '{printf "%.1f GB\n", $1/1024/1024/1024}'
```

**WSL2 specifically:** it defaults to half your RAM. Create `C:\Users\YOURNAME\.wslconfig`:

```ini
[wsl2]
memory=12GB
swap=8GB
```

Then `wsl --shutdown` from PowerShell and reopen.

---

## Ports

**`Address already in use` / `bind: address already in use`**

Find what owns it:

```bash
ss -ltnp | grep :8080          # Linux / WSL2
lsof -iTCP:8080 -sTCP:LISTEN   # macOS
```

Either stop that process, or use a different port. Nothing in this workshop requires a specific port — if you change one, change it in *every* config: the engine's `--port`, llama-swap's `proxy`, and LiteLLM's `api_base`.

Note that a port being occupied is **expected** once your stack is running. `bootstrap.sh` reports it as a warning, not a failure, for exactly that reason.

---

## Model downloads

**`401 Unauthorized` from Hugging Face**

The repo is **gated** — Llama and Mistral models require you to accept a licence. Log in to huggingface.co, open the model page, click through the agreement, then:

```bash
hf auth login
```

Prefer ungated models in a workshop. See [models.md](models.md#licences--read-this-once).

**`404 Not Found` on a file that "exists"**

Filenames are case-sensitive and conventions differ per repo. `ggml-org/` uses `Qwen3-1.7B-Q4_K_M.gguf`; `Qwen/` uses lowercase `qwen2.5-coder-1.5b-instruct-q4_k_m.gguf`. Copy filenames exactly from [models.md](models.md), do not retype them.

**File downloaded but the engine rejects it**

Truncated download. Check the magic bytes:

```bash
head -c 4 ~/models/YOURMODEL.gguf; echo    # must print: GGUF
```

Delete and re-download. `hf download` and `curl -C -` both resume, so re-running is cheap.

**Everything is slow to download at the venue**

That is the mirror's job. See [offline-models.md](offline-models.md).

---

## Thinking models

**The request succeeds but `content` is empty**

Not a bug. A reasoning model spent its entire token budget on private chain-of-thought and had nothing left for the answer.

Two fixes:

```bash
# give it room
-d '{"max_tokens": 4096, ...}'

# or turn thinking off (llama.cpp)
llama-server ... --reasoning-budget 0
```

Check where the tokens went:

```bash
curl -s ... | jq '.choices[0].message.reasoning_content | length'
```

If that is large and `content` is empty, this is your problem.

---

## Chat templates

**Gibberish, endless repetition, or the model ignores your instructions**

Usually the wrong chat template. A model trained with ChatML that gets fed Llama-format prompts produces exactly this.

Fix: let the model supply its own template.

```bash
llama-server -m MODEL.gguf --jinja
```

`--jinja` reads the template embedded in the GGUF instead of using a guessed default. **You generally want this always on**, and it is required for tool calling.

Check what template a GGUF carries:

```bash
llama-server -m MODEL.gguf --port 8080 2>&1 | grep -i -A3 'chat template'
```

---

## Tool calling

**The agent cannot use tools, or emits malformed JSON**

Three causes, check in this order:

1. **Missing `--jinja`.** Without it the model never sees a tool schema in the format it was trained on. This is the usual answer.
2. **The model is too small.** This is not a config problem. Reliable tool calling needs roughly 7B+. A 1.7B model will fumble the JSON intermittently and a 135M model will not produce it at all. Exercise 2 exists to show you this. Use a cloud model for real agentic work.
3. **The client is not sending tools.** Verify the engine accepts them independently of your client:

```bash
curl -s http://127.0.0.1:8080/v1/chat/completions -H "Content-Type: application/json" -d '{
  "model":"m",
  "messages":[{"role":"user","content":"What is 12 * 12? Use the calculator."}],
  "tools":[{"type":"function","function":{"name":"calculator","description":"evaluate a math expression","parameters":{"type":"object","properties":{"expression":{"type":"string"}},"required":["expression"]}}}]
}' | jq '.choices[0].message.tool_calls'
```

`null` means the model did not call the tool. A populated array means the engine is fine and the problem is in your client.

---

## Performance

**Slower than you expected**

Measure before you optimise:

```bash
llama-bench -m ~/models/YOURMODEL.gguf -ngl 0 -p 512 -n 128
```

Then:

- **Apple Silicon:** are you offloading layers? Drop `-ngl 0` and let Metal work. `-ngl 999` means "all of them".
- **CPU threads:** `-t $(nproc)` helps up to your physical core count, then hurts. Do not set it above physical cores — hyperthread siblings contend.
- **Context:** a huge `-c` slows prefill even when the conversation is short.
- **Quantisation:** Q4_K_M is usually *faster* than Q8_0 on CPU, because it moves less data. Bigger is not always slower.
- **Expectations:** see the tok/s table in [01-concepts.md](01-concepts.md#throughput-vs-latency). A 4B model at 5 tok/s on CPU is normal, not broken.

**First request is very slow, later ones are fast**

Normal. That is a cold load: starting the engine and reading the model into memory. llama-swap pays it once per model per TTL window. LiteLLM's `timeout` must be long enough to survive it, which is why the workshop config sets `timeout: 600`.

---

## Nuclear options

When something is in a state you cannot explain, reset it deliberately rather than thrashing.

```bash
# stop the gateway
cd configs/litellm && docker compose down && cd ../..

# stop everything listening on the workshop ports (CAREFUL: check what it lists first)
for p in 8080 8090 4000; do ss -ltnp 2>/dev/null | grep ":$p " || true; done

# verify nothing is left
./scripts/bootstrap.sh

# rebuild from a clean slate
docker compose -f configs/litellm/docker-compose.yml up -d --force-recreate
./scripts/healthcheck.sh
```

Do **not** delete your model files to "start over" — re-downloading gigabytes fixes nothing that a restart would.

---

## Still stuck?

Give an instructor these four things and you will get help immediately:

1. Which layer: `./scripts/healthcheck.sh` output
2. The exact command you ran
3. The **full** error, not a paraphrase — the last 20 lines
4. Your OS, RAM, and whether Docker is running

```bash
./scripts/healthcheck.sh > /tmp/health.txt 2>&1
uname -srmo; free -h | head -2; docker info --format '{{.ServerVersion}}'
```

Being precise about a failure is a skill worth more than any single tool in this workshop.

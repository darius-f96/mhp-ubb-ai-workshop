# 4 — LiteLLM: one gateway, local and cloud

You now have models behind llama-swap. Soon you will also have a cloud API key, because a 1.7B model cannot do everything. Your clients should not have to know which is which.

**LiteLLM** puts one endpoint in front of all of it. Clients talk to `:4000` and never learn where the tokens came from.

By the end of this page you will have a gateway that serves your local models, can fall back to the cloud when they are down, and requires no change in client code to do it.

---

## What it buys you

| Capability | Why you care |
|------------|--------------|
| **One API** | 100+ providers behind OpenAI-shaped endpoints. Swap a backend without touching a client |
| **Routing** | `local-chat` → your laptop, `cloud-fast` → OpenRouter. Pick per request |
| **Fallback** | Local model died? Retry on the cloud automatically. This is what makes a demo survivable |
| **Renaming** | Change the model underneath without any client noticing |
| **Keys and budgets** | Issue API keys, cap spend (needs a database — not for this workshop) |
| **Observability** | One place to see every request |

It is an **AI gateway**, not an inference engine. It does no matrix multiplication; it forwards.

---

## Install

### Docker (recommended — this is what the workshop uses)

The config lives in [`configs/litellm/`](../configs/litellm/):

```bash
cd configs/litellm
cp .env.example .env
$EDITOR .env                 # set LITELLM_MASTER_KEY; cloud keys are optional
docker compose up -d
docker compose logs -f       # Ctrl-C to stop following; the container keeps running
```

> **The master key must start with `sk-`.** The docs state this as a requirement. Every key in this repo's examples does (`sk-workshop-change-me`) — keep that prefix if you change the value, or a newer LiteLLM may reject the key at startup rather than at request time.

The compose file pins `ghcr.io/berriai/litellm:v1.106.4`. **Pin deliberately, never float** — and note two traps that are easy to fall into, both verified 2026-10-26:

1. **`main-latest` sounds newest but is stale.** It was built 2026-09-16; `main-stable` was built 2026-10-23. The names mislead.
2. **The `main-v<X.Y.Z>-stable` family ended** at `main-v1.83.14-stable`. There is no `main-v1.106*-stable`. Current stable is the **bare version tag**: `v1.106.4`.

Today `v1.106.4`, `main-stable` and `latest` are byte-identical (digest `sha256:c169fb3a…`), so pinning the explicit version costs nothing and cannot move under you mid-workshop.

Pre-pull before a workshop so a room is not all pulling at once:

```bash
docker pull ghcr.io/berriai/litellm:v1.106.4
```

> Image tags and PyPI versions use different numbering schemes and do not match. Do not go looking for an image called `1.40.3`.

### pip (no Docker)

Current PyPI version is **1.106.4**, requiring **Python >=3.10,<3.15**.

```bash
python3 -m venv ~/.venvs/litellm
source ~/.venvs/litellm/bin/activate
pip install 'litellm[proxy]'
```

Run it:

```bash
litellm --config configs/litellm/config.yaml --port 4000
```

You lose the container's network isolation but gain one less moving part. Either path works for this workshop.

---

## The config

Two ideas, and once they click the whole file is obvious.

```yaml
model_list:
  - model_name: local-chat            # ← PUBLIC alias. What clients ask for.
    litellm_params:
      model: openai/chat              # ← UPSTREAM id, with a provider prefix.
      api_base: http://host.docker.internal:8090/v1
      api_key: dummy
```

**`model_name`** is what your client sends. **`litellm_params.model`** is what LiteLLM asks the backend for.

The `openai/` prefix means "speak the OpenAI-compatible protocol". The part after the slash — `chat` — must match an id your local server exposes. Check:

```bash
curl -s http://127.0.0.1:8090/v1/models | jq -r '.data[].id'
```

Whatever that prints is what goes after `openai/`. If your llama-swap config calls the model `chat`, then `model: openai/chat` is right and `model: openai/local-chat` is wrong.

**The two names do not need to match, and usually should not.** Renaming at the gateway is free and invisible downstream — which is precisely why the gateway is worth having.

### `api_key: dummy` is correct

llama.cpp and llama-swap do not authenticate on localhost. But the OpenAI protocol requires the field, so LiteLLM must send *something*. `dummy` is the conventional value. Do not go hunting for a real key.

### `host.docker.internal`, not `127.0.0.1`

LiteLLM runs **inside a container**. From there, `127.0.0.1` means the container itself — where no model server exists. `host.docker.internal` means your actual machine.

On Linux and WSL2 that name does not exist unless you create it, which is what this line in `docker-compose.yml` does:

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

Docker Desktop (macOS, Windows) provides the name automatically, so the line is harmless there. **Missing it on Linux is the single most common LiteLLM failure in this workshop.** See [troubleshooting](troubleshooting.md#container-networking).

### Environment substitution

Values written `os.environ/NAME` are read from the environment at startup. That is why you edit `.env` and never `config.yaml`:

```yaml
api_base: os.environ/LOCAL_API_BASE
api_key:  os.environ/LOCAL_API_KEY
```

`.env` is gitignored; `.env.example` is committed and must never hold a real key.

---

## Verify it works

**Is it alive?** These two need **no auth**, even with a master key set — which is what makes them the right first probe:

```bash
curl -s http://127.0.0.1:4000/health/liveliness
# → "I'm alive!"

curl -s http://127.0.0.1:4000/health/readiness
# → {"status":"healthy","db":"Not connected"}
```

**Confirming your image pin actually took effect.** The plain readiness endpoint does *not* report a version — that detail is on `/health/readiness/details`, which needs the key:

```bash
curl -s http://127.0.0.1:4000/health/readiness/details \
  -H "Authorization: Bearer $LITELLM_API_KEY" | jq '.litellm_version, .db'
# → "1.106.4"
# → "Not connected"

# or straight from the container, no HTTP at all:
docker exec litellm litellm --version
# → LiteLLM: Current Version = 1.106.4
```

Worth doing once per student: a stale locally-cached image is invisible otherwise, and it is the kind of mismatch that makes two people in the same room get different behaviour from the same file.

**Are your routes registered?**

```bash
curl -s http://127.0.0.1:4000/v1/models -H "Authorization: Bearer $LITELLM_API_KEY" | jq -r '.data[].id'
```

You should see `local-chat`, `local-coder`, `local-embed`, `resilient`, `cloud-fast`, `cloud-gemini`. This lists what LiteLLM is *configured* with — it does not prove the backend is up.

**Auth is enforced.** Once `master_key` is set, *every* key-bearing endpoint needs the header — including `/v1/models` and `/health`. Without it you get `HTTP 401`, and the log records `No api key passed in`. That is expected behaviour, not a bug:

```bash
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000/v1/models    # → 401
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:4000/health        # → 401
```

> This is the single most common student blocker: `/health/liveliness` returns 200, so they conclude the proxy is healthy, then `/v1/models` returns 401 and they think they broke something. **The 401 is caused by setting the master key**, not by a mistake.
>
> If you want zero auth friction on a laptop-bound workshop, simply **omit `general_settings.master_key`** — then all of these are open on localhost and there is nothing to misplace. The trade is that anything on your machine can use the proxy.

**`/health` with a key does real work** — it sends a test request to every deployment and splits the results:

```bash
curl -s http://127.0.0.1:4000/health -H "Authorization: Bearer $LITELLM_API_KEY" | jq
# → {"healthy_endpoints":[...], "unhealthy_endpoints":[...]}
```

Add `?model=local-chat` to test one route.

**A real completion, end to end:**

```bash
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model":"local-chat","messages":[{"role":"user","content":"Say OK"}],"max_tokens":16}' \
  | jq -r '.choices[0].message.content'
```

If that prints something, your whole chain works: curl → LiteLLM → llama-swap → llama.cpp → weights on disk.

Or just run the checker, which does all of it and tells you where it broke:

```bash
./scripts/healthcheck.sh
```

**Embeddings through the same gateway:**

```bash
curl -s http://127.0.0.1:4000/v1/embeddings \
  -H "Content-Type: application/json" -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model":"local-embed","input":"the quick brown fox"}' \
  | jq '.data[0].embedding | length'
```

---

## Fallback — the reason this layer exists

```yaml
router_settings:
  fallbacks:
    - resilient: ["cloud-fast", "cloud-gemini"]
```

Ask for `resilient`. If it fails, LiteLLM tries `cloud-fast`, then `cloud-gemini`. First success wins.

Prove it to yourself — this is Exercise 5:

```bash
# 1. stop llama-swap (Ctrl-C in its terminal)
# 2. ask anyway
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model":"resilient","messages":[{"role":"user","content":"Say OK"}]}' | jq
```

It still answers. Your client code did not change. The response's `model` field tells you which backend served it.

Related knobs, all under `router_settings`:

| Key | Workshop value | Meaning |
|-----|----------------|---------|
| `allowed_fails` | `2` | Fails before a deployment is marked unhealthy |
| `cooldown_time` | `60` | Seconds to route around an unhealthy deployment |
| `num_retries` | `1` | Retries on the same model before falling back |

---

## Cloud routes

Both are optional. LiteLLM starts fine with empty keys — those routes only fail if you actually call them.

```yaml
  - model_name: cloud-fast
    litellm_params:
      model: openrouter/openai/gpt-4o-mini     # provider prefix: openrouter/
      api_key: os.environ/OPENROUTER_API_KEY

  - model_name: cloud-gemini
    litellm_params:
      model: gemini/gemini-2.0-flash           # provider prefix: gemini/
      api_key: os.environ/GEMINI_API_KEY
```

The **provider prefix** is the pattern: `openai/`, `openrouter/`, `gemini/`, `anthropic/`, `bedrock/`, `azure/`. It tells LiteLLM which protocol and SDK to use. Your local server is `openai/` because it speaks the OpenAI-compatible API — the same shape, whether it is a file on your laptop or a data centre.

- OpenRouter: one key reaches hundreds of models, with free tiers → <https://openrouter.ai/keys>
- Google AI Studio free tier → <https://aistudio.google.com/apikey>

> **Verify model names against the provider's current list.** They change constantly, and a stale name is a confusing `model not found`. `openrouter/openai/gpt-4o-mini` and `gemini/gemini-2.0-flash` were current when this was written; check before the workshop.

---

## The admin UI

```
http://127.0.0.1:4000/ui
```

**It needs a database.** This is the part that surprises people: the admin UI's stated requirements are *"Requires proxy master key to be set"* **and** *"Requires db connected."* Without Postgres it will not give you a working UI, however valid your master key is.

That is fine, and deliberate. What works **DB-less** is the part that actually matters for this workshop:

| Works without a database | Needs Postgres |
|--------------------------|----------------|
| Routing and load balancing | The admin UI (`/ui`) |
| Fallbacks and retries | Virtual keys (only the master key works) |
| `master_key` authentication | Budget enforcement (`max_budget` never fires) |
| Everything in `config.yaml` | Spend tracking |

Adding a Postgres dependency turns a five-minute setup into a fifty-minute one, and teaches nothing about self-hosting models. **Skip the UI.** Read your config and use `curl`.

If you genuinely want the UI, LiteLLM ships a two-service quickstart that brings up the gateway plus Postgres:

```bash
curl -sSLO https://github.com/BerriAI/litellm/raw/main/docker/docker-compose.quickstart.yml
printf 'LITELLM_MASTER_KEY=sk-%s\nLITELLM_SALT_KEY=sk-%s\n' \
  "$(openssl rand -hex 32)" "$(openssl rand -hex 32)" > .env
docker compose -f docker-compose.quickstart.yml up -d
```

Note `LITELLM_SALT_KEY` — it encrypts provider keys added through the UI. And **do not** set `disable_env_credential_login: true` before creating a DB admin user; the docs warn it *"will make you unable to log in."*

The config is deliberate about staying DB-less:

```yaml
litellm_settings:
  drop_params: true
  # no success_callback / failure_callback — those need a database
```

`drop_params: true` makes LiteLLM discard parameters a backend does not support instead of erroring. **It defaults to `False`, and for llama.cpp it is load-bearing rather than cosmetic.**

The concrete case, from a production config: llama-server's `/v1/embeddings` rejects a null `encoding_format` — which LiteLLM sends by default — with `type must be string, but is null`. Without `drop_params`, every embedding request 400s and the error points at the wrong layer. This matters specifically for the RAG exercise.

With small local models behind an OpenAI-shaped client, it removes a whole category of confusing failures. Turn it on.

---

## Timeouts

The most common "it's broken" that is not broken.

A **cold** llama-swap load has to start an engine and read a model into memory. That takes seconds, sometimes tens of seconds on a slow disk — and if the first request also has to *download* the weights, it can take minutes.

**Correcting a common misconception:** LiteLLM's global `request_timeout` default is generous, not tight. In 1.82.6 it was verified at **6000 seconds** (`litellm/constants.py`: `float(os.getenv("REQUEST_TIMEOUT", 6000))`). Later versions refactored that constant, so the exact default now depends on your tag — which is the real argument for setting it yourself rather than relying on it.

What actually bites is the **per-route** timeout, and the ordering between the three layers:

```yaml
litellm_settings:
  request_timeout: 900        # global ceiling — set it explicitly

  - model_name: local-chat
    litellm_params:
      timeout: 600            # generous, and costs nothing when the model is warm
```

Order them so nothing gives up before the layer below it has finished:

```
per-route timeout  >  global request_timeout  >  llama-swap healthCheckTimeout
```

Get that backwards and LiteLLM times out mid-load — and because **each retry re-triggers a fresh load**, retrying makes it worse rather than better.

Two notes from experience:

- A per-route `timeout` inside `litellm_params` is **not documented** on the configs page (which points you at `router_settings.timeout` / `litellm_settings.request_timeout`). It works, because `litellm_params` forwards anything `litellm.completion()` accepts. Verified by working deployment, not by docs.
- **For students, pre-warming beats tuning.** Send one throwaway request before the exercise starts and the cold load happens while nobody is waiting on it:

```bash
curl -s http://127.0.0.1:8090/v1/models >/dev/null
curl -s http://127.0.0.1:8090/v1/chat/completions -H "Content-Type: application/json" \
  -d '{"model":"chat","messages":[{"role":"user","content":"hi"}],"max_tokens":1}' >/dev/null
```

---

## Managing it

```bash
cd configs/litellm

docker compose up -d                 # start
docker compose logs -f litellm       # follow logs — your first debugging stop
docker compose restart litellm       # after editing config.yaml
docker compose down                  # stop and remove
docker compose up -d --force-recreate  # after editing .env
docker compose ps                    # status
```

**`config.yaml` is mounted read-only into the container.** Edit the file on the host, then restart — there is no hot reload in this setup.

**`.env` changes need `--force-recreate`**, not just `restart`: env files are read when the container is created.

---

## Pointing clients at it

Everything downstream uses the same two values:

```
base URL : http://127.0.0.1:4000/v1
api key  : $LITELLM_API_KEY
```

```bash
export LITELLM_API_KEY=sk-workshop-change-me     # must match .env
export OPENAI_API_BASE=http://127.0.0.1:4000/v1
export OPENAI_API_KEY=$LITELLM_API_KEY
```

Any OpenAI-compatible client — Qwen Code, OpenCode, the `openai` Python package, curl — will now use your gateway. That is [the next chapter](05-qwen-code.md).

---

## Common failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `401 Unauthorized` | Missing or wrong bearer token | Export `LITELLM_API_KEY` to match `.env` |
| `Connection refused` on `:4000` | Container not running | `docker compose up -d`, then `docker compose logs` |
| Routes listed but every completion fails | Container cannot reach the host | `extra_hosts: host-gateway` + `host.docker.internal` in `api_base` |
| `model not found` from the backend | `openai/<id>` does not match the server's id | `curl :8090/v1/models` and copy the real id |
| Timeout on the first request | Cold load exceeded the timeout | Raise `timeout`; it is not a crash |
| Container exits immediately | YAML syntax error | `python3 -c "import yaml;yaml.safe_load(open('config.yaml'))"` |
| `.env` change ignored | Env read at container *creation* | `docker compose up -d --force-recreate` |

Full details in [troubleshooting.md](troubleshooting.md).

---

**Next:** [05 — Qwen Code: an agent on your local model](05-qwen-code.md)

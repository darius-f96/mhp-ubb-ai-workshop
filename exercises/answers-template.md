# Workshop answers — YOUR NAME

Copy this file to `answers.md`, fill it in, and push it on your own branch.

Answer in your own words. Short and specific beats long and vague. Where an exercise asks for a number, paste the actual output — that is your evidence.

```
Name:
Date:
Machine:            # e.g. MacBook Air M2 16GB / ThinkPad T480 16GB / WSL2 12GB
OS:
CPU cores:
```

---

## Exercise 1 — Benchmark your own machine

Paste your `llama-bench` output here:

```
```

1. Decode speed (tok/s) for each model:
2. How does speed scale with model size?
3. How long does a 500-token answer take on the 1.7B?
4. Largest model you would use for interactive chat, and why:

---

## Exercise 2 — Break a tiny model on purpose

Paste both models' answers to the apple-shop prompt:

```
SmolLM2-135M:

Qwen3-1.7B:
```

1. Which model got the arithmetic right?
2. Did the 135M follow the "output only JSON" instruction? What did it do instead?
3. A task where you would still choose the 135M:
4. What this implies for small models inside an agent:

---

## Exercise 3 — Watch context cost you memory

| Setting | Model size | KV cache size |
|---------|-----------|---------------|
| `-c 4096` | | |
| `-c 32768` | | |
| `-c 32768` + `q8_0` KV cache | | |
| `-c 131072` | | |

1. KV growth from 4096 → 32768. Linear?
2. Savings from `--cache-type-k q8_0 --cache-type-v q8_0`, and the trade-off:
3. At `-c 32768`, is the KV cache larger than the weights? Why does that matter?
4. Symptom at `-c 131072` (what OOM actually looks like):
5. Two-sentence reply to "just set context to the max, it's free":

---

## Exercise 4 — Hot-swap between specialists

| Call | Time |
|------|------|
| `coder`, cold | |
| `coder`, warm | |
| `chat`, cold (after eviction) | |

1. Cold vs warm, and the cause of the difference:
2. What `/running` showed after requesting `chat`, and what happened to `coder`:
3. Why that is valuable on 16 GB, and what it costs:
4. What `ttl` and `proxy` control; what `ttl: 5` would do:
5. **Stretch** — the `tiny` model. Did you have to restart llama-swap?

---

## Exercise 5 — Survive a failure with a gateway (Optional)

1. Did the `resilient` request succeed with llama-swap down? Where did the tokens come from?
2. How you could tell which backend served it:
3. Why the client code not changing is the whole point:
4. What `/health` reported while the local backend was down:
5. One reason a company keeps the local path despite a better cloud model:

---

## Exercise 6 — Point an agent at your stack

1. Did the agent create and edit files? Which tools did it use?
2. How it behaved on the refactor (describe the failure mode if it failed):
3. Difference vs a cloud model — be specific, not polite:
4. Smallest model you would trust to edit a real codebase unsupervised, and what you would add to make a small model safe:
5. **Stretch** — which MCP server you configured and what it gave you:

---

## The one thing you would do differently

Two or three sentences. What surprised you most, and what would you change about your own setup after today?

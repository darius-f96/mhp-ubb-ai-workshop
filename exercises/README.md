# Exercises

Six exercises. Do them in order — each one assumes the previous stack is running.

Time budgets assume a 16 GB laptop with no GPU. If you are much faster, do the stretch goals. If you are stuck for more than ten minutes, **ask**. The point is the concepts, not the suffering.

Record your answers in `answers.md` (copy `answers-template.md`). At the end you will push that file to your own fork — which is also a Git exercise.

---

## Exercise 1 — Benchmark your own machine

**Time:** 10 min · **Goal:** stop guessing about your hardware

Before you choose a model, measure what your laptop can actually do.

```bash
llama-bench -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -ngl 0 -t 4 -p 512 -n 128
```

`-ngl 0` forces CPU (no GPU layers). `-t 4` sets threads. `pp512` is prefill speed — how fast it digests your prompt. `tg128` is decode speed — how fast it writes the answer.

> **Always pass `-t` and `-ngl` explicitly.** `llama-bench` defaults to `-t 20` threads and `-ngl -1` (offload everything). Twenty threads on a laptop produces noise, not a measurement, and `-ngl -1` will use a GPU you may not want in the number. Try `-t 2`, `-t 4` and `-t 8` and see where yours peaks — it is usually your *physical* core count, not your logical one.

Now the same for a bigger and a smaller model:

```bash
llama-bench -m ~/models/Qwen3-0.6B-Q4_0.gguf       -ngl 0 -t 4 -p 512 -n 128
llama-bench -m ~/models/Qwen3-4B-Q4_K_M.gguf       -ngl 0 -t 4 -p 512 -n 128
```

If you have an Apple Silicon Mac, run the 1.7B again **without** `-ngl 0` and compare. That gap is Metal doing the work instead of your CPU.

**Answer these:**

1. What is your decode speed (tok/s) for each model?
2. How does speed scale with model size? Is it linear, or worse?
3. At your 1.7B tok/s, how long does a 500-token answer take? Is that acceptable for interactive use?
4. What is the largest model you would use for *interactive chat* on this machine? Justify it with your numbers.

> **Why this matters:** every "which model should I use?" question is answered by these two numbers. People who skip this step spend the workshop waiting on a model that is too big, then conclude self-hosting does not work.

---

## Exercise 2 — Break a tiny model on purpose

**Time:** 10 min · **Goal:** see what scale actually buys you

Download the 135M model if you have not:

```bash
hf download unsloth/SmolLM2-135M-Instruct-GGUF SmolLM2-135M-Instruct-Q4_K_M.gguf --local-dir ~/models
```

Serve both, on different ports, in two terminals:

```bash
# terminal 1
llama-server -m ~/models/SmolLM2-135M-Instruct-Q4_K_M.gguf -c 4096 --port 8081
# terminal 2
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -c 4096 --port 8082
```

Ask **both** the identical prompt:

```bash
for p in 8081 8082; do
  echo "── port $p ──"
  curl -s http://127.0.0.1:$p/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"m","messages":[{"role":"user","content":"A shop has 17 apples. It sells 5, then restocks with twice as many as it has left. How many apples now? Show your reasoning briefly."}]}' \
    | jq -r '.choices[0].message.content'
  echo
done
```

Then try something needing instruction following:

```bash
for p in 8081 8082; do
  echo "── port $p ──"
  curl -s http://127.0.0.1:$p/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d '{"model":"m","messages":[{"role":"user","content":"List exactly three prime numbers as a JSON array. Output only the JSON, no other text."}]}' \
    | jq -r '.choices[0].message.content'
  echo
done
```

**Answer these:**

1. Which model got the arithmetic right?
2. Did the 135M follow the "output only JSON" instruction? What did it do instead?
3. The 135M is ~13× smaller and much faster. Name a task where you would still choose it.
4. What does this tell you about using small models inside an *agent* that must emit structured tool calls?

> **Why this matters:** you will be tempted to run the smallest model because it is fast. This exercise is the inoculation. Structured output is the first capability to disappear as models shrink, and agents are built entirely out of structured output.

---

## Exercise 3 — Watch context cost you memory

**Time:** 15 min · **Goal:** understand the constraint that actually limits you

Start the server with a small context and watch the startup log:

```bash
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -c 4096 --port 8080 2>&1 | grep -iE 'kv|context|model size'
```

Note the KV cache size. Stop it (`Ctrl-C`) and repeat at 8× the context:

```bash
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -c 32768 --port 8080 2>&1 | grep -iE 'kv|context|model size'
```

Now add the KV quantisation flags and compare:

```bash
llama-server -m ~/models/Qwen3-1.7B-Q4_K_M.gguf -c 32768 --flash-attn on \
  --cache-type-k q8_0 --cache-type-v q8_0 --port 8080 2>&1 | grep -iE 'kv|context|model size'
```

Finally, push until it hurts. Try `-c 131072` and see what your machine does.

**Answer these:**

1. How much did the KV cache grow from `-c 4096` to `-c 32768`? Was it linear?
2. How much did `--cache-type-k q8_0 --cache-type-v q8_0` save? What is the trade-off?
3. At `-c 32768`, is the KV cache larger than the model weights? Why does that matter for choosing a model?
4. What happened at `-c 131072`? Describe the *symptom* — that is what an OOM looks like in practice.
5. Your colleague says "just set the context to the model's maximum, it's free". Write them a two-sentence reply.

> **Why this matters:** newcomers blow up their RAM with context, not with model size. A 1.3 GB model with a 128k context can use more memory than an 8 GB model with a 4k context.

---

## Exercise 4 — Hot-swap between specialists

**Time:** 20 min · **Goal:** one port, several models, only one in RAM

Use [`configs/llama-swap/config.yaml`](../configs/llama-swap/config.yaml), which defines a chat model, a code model and an embedding model.

```bash
llama-swap --config configs/llama-swap/config.yaml --listen 127.0.0.1:8090
```

Leave it in the foreground so you can read its log. In a second terminal:

```bash
curl -s http://127.0.0.1:8090/v1/models | jq -r '.data[].id'
```

All models are listed, but **none are loaded**. Verify that:

```bash
curl -s http://127.0.0.1:8090/running | jq
```

Now request the code model and watch the llama-swap log:

```bash
time curl -s http://127.0.0.1:8090/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"coder","messages":[{"role":"user","content":"Write a Python function that reverses a string."}]}' \
  | jq -r '.choices[0].message.content'
```

The first call is slow because it cold-loads. Call it again immediately and compare the time. Then ask for the *chat* model and watch what happens to the coder:

```bash
time curl -s http://127.0.0.1:8090/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"chat","messages":[{"role":"user","content":"Hello!"}]}' \
  | jq -r '.choices[0].message.content'

curl -s http://127.0.0.1:8090/running | jq
```

**Answer these:**

1. How long did the cold call take versus the warm one? What caused the difference?
2. After requesting `chat`, what does `/running` show? What did llama-swap do to `coder`?
3. Why is that behaviour valuable on a 16 GB laptop, and what does it cost you?
4. In the config, what do `ttl` and `proxy` control? What would happen if you set `ttl: 5`?
5. **Stretch:** add a fourth model to the config — the 135M from Exercise 2 — under the id `tiny`. Do not restart llama-swap if you can avoid it; find out whether you have to.

> **Why this matters:** this is the difference between "I can run one model" and "I have a local model service". Specialisation is how small models become useful — a small code model plus a small chat model beats one mediocre generalist, as long as only one is resident at a time.

---

## Exercise 5 — Survive a failure with a gateway

**Time:** 20 min · **Goal:** resilience, and the reason LiteLLM exists

Bring up LiteLLM with [`configs/litellm/`](../configs/litellm/):

```bash
cd configs/litellm && cp .env.example .env && docker compose up -d && cd ../..

# Load the key into THIS shell. `.env` is read by the CONTAINER, not by your
# terminal — skip this and every curl below 401s against a healthy gateway.
set -a; . configs/litellm/.env; set +a
echo "$LITELLM_API_KEY"        # must print your key, not an empty line

./scripts/healthcheck.sh
```

Confirm the proxy sees your local models:

```bash
curl -s http://127.0.0.1:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_API_KEY" | jq -r '.data[].id'
```

Talk to the local model *through* the proxy:

```bash
curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model":"local-chat","messages":[{"role":"user","content":"Say OK"}]}' | jq -r '.choices[0].message.content'
```

Now break it on purpose. Stop llama-swap (`Ctrl-C` in its terminal) and ask the proxy for a model configured with a cloud fallback:

```bash
time curl -s http://127.0.0.1:4000/v1/chat/completions \
  -H "Content-Type: application/json" -H "Authorization: Bearer $LITELLM_API_KEY" \
  -d '{"model":"resilient","messages":[{"role":"user","content":"Say OK"}]}' | jq
```

Restart llama-swap. Then read the gateway's view of the world:

```bash
docker logs litellm --tail 40
curl -s http://127.0.0.1:4000/health -H "Authorization: Bearer $LITELLM_API_KEY" | jq
```

**Answer these:**

1. Did the `resilient` request succeed while llama-swap was down? Where did the tokens come from?
2. How could you tell from the response which backend served it?
3. Your client code did not change between the local and cloud call. Why is that the whole point?
4. What did `/health` report while the local backend was down?
5. **Design question:** give one reason a company might keep the local path even though the cloud model is better.

> **Why this matters:** a demo that dies when a service restarts is a bad demo. A system that degrades to a fallback and recovers is a system you can put in production. You just watched that happen because you caused it deliberately.

---

## Exercise 6 — Point an agent at your stack

**Time:** 25 min · **Goal:** the payoff — a coding agent running entirely locally

Configure Qwen Code with [`configs/qwen/settings.json`](../configs/qwen/settings.json) so it uses the proxy at `:4000`. Then, in a scratch directory:

```bash
mkdir -p ~/agent-test && cd ~/agent-test
git init -q
qwen --model local-chat
```

Ask it to do something small and concrete:

> Create a file `fizzbuzz.py` with a function `fizzbuzz(n)` that returns a list of strings for 1..n, and a test file `test_fizzbuzz.py` with three tests.

Watch what it does. Then ask it something requiring real reasoning:

> Refactor fizzbuzz.py so the divisor/word pairs come from a data structure instead of being hardcoded, without breaking the tests.

**Answer these:**

1. Did the agent successfully create and edit files? Which tools did it use?
2. How did it behave on the refactor — did it get it right first time? Describe the failure mode if not.
3. Now switch to a cloud model and repeat the refactor. Describe the difference. Be specific, not polite.
4. What is the smallest model you would trust to edit a real codebase unsupervised? What would you need to add to make a small model safe to use that way?
5. **Stretch:** configure one MCP server (a filesystem or Git MCP works well) and have the agent use it. What did the MCP give you that the plain agent did not?

> **Why this matters:** this is the honest conclusion of the workshop. Small local models are genuinely useful for retrieval, extraction, classification and private work — and genuinely not good enough to drive an agent through a real codebase. You now have the experience to say which is which, and the stack to route each job to the right place.

---

## Handing in

You cloned **our** repository, so its `origin` is read-only for you — pushing to it fails with a 403. You need your own copy on GitHub first.

**1 · Fork, once, in the browser.** Open <https://github.com/darius-f96/mhp-ubb-ai-workshop> and click **Fork** (top right). That creates `github.com/YOUR-USERNAME/mhp-ubb-ai-workshop` under your account, which you *can* push to.

**2 · Add your fork as a second remote.** Keeping `origin` pointed at upstream means you can still pull corrections during the day:

```bash
git remote add mine https://github.com/YOUR-USERNAME/mhp-ubb-ai-workshop.git
git remote -v        # verify: origin = darius-f96, mine = YOUR-USERNAME
```

**3 · Work on a branch, commit, push to your fork:**

```bash
cp answers-template.md answers.md
# ... fill it in ...

git checkout -b workshop-YOURNAME
git add answers.md
git commit -m "AI workshop exercises"
git push -u mine workshop-YOURNAME
```

**4 · Open the pull request** on your own fork — GitHub usually offers a "Compare & pull request" banner straight after the push. Base it on *your* `main`, compare `workshop-YOURNAME`, then share the link with an instructor.

> `git add answers.md` names one file deliberately. If you built llama.cpp or downloaded models inside this directory, a bare `git add .` would try to commit gigabytes of weights and a nested repository. Check `git status` before you commit — that habit is worth more than the exercise.

---

## If you finish early

- **Build the RAG pipeline properly.** [`rag/rag.py`](rag/rag.py) is a complete, dependency-free implementation — chunking, embeddings, cosine retrieval, cited answers, standard library only. Read it, run it, then break it and fix it:

  ```bash
  python3 rag/rag.py index                      # embed docs/ into vectors
  python3 rag/rag.py search "context window"    # retrieval only — debug here
  python3 rag/rag.py ask "what does llama-swap do?"
  ```

  Use `search` before `ask` when results are bad. It removes the chat model from the picture, so you can tell a *retrieval* problem from a *generation* problem — and that distinction is most of RAG tuning. Then try: change `CHUNK_CHARS` from 1200 to 400 and re-index. Does retrieval get better or worse? Why?

- Add the vision model (`Qwen3-VL-2B`) to llama-swap and have it describe an image. Note how slow CPU vision is.
- Run `llama-server` with `--parallel 4` and hit it with four concurrent requests. What happens to per-request speed? Why?
- Try the same model at Q2_K and Q8_0. Score both on the Exercise 2 prompts. Where exactly does quantisation start to hurt?

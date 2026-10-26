# 7 — vLLM: what production serving looks like

**Read this first:** you are probably not going to run vLLM in this workshop, and that is the correct outcome. This chapter exists so you understand what it is, why it exists, and what the instructor is doing when they demo it.

The honest numbers, verified 2026-10-26:

| Fact | Value |
|------|-------|
| Current version | **0.32.0** (PyPI, requires Python `>=3.11,<3.15`) |
| Docker image | `vllm/vllm-openai:v0.32.0` |
| **Image size** | **10.31 GB** |
| Nightly image size | 9.7–12.5 GB |
| CPU-only image tag | **does not exist** (`cpu` and `nightly-cpu` both 404) |
| Minimum sensible GPU VRAM | ~8 GB, and only for small models |

A 10 GB download on venue Wi-Fi, for software that wants a GPU you do not have. **Use llama.cpp.** That is not a compromise — for one user on a laptop it is the right tool.

---

## So what is it for?

vLLM is built for **throughput under concurrency**. Its headline contribution is **PagedAttention**: it manages KV-cache memory the way an operating system manages virtual memory — in non-contiguous pages, allocated on demand, instead of one big reserved block per request.

The consequence is that it can pack many requests into the same GPU memory at once. Serve a hundred users from one GPU and vLLM will beat llama.cpp substantially. Serve **one** user from one laptop CPU and there is nothing to batch, so all that machinery is overhead.

That is the whole trade-off in one sentence: **vLLM optimises for many concurrent requests on a GPU; llama.cpp optimises for running anywhere.**

---

## vLLM vs llama.cpp

| | **llama.cpp** | **vLLM** |
|---|---|---|
| Language | C/C++ | Python (with C++/CUDA kernels) |
| Model format | GGUF | safetensors (HF checkpoints) |
| Hardware | CPU, Apple Metal, NVIDIA, AMD, phones | NVIDIA GPU primarily; CPU build exists but is not the point |
| Install weight | ~100 MB binary | 10.31 GB image, or a heavy Python env |
| Strength | Runs anywhere; excellent for one user | Throughput and batching for many users |
| Quantisation | Extensive GGUF quants (Q2–Q8, imatrix) | AWQ, GPTQ, FP8, NVFP4, bitsandbytes |
| KV cache | Contiguous, sized up front by `-c` | Paged — allocated on demand |
| Laptop with no GPU | **Yes** | No |
| Production GPU server | Possible | **Yes** |

**Pick llama.cpp** when: one user, a laptop, no GPU, edge devices, or you want the smallest possible footprint.
**Pick vLLM** when: a GPU, multiple concurrent users, and throughput is the metric you care about.

---

## If you do have an NVIDIA GPU

The fastest path is Docker. Verify your driver first:

```bash
nvidia-smi
```

If that does not print a GPU table, stop — you need drivers and the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html) before any of this works.

Then:

```bash
docker run --rm --gpus all \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -p 8000:8000 \
  vllm/vllm-openai:v0.32.0 \
  --model Qwen/Qwen3-1.7B \
  --served-model-name local-chat \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.85 \
  --port 8000
```

It speaks the same OpenAI-compatible API, so **nothing downstream changes**:

```bash
curl -s http://127.0.0.1:8000/v1/models | jq -r '.data[].id'

curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"local-chat","messages":[{"role":"user","content":"Say OK"}]}' \
  | jq -r '.choices[0].message.content'
```

Point LiteLLM at `:8000` instead of `:8090` and the rest of the workshop is identical. That is the value of the standard API — you just swapped an inference engine without touching a client.

### Flags that matter

| Flag | Purpose |
|------|---------|
| `--model` | HF repo id or a local path |
| `--served-model-name` | The id clients ask for. Decouples the public name from the checkpoint |
| `--max-model-len` | Context window, **per sequence** — unlike llama.cpp's `-c`, this is not divided by concurrency |
| `--gpu-memory-utilization` | Fraction of VRAM to claim (0.0–1.0). Leaves room for the rest of your system |
| `--max-num-seqs` | Concurrent sequences. Lower = better per-request latency; higher = better throughput |
| `--enable-prefix-caching` | Reuse KV for repeated prompt prefixes. Big win for agentic workloads that resend the same context |
| `--enable-chunked-prefill` | Interleave long prefills with decodes so one big prompt does not stall everyone |
| `--max-num-batched-tokens` | Batch size cap per step |
| `--enable-auto-tool-choice` | Required for tool calling |
| `--tool-call-parser` | Which format the model emits (`hermes`, `qwen3_coder`, `llama3_json`, …) — must match the model |
| `--reasoning-parser` | Extracts chain-of-thought into `reasoning_content` |
| `--kv-cache-dtype` | Quantise the KV cache (`auto`, `fp8`, …) |
| `--quantization` | Force a quant method (`awq`, `gptq`, `fp8`, …) |
| `--tensor-parallel-size` | Shard across N GPUs |
| `--host` / `--port` | Bind address |

### VRAM guidance

Weights plus KV cache plus activations must fit. Rough figures for 4-bit quantised checkpoints:

| Model size | Weights | Practical minimum VRAM | Notes |
|-----------|---------|------------------------|-------|
| 1.5–3B | ~1–2 GB | **8 GB** | Comfortable, good context headroom |
| 7–8B | ~4–5 GB | **12–16 GB** | The sweet spot for a single consumer GPU |
| 14B | ~8–9 GB | **24 GB** | Needs a 3090/4090 class card |
| 27B+ | 15 GB+ | 2×24 GB or better | Tensor parallelism |

Sensible targets for an 8 GB card: `Qwen/Qwen3-1.7B`, `Qwen/Qwen3-4B`, `Qwen/Qwen2.5-Coder-3B-Instruct`, `HuggingFaceTB/SmolLM3-3B`. Keep `--max-model-len` modest — 8192 or 16384 — because KV cache competes directly with weights for the same memory.

> Verify the exact VRAM you have with `nvidia-smi`, and start `--gpu-memory-utilization` at 0.85. If you get a CUDA out-of-memory error, lower `--max-model-len` before you lower the model size — context is usually the cheaper thing to give up.

### Apple Silicon

vLLM has experimental Metal support, but it is not the well-trodden path. On a Mac, **llama.cpp with Metal is faster and far easier**. Do not fight this one.

---

## The CPU question, answered honestly

There is no CPU Docker image. You would install from source or via pip:

```bash
pip install vllm          # Python >=3.11,<3.15
```

CPU support is documented at <https://docs.vllm.ai/en/latest/getting_started/installation/cpu/index.html>, and it typically means building from source with specific flags.

**It will run. It will not be pleasant.** vLLM's entire design assumes a GPU with fast parallel matrix math and lots of memory bandwidth. On a CPU you pay the 10 GB install, a long build, and a large Python dependency tree — and then get *worse* performance than llama.cpp, which has spent years optimising CPU kernels (AVX, NEON, quantised matmul).

If you are on a CPU: **llama.cpp, full stop.** There is no scenario in this workshop where CPU vLLM is the better choice.

---

## What the instructor's demo shows

Advanced vLLM tuning, on hardware you do not have — included so you recognise the techniques rather than to reproduce them.

A real production launcher on a 128 GB NVIDIA DGX Spark passes, among others:

```
--max-model-len 500000
--max-num-seqs 4
--gpu-memory-utilization 0.80
--enable-prefix-caching
--enable-chunked-prefill
--max-num-batched-tokens 8192
--enable-auto-tool-choice --tool-call-parser qwen3_coder
--reasoning-parser qwen3
--kv-cache-dtype auto
--hf-overrides '{"text_config":{"rope_parameters":{"rope_type":"yarn","factor":4.0,...}}}'
--speculative-config '{"method":"mtp","num_speculative_tokens":2}'
```

Worth understanding three of these, because the ideas transfer:

- **`--hf-overrides` with YaRN** extends context beyond what the model was trained on, by rescaling rotary position embeddings. Note the trade-off: the server *accepts* 500 000 tokens, but the trained ceiling is 262 144 and everything above that is extrapolation — quality degrades. Accepting a request is not the same as handling it well.
- **`--speculative-config` with MTP** (multi-token prediction) drafts several tokens at once and verifies them in a single pass. It wins when acceptance rates are high — notably on code — and *loses* when the draft model costs more than it saves. On a bandwidth-bound machine, adding a draft to an already-cheap MoE step made things **47% slower** in one measured case. Benchmark; do not assume.
- **`--enable-prefix-caching`** is the one that matters most for agents. An agent resends the same system prompt and file context on every turn; caching that prefix makes follow-ups dramatically cheaper.

The general lesson, which does apply to your laptop: **serving configuration is a set of trade-offs, not a list of things to maximise.** Every flag buys something and costs something else. The people who run this well measure.

---

## Other engines worth knowing

vLLM and llama.cpp are not the whole field:

- **SGLang** — strong on structured generation and RadixAttention prefix caching
- **TensorRT-LLM** — NVIDIA's, fastest on their hardware, much more setup
- **Ollama** — wraps llama.cpp with a friendly CLI and a model library. The easiest possible on-ramp, and worth installing just to compare
- **LocalAI** — OpenAI-compatible drop-in with a broader feature surface
- **ik_llama.cpp** — a llama.cpp fork focused on long context and speculative decoding

They all speak the same OpenAI-compatible API, so swapping between them is a config change in LiteLLM. Pick based on your hardware and your concurrency, not on which is most discussed.

---

## Summary

| Question | Answer |
|----------|--------|
| Should I install vLLM for this workshop? | **No.** Use llama.cpp |
| Why is it in the curriculum at all? | So you can follow the demo and know what production serving involves |
| When would I reach for it? | A GPU, and more than a handful of concurrent users |
| Does it change anything downstream? | No — same API. LiteLLM points at a different port, nothing else moves |
| Can I run it on CPU? | Technically yes. Practically, do not |

---

**Next:** [08 — qwen serve: your agent as a service](08-qwen-serve.md)

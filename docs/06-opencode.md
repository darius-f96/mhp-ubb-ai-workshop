# 6 — OpenCode: a second agent, same backend

You already have Qwen Code driving your local stack. Why a second agent?

Because the interesting lesson is not "how do I configure tool X" — it is that **the backend is the durable part**. Both agents point at the same `http://127.0.0.1:4000/v1`. Swap the client, keep the stack. That is what the OpenAI-compatible API buys you, and you only feel it by actually swapping.

By the end of this page OpenCode will be using the exact same llama.cpp → llama-swap → LiteLLM chain, with no change to any of them.

---

## What it is

A terminal coding agent, provider-agnostic by design. It does not favour one vendor's models; it treats every provider as configuration.

Current version: **1.19.4** on npm and GitHub Releases (published 2026-10-22).

> **Versions differ by install channel.** Homebrew currently builds **2.1.4** from a source tag, while npm and GitHub Releases are at **1.19.4**. That is not a typo and not something you did wrong — the channels are out of step. Treat `opencode --version` as the only authority for what *you* have.

> **Package-name warning:** the npm package is **`opencode-ai`**. `@opencode-ai/opencode` does **not** exist — it returns a 404. Easy mistake, confusing error.

> **The project moved.** It was `sst/opencode`; the canonical repo is now **`anomalyco/opencode`**. The old URL still works via a redirect, but use the new one.

---

## Install

### The install script

```bash
curl -fsSL https://opencode.ai/install | bash
opencode --version
```

### npm

```bash
npm install -g opencode-ai
opencode --version
```

### Homebrew (macOS / Linux)

It is in homebrew-core — no tap needed:

```bash
brew install opencode
```

<details>
<summary>Why <code>brew install sst/tap/opencode</code> no longer works</summary>

Older guides point at the `sst` tap. That tap's formula is gone (404) now that the project moved to `anomalyco`, and OpenCode is packaged in homebrew-core as plain `opencode`. Use the core formula.
</details>

### Pre-built binaries

From <https://github.com/anomalyco/opencode/releases> — verified asset names for v1.19.4:

| Platform | Asset | Size |
|----------|-------|------|
| Linux x86-64 | `opencode-linux-x64.tar.gz` | 79.7 MB |
| Linux x86-64 (musl / Alpine) | `opencode-linux-x64-musl.tar.gz` | 79.7 MB |
| Linux x86-64 (older CPU) | `opencode-linux-x64-baseline.tar.gz` | 79.7 MB |
| Linux ARM64 | `opencode-linux-arm64.tar.gz` | 78.5 MB |
| macOS Apple Silicon | `opencode-darwin-arm64.zip` | — |
| macOS Intel | `opencode-darwin-x64.zip` | — |

```bash
curl -L -o opencode.tar.gz \
  https://github.com/anomalyco/opencode/releases/download/v1.19.4/opencode-linux-x64.tar.gz
tar xzf opencode.tar.gz
sudo mv opencode /usr/local/bin/
opencode --version
```

Use the `-baseline` build if you get an *illegal instruction* crash on an older CPU, and the `-musl` build on Alpine.

---

## Point it at your gateway

### Where config lives

OpenCode layers config; **later sources override earlier ones** (from the official docs):

1. Remote config — `.well-known/opencode`, organizational defaults
2. **Global** — `~/.config/opencode/opencode.json`
3. Custom — `OPENCODE_CONFIG` env var
4. **Project** — `opencode.json` in the project root
5. `.opencode/` directories — agents, commands, plugins
6. Inline — `OPENCODE_CONFIG_CONTENT` env var
7. Managed files — `/Library/Application Support/opencode/` on macOS
8. macOS managed preferences — `.mobileconfig` via MDM (highest; not user-overridable)

For this workshop, **global** is what you want — configure it once, use it in every project.

```bash
mkdir -p ~/.config/opencode
$EDITOR ~/.config/opencode/opencode.json
```

### The config

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Self-hosted via LiteLLM",
      "options": {
        "baseURL": "http://127.0.0.1:4000/v1",
        "apiKey": "{env:LITELLM_API_KEY}"
      },
      "models": {
        "local-chat":  { "name": "Qwen3-1.7B (local)" },
        "local-coder": { "name": "Qwen2.5-Coder-1.5B (local)" },
        "resilient":   { "name": "Local with cloud fallback" },
        "cloud-fast":  { "name": "Cloud (OpenRouter)" }
      }
    }
  }
}
```

Field by field:

| Field | Meaning |
|-------|---------|
| `$schema` | Gives your editor autocomplete and validation. Worth keeping |
| `provider.local` | A provider id — **any string you like**. This is what you prefix model names with |
| `npm` | Which adapter package implements the protocol. `@ai-sdk/openai-compatible` for anything OpenAI-shaped, including your local stack |
| `name` | Display label in the UI |
| `options.baseURL` | Your gateway, **including `/v1`** |
| `options.apiKey` | The key. `{env:VAR}` reads it from the environment instead of hardcoding it |
| `models` | A map of model ids to display config |

**The rule that causes most failures**, straight from OpenCode's own docs:

> Each ID must match the id returned by `GET /v1/models`.

So check before you guess:

```bash
curl -s http://127.0.0.1:4000/v1/models -H "Authorization: Bearer $LITELLM_API_KEY" | jq -r '.data[].id'
```

Whatever that prints goes in the `models` map — and those ids are the `model_name` values you defined in [LiteLLM's config](04-litellm.md#the-config). That is the whole chain agreeing on one set of names.

Then set the key:

```bash
export LITELLM_API_KEY=sk-workshop-change-me
```

---

## Run it

```bash
cd ~/my-project
opencode
```

Inside the session:

| Command | Purpose |
|---------|---------|
| `/models` | List what is configured, and switch model |
| `/connect` | Add or authenticate a hosted provider interactively |
| `/init` | Generate an `AGENTS.md` context file for the project |
| `/help` | Everything else |

Select a model directly:

```bash
opencode --model local/local-chat
```

Note the `provider/model` shape — `local` is the provider id you invented in the config, `local-chat` is the model id. Two levels, and it is easy to type only one.

One-shot, without the interactive UI:

```bash
opencode run "Explain what this repo does" --model local/local-chat
```

---

## Models it already knows about

OpenCode ships with a catalogue of hosted models (from [models.dev](https://models.dev)), so for cloud providers you often need no `provider` block at all:

```bash
opencode
/models          # browse what is already known
/connect         # authenticate a provider
```

That is the difference in philosophy from Qwen Code: OpenCode assumes you will point it at *anything*, and ships a catalogue so the common cases need no config. Your local server is the case that does need config, because it is not in any catalogue.

---

## MCP servers

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "context7": {
      "type": "local",
      "command": ["npx", "-y", "@upstash/context7-mcp"],
      "enabled": true
    },
    "my-remote": {
      "type": "remote",
      "url": "https://mcp.example.com/mcp",
      "enabled": true
    }
  }
}
```

Two types: `local` (a command OpenCode launches) and `remote` (a URL it connects to). `enabled: false` disables a server without deleting it — useful when an organisation's remote config ships servers you do not want, because your own config overrides theirs.

The same caveat as everywhere else in this workshop: **MCP means tool calling, and tool calling is what small models are worst at.** OpenCode's own docs say it plainly:

> If tool calls aren't working well, pick a loaded model with strong tool-calling support (for example, a Qwen-Coder or DeepSeek-Coder variant).

That is exactly the wall Exercise 2 and Exercise 6 are designed to show you. Use `local-coder` rather than `local-chat` for tool work, and expect to reach for a cloud model for anything serious.

---

## Project context

OpenCode reads **`AGENTS.md`** — the emerging cross-tool convention for agent instructions (Qwen Code uses `QWEN.md`, Claude Code uses `CLAUDE.md`; the idea is identical).

```bash
opencode
/init          # generates AGENTS.md from your repo
```

Then edit it down. Keep it short and factual: build command, test command, conventions, what not to touch. Small models benefit disproportionately — it removes guesswork they cannot supply themselves.

---

## Qwen Code vs OpenCode

Neither is better; they make different trade-offs.

| | **Qwen Code** | **OpenCode** |
|---|---|---|
| Install | `npm i -g @qwen-code/qwen-code` | `npm i -g opencode-ai`, script, or brew |
| Version verified | 0.26.1 | 1.19.4 |
| Requires | Node >= 22 | — |
| Config file | `~/.qwen/settings.json` | `~/.config/opencode/opencode.json` |
| Config style | `modelProviders.openai` **array**, key via `envKey` indirection | `provider.<id>` **map**, key via `{env:VAR}` interpolation |
| Local provider | Built in — just add an entry | Needs `npm: "@ai-sdk/openai-compatible"` |
| Model catalogue | Your own providers | Ships [models.dev](https://models.dev) catalogue |
| Context file | `QWEN.md` | `AGENTS.md` |
| Selecting a model | `--model local-chat` | `--model local/local-chat` |
| Daemon mode | **Yes** — `qwen serve`, browser UI, LAN sharing | Serve mode for its own UI |
| MCP | `qwen mcp add` CLI + `mcpServers` | `mcp` block, `local`/`remote` types |
| Distinctive | `qwen serve` turns it into a service ([ch. 8](08-qwen-serve.md)); extensions, hooks, review, batch | Provider-agnostic; org config via `.well-known`; MDM-manageable |

**For this workshop:** configure both. It takes ten minutes, and the comparison teaches you that the *stack* is the durable investment — the client is interchangeable. That is worth more than fluency in either tool.

---

## Verify

```bash
# 1. config is valid JSON
python3 -c "import json;json.load(open('$HOME/.config/opencode/opencode.json'));print('JSON OK')"

# 2. the ids you configured actually exist upstream
curl -s http://127.0.0.1:4000/v1/models -H "Authorization: Bearer $LITELLM_API_KEY" | jq -r '.data[].id'

# 3. a real completion
opencode run "Reply with exactly: OPENCODE-OK" --model local/local-chat
```

If step 3 hangs or errors, work down the stack — `./scripts/healthcheck.sh` tells you which layer broke. It is almost never OpenCode.

---

## Common failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| `404` installing `@opencode-ai/opencode` | Wrong package name | It is **`opencode-ai`** |
| `model not found` | id does not match `/v1/models` | Copy the id from the curl above |
| `provider not found` | You passed `local-chat` instead of `local/local-chat` | Include the provider prefix |
| `401` | `LITELLM_API_KEY` unset or wrong | Export it; must match `LITELLM_MASTER_KEY` |
| Illegal instruction on launch | CPU too old for the default build | Use `opencode-linux-x64-baseline.tar.gz` |
| Crash on Alpine | glibc build on musl | Use the `-musl` asset |
| Config ignored | Wrong scope, or an earlier layer overrode it | Project config beats global; check both |
| Malformed tool calls | Model too small | Use `local-coder` or a cloud model |

Full details in [troubleshooting.md](troubleshooting.md).

---

**Next:** [07 — vLLM: what production serving looks like](07-vllm.md)

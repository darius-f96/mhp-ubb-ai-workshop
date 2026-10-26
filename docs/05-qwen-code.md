# 5 — Qwen Code: an agent on your local model

Everything so far produced an HTTP endpoint. This is where it becomes useful: a terminal agent that reads your repository, edits files, and runs commands — driven by the model on your laptop.

By the end of this page Qwen Code will be talking to your LiteLLM gateway, and you will understand the two settings that decide whether it works or quietly misbehaves.

---

## What it is

An agentic coding CLI from Alibaba, in the same family as Claude Code and Gemini CLI. It runs in your terminal, has tools for reading and editing files and running shells, supports MCP servers, and can run as a daemon ([chapter 8](08-qwen-serve.md)).

Current version: **0.26.1** (npm `@qwen-code/qwen-code`). Requires **Node >= 22**.

---

## Install

```bash
npm install -g @qwen-code/qwen-code
qwen --version
```

Check the published version and Node requirement yourself:

```bash
npm view @qwen-code/qwen-code version engines
```

**Update later:**

```bash
qwen update          # built-in updater
npm update -g @qwen-code/qwen-code
```

If `npm install -g` fails with a permissions error, do **not** reach for `sudo`. Fix the prefix instead:

```bash
mkdir -p ~/.npm-global
npm config set prefix ~/.npm-global
echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc   # or ~/.zshrc
source ~/.bashrc
npm install -g @qwen-code/qwen-code
```

---

## Point it at your local stack

There are two ways. **Use `settings.json`** — the env-var route has a trap, described below.

### The settings.json route (recommended)

Copy the prepared file:

```bash
mkdir -p ~/.qwen
cp configs/qwen/settings.json ~/.qwen/settings.json
$EDITOR ~/.qwen/settings.json
```

Two things to edit:

1. **`env.WORKSHOP_LITELLM_KEY`** — must match `LITELLM_MASTER_KEY` in `configs/litellm/.env`
2. **`generationConfig.contextWindowSize`** — must match the `-c` you gave llama.cpp

The shape:

```json
{
  "env": {
    "WORKSHOP_LITELLM_KEY": "sk-workshop-change-me"
  },
  "modelProviders": {
    "openai": [
      {
        "id": "local-chat",
        "name": "local-chat — Qwen3-1.7B, self-hosted",
        "baseUrl": "http://127.0.0.1:4000/v1",
        "envKey": "WORKSHOP_LITELLM_KEY",
        "generationConfig": {
          "contextWindowSize": 8192,
          "temperature": 0.2
        }
      }
    ]
  }
}
```

Field by field:

| Field | Meaning |
|-------|---------|
| `modelProviders.openai` | An **array** of providers speaking the OpenAI-compatible protocol |
| `id` | What you pass to `--model`. Must match a `model_name` in LiteLLM |
| `name` | Label shown in the picker |
| `baseUrl` | Your gateway, **including `/v1`** |
| `envKey` | The **name** of an env var holding the key — not the key itself |
| `env` | Defines those variables. Keeps secrets out of the provider block |
| `generationConfig` | Per-model generation settings |

Note `envKey` is indirection: the provider says *which* variable to read, and `env` supplies its value. That is why the key appears once and providers stay shareable.

**Scope:** `~/.qwen/settings.json` is user-wide. `<project>/.qwen/settings.json` applies to one repo and **wins** over user scope. Use project scope to commit a team's model choice without committing secrets.

### The env-var route — and its trap

These variables exist and work:

```bash
export OPENAI_API_KEY=sk-workshop-change-me
export OPENAI_BASE_URL=http://127.0.0.1:4000/v1
export OPENAI_MODEL=local-chat
qwen --model local-chat
```

**The trap, verified by testing:** if `~/.qwen/settings.json` already contains `modelProviders` entries, those **take precedence and the env vars are ignored.** In testing, setting all three env vars and running `qwen` produced a reply from the *settings.json* provider — the stub endpoint the env vars pointed at received **zero requests**.

So the env-var route works on a fresh machine and silently stops working once you have a settings file. That is a confusing failure, because nothing tells you your variables were ignored.

**Rule: pick one.** If you have a `settings.json`, put your provider in it and stop exporting `OPENAI_BASE_URL`.

> There is no `qwen auth` command any more — it is marked *(removed)* in `qwen --help`. Authentication is configured through `settings.json` / env, not an interactive login flow.

---

## The context-window trap

This is the second setting that decides whether things work.

Qwen Code needs to know how large a model's context window is, to decide how much history to send and when to compact. It **infers that from the model name.** For names it recognises the guess is right. For `local-chat` — a name you invented — it has nothing to go on, and a wrong guess means requests that are too large, or history truncated far earlier than you expect.

Pin it explicitly:

```json
"generationConfig": {
  "contextWindowSize": 8192
}
```

**Match it to what llama.cpp actually has**, not what you wish it had. Remember from [chapter 2](02-llama-cpp.md#the-context--parallel-trap) that `-np 4` divides your `-c` by four. If you started llama.cpp with `-c 8192 -np 4`, the real per-request context is **2048**, and `contextWindowSize` should say 2048.

Getting this wrong does not produce a clear error. It produces an agent that forgets things. Set it deliberately.

---

## Run it

Interactive, in a project:

```bash
cd ~/my-project
qwen --model local-chat
```

One-shot from the shell (positional prompt defaults to one-shot):

```bash
qwen --model local-chat "Explain what this repo does"
```

Keep going interactively after a one-shot:

```bash
qwen -i --model local-chat "Refactor the auth module"
```

Switch model mid-session with `/model`, or ask what is configured with `/status`.

### Approval modes

How much freedom the agent has. Set with `--approval-mode`:

| Mode | Behaviour |
|------|-----------|
| `plan` | Analyse only. Will not modify files or run commands |
| `default` | Asks before file edits and shell commands |
| `auto-edit` | Approves file edits automatically, still asks for commands |
| `auto` | An LLM classifier approves safe actions, blocks risky ones |
| `yolo` | Approves everything |

```bash
qwen --approval-mode plan --model local-chat "How would you add tests to this?"
```

`-y` / `--yolo` is shorthand for `yolo`. **Read the warning it prints** — verified text:

> `Warning: running headless with --yolo / approval-mode=yolo and no sandbox. All tool calls (shell, write, edit) auto-execute at this process's privilege level.`

That is not boilerplate. In `yolo` mode an agent that misreads your intent can run any command as you. For the workshop, use `default` or `plan`. Use `yolo` only inside a container or on a scratch directory you do not care about.

Related:

```bash
--allowed-tools TOOL [TOOL...]     # bypass confirmation for these tools only
--sandbox CMD                      # run tool calls inside a sandbox
qwen sandbox CMD                   # inspect the sandbox backend
```

---

## MCP servers

MCP (Model Context Protocol) gives the agent tools from outside itself — a database, a documentation index, GitLab, Jira. This is how an agent reaches things that are not files in your repo.

### Add one

```bash
qwen mcp add <name> <commandOrUrl> [args...]
```

A stdio server (a command it launches):

```bash
qwen mcp add context7 npx -- -y @upstash/context7-mcp
```

An HTTP or SSE server (a URL):

```bash
qwen mcp add my-api https://mcp.example.com/sse \
  -H "Authorization: Bearer YOURTOKEN"
```

Full options, verified from `qwen mcp add --help`:

| Option | Meaning |
|--------|---------|
| `-s, --scope user\|project` | Where to save it. Default `user` |
| `-t, --transport stdio\|sse\|http` | Auto-detected from the URL if omitted |
| `-e, --env KEY=value` | Environment variables, repeatable |
| `-H, --header "Name: value"` | HTTP headers for sse/http, repeatable |
| `--timeout MS` | Connection timeout |
| `--trust` | Skip per-call confirmation in a trusted workspace |
| `--description TEXT` | Human-readable note |
| `--include-tools a,b` | Only expose these tools |
| `--exclude-tools a,b` | Hide these tools |
| `--oauth-client-id` / `--oauth-client-secret` / `--oauth-redirect-uri` | OAuth for authenticated servers |

### Manage them

```bash
qwen mcp list                 # what is configured
qwen mcp reconnect [name]     # retry a failed connection
qwen mcp approve [name]       # approve a pending server
qwen mcp reject  [name]
qwen mcp remove  <name>
```

Inside a session, `/mcp` shows live status and lets you call tools.

### Or edit the JSON directly

```json
"mcpServers": {
  "context7": {
    "command": "npx",
    "args": ["-y", "@upstash/context7-mcp"],
    "timeout": 30000,
    "trust": false
  }
}
```

> **A note for the workshop:** MCP servers are a second thing to install and debug on top of everything else. Get the local model working end to end *first*. Adding MCP before your model reliably answers a question means debugging two systems at once.

> **And a note on small models:** an MCP server exposes tools, and using tools means the model must emit correct structured calls. That is exactly what a 1.7B model is worst at. Expect to need a cloud model for MCP to be genuinely useful — see [Exercise 6](../exercises/README.md#exercise-6--point-an-agent-at-your-stack).

---

## Project context

Qwen Code reads markdown context files and injects them into every prompt:

- **`QWEN.md`** — project-level instructions, conventions, architecture notes. Commit this.
- **`~/.qwen/QWEN.md`** — user-wide preferences.

A good `QWEN.md` is short and factual: how to build, how to test, what conventions to follow, what not to touch. Small models especially benefit — it removes guesswork they cannot do themselves.

```markdown
# QWEN.md
Build: `npm run build`
Test:  `npm test` (single file: `npm test -- path/to/file.test.ts`)
Do not edit anything under `generated/`.
```

---

## Other subcommands worth knowing

From `qwen --help`:

| Command | Purpose |
|---------|---------|
| `qwen serve` | Run as an HTTP daemon with a browser UI — [chapter 8](08-qwen-serve.md) |
| `qwen mcp` | Manage MCP servers |
| `qwen extensions` | Manage extensions (bundles of context, commands, MCP servers) |
| `qwen sessions` | Manage saved sessions |
| `qwen review` | Run a code review non-interactively |
| `qwen hooks` | Manage lifecycle hooks |
| `qwen sandbox` | Inspect the sandbox backend, or run a command inside it |
| `qwen batch` | Run many independent requests through the DashScope Batch API |
| `qwen agents` | Join a coordinator as a runtime |
| `qwen channel` | Messaging channels (Telegram, Discord, …) |
| `qwen update` | Check for and install updates |

Session flags: `--session-id`, `--continue`, `--resume`, `--fork-session`.

---

## Honest expectations

A 1.7B model driving a coding agent is **not** a good experience, and pretending otherwise wastes the workshop.

What it will do: read files, attempt edits, produce plausible-looking but often wrong code, and fumble tool-call JSON.

What it will not do: reliably refactor across files, hold a long plan in context, or recover gracefully from its own mistakes.

That gap is the lesson. Run Exercise 6, then switch `--model` to `cloud-fast` and repeat the identical task. The difference is immediate and it is the clearest demonstration in the whole day of what model scale buys you — and therefore of when self-hosting is the right trade.

Where a local model in an agent *is* genuinely fine: small self-contained tasks, classification, extraction, summarisation, and anything where the data must not leave the machine.

---

## Common failures

| Symptom | Cause | Fix |
|---------|-------|-----|
| Env vars ignored | `settings.json` has `modelProviders` — it wins | Put the provider in settings.json |
| Agent forgets context early | `contextWindowSize` too small, or `-np` divided your `-c` | Pin it to the real per-request context |
| Requests rejected as too large | `contextWindowSize` larger than the server's `-c` | Lower it to match |
| `401` from the gateway | Key mismatch | `env.WORKSHOP_LITELLM_KEY` must equal `LITELLM_MASTER_KEY` |
| `404 model not found` | `id` does not match a LiteLLM `model_name` | Compare with `curl :4000/v1/models` |
| Malformed tool calls | Model too small | Use a cloud model for agentic work |
| Hangs at startup on a fresh machine | Waiting for interactive auth/setup | Configure settings.json first, or run in a real terminal |
| npm `EACCES` on global install | Bad npm prefix | Set `npm config set prefix ~/.npm-global` — do not `sudo` |

Full details in [troubleshooting.md](troubleshooting.md).

---

**Next:** [06 — OpenCode: a second agent, same backend](06-opencode.md)

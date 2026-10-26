# 8 — qwen serve: your agent as a service

`qwen` is a process you watch in a terminal. `qwen serve` is a **daemon you talk to** — with an HTTP API, a browser UI, durable sessions, and access from your phone.

There is a slide deck for this chapter: [`slides/qwen-serve.html`](../slides/qwen-serve.html). Open it in a browser; it needs no server and no internet.

> **Status:** the help text describes this as *"Stage 1 experimental: --http-bridge"*. The API surface is real and usable; the internals will move. Verified against Qwen Code **v0.25.1**.

---

## Start it

```bash
qwen serve
```

That is the whole thing on loopback. Defaults, straight from `qwen serve --help`:

| Flag | Default | Meaning |
|------|---------|---------|
| `--port` | `4170` | TCP port. `0` asks the OS for a free one |
| `--hostname` | `127.0.0.1` | Loopback → auth-free. Anything else → token required |
| `--web` | `true` | Serve the Web Shell UI. `--no-web` = API only |
| `--http-bridge` | `true` | Preheat the primary `qwen --acp` child |
| `--max-sessions` | `32` | Concurrent live sessions before `503` |
| `--event-ring-size` | `8000` | SSE replay ring depth per session |

Open the printed URL. You have a browser-based agent.

---

## What actually starts

```
browser (Web Shell)  ·  curl / script  ·  another qwen (--join)
                 │            │              │
                 └────────────┴──────────────┘
                              │
                    ┌─────────▼──────────┐
                    │    qwen serve      │  daemon on :4170
                    │  · HTTP API        │  bearer auth (non-loopback)
                    │  · Web Shell UI    │  CORS allowlist
                    │  · session store   │  SSE replay ring
                    └─────────┬──────────┘
                              │  --http-bridge (stage 1)
                    ┌─────────▼──────────┐
                    │  qwen --acp child  │  the real agent runtime
                    │  tools, MCP, skills│  one per session
                    └────────────────────┘
```

Stage 1 spawns a **child process per session**. The help text is explicit that *"Stage 2 native in-process mode is not yet implemented; this flag will become opt-in then."* Practical consequence: session count drives process count, which drives memory. More on that below.

---

## The security model — understand this one rule

> *"Loopback (127.0.0.0/8, localhost, ::1, [::1]) is auth-free; anything else requires a token (one is generated and printed when neither `--token` nor `QWEN_SERVER_TOKEN` supplies one)."*

So:

```bash
qwen serve                              # 127.0.0.1 — no token, only your machine can reach it
qwen serve --hostname 192.168.1.20      # LAN — token REQUIRED (generated if you do not supply one)
```

This is an agent that can read files, edit them, and run shell commands. Exposing it on a network without a token is not a small mistake.

**`--require-auth`** hardens the loopback case:

> *"Refuse to start without a bearer token, even on loopback. Hardens the loopback developer default for shared dev hosts / CI runners / multi-tenant workstations where any local user can hit 127.0.0.1."*

Use it on any machine with more than one user. Note that with it enabled, **`/health` also requires the token** — no loopback exemption — so container health checks must send the bearer too.

Related, and worth reading the fine print on:

| Flag | What it does |
|------|--------------|
| `--token` | Bearer token required on every request. Falls back to `QWEN_SERVER_TOKEN` |
| `--allow-origin` | Cross-origin allowlist. **Without it, browser clients get 403** on every request carrying an `Origin` header — which all browser POSTs do |
| `--tls-cert` / `--tls-key` | Serve HTTPS. Required for secure-context browser APIs (voice input / `getUserMedia`, WebRTC) over a LAN IP. Generate a local cert with `mkcert` |
| `--enable-session-shell` | Enables `POST /session/:id/shell` — **arbitrary command execution over HTTP**. Off by default. Leave it off |
| `--open` | Opens the Web Shell in a browser. *"The launch URL (token included) is handed to the browser launcher and is visible in the process list"* — so open it manually on a multi-user host |
| `--token-qr` | Print the token QR even when stdout is not a terminal. Withheld by default to keep stable credentials out of collected logs |

---

## Sharing to your phone: two ways, one real trade-off

### `--local-control` — ad-hoc

> *"Share the Web Shell on the local IPv4 network with its own revocable pairing token, terminal QR code, and best-effort sleep inhibition. Ctrl+C turns it off by ending the whole daemon; the Web Shell Settings card turns it off while the daemon keeps running."*

```bash
qwen serve --local-control
```

Scan the QR. Done. `--local-control-address` picks which IPv4 to share if you are on several networks.

**The catch:** the pairing token is minted in memory and revoked at stop. So it **rotates on every restart**, and every bookmarked URL breaks. Fine for a demo to a room; wrong for a setup you come back to.

### Static bind — persistent

```bash
qwen serve \
  --hostname 192.168.1.20 \
  --token "$(cat ~/.qwen-serve-token)" \
  --allow-origin http://192.168.1.20:4170
```

Now the token comes from you, so it **survives restarts**. Bookmark this once and it keeps working:

```
http://192.168.1.20:4170/#token=YOURTOKEN
```

Keep the token file private:

```bash
umask 077 && openssl rand -hex 32 > ~/.qwen-serve-token
```

**Rule of thumb:** ad-hoc demo → `--local-control`. Anything persistent → static bind.

### Making it survive logout

A foreground daemon dies when you close the terminal. On Linux, run it as a **systemd user** unit:

```ini
# ~/.config/systemd/user/qwen-serve.service
[Unit]
Description=Qwen Code daemon
After=network-online.target

[Service]
EnvironmentFile=%h/.qwen-serve-token-env
ExecStart=%h/.nvm/versions/node/v22.12.0/bin/qwen serve \
  --hostname 192.168.1.20 \
  --allow-origin http://192.168.1.20:4170
Restart=on-failure

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now qwen-serve
loginctl enable-linger $USER     # ← required for a USER unit to start at boot
```

Without `enable-linger`, a user unit only runs while you are logged in graphically.

> **Real gotcha, learned the hard way:** the unit's default `KillMode=control-group` means `systemctl --user restart qwen-serve` **also kills anything a session launched as a background task**, because those processes stay in the unit's cgroup even after their launching agent exits. Their `PPID` becomes `systemd --user`, which hides the membership — so a PPID check will not warn you. Read the `CGroup:` block of `systemctl --user status qwen-serve` before restarting.

---

## Durable sessions

The Web Shell talks to the daemon over **Server-Sent Events**. Drop the connection, reconnect, and it replays what you missed:

```
GET /session/:id/events
Last-Event-ID: 4182        ← resume from here
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--event-ring-size` | `8000` | How much history a reconnect can recover. Larger = more headroom, a few hundred KB extra RAM per session |
| `--compacted-replay-max-bytes` | `8388608` (8 MiB) | Cap on the compacted snapshot for `POST /session/:id/load` late attaches. Max 256 MiB |
| `--max-journal-events` | `10000` | Per-session cap on replay entries in the current unfinished turn |
| `--max-journal-bytes` | `8388608` | Same, in bytes. Per-session hard cap 256 MiB |

Pinning either `--max-journal-*` flag **disables adaptive growth**, which would otherwise raise caps when a turn outgrows them. Leave them alone unless you have a reason.

This is the feature that makes it feel like a service rather than a toy: refresh the page on your phone mid-run and you are back where you were.

---

## Limits — it refuses work rather than dying

| Flag | Default | Meaning |
|------|---------|---------|
| `--max-sessions` | `32` | Concurrent live sessions; beyond it new spawns get `503`. **Attaching to existing sessions still works** |
| `--max-total-sessions` | — | Same cap across *all* workspace runtimes |
| `--max-pending-prompts-per-session` | `5` | Queued prompts per session; excess get `503` |
| `--max-connections` | `256` | Listener-level TCP cap. Slow or phantom SSE clients are rejected at accept time |
| `--prompt-deadline-ms` | — | Server-side wallclock cap on `POST /session/:id/prompt`. Falls back to `QWEN_SERVE_PROMPT_DEADLINE_MS` |
| `--mcp-client-budget` | — | Cap on live MCP clients per workspace |
| `--mcp-budget-mode` | `warn` | `warn` (no refusal, status warns at ≥75%), `enforce` (refuses past the cap), `off` (observability only). **Boot rejects `enforce` without a budget** |

`0` disables a cap.

---

## Memory

Each session is a child process with its own V8 heap. On a 16 GB laptop that is the difference between a demo and a freeze.

| Flag | Meaning |
|------|---------|
| `--memory-budget-mb` | Total budget for the daemon **process tree**. Unset, derived as **50% of cgroup-constrained or host memory**, capped at available memory. Range 1024–1048576. Also sizes a daemon-wide pool of 5% of the budget (capped 1024 MB) for replay growth |
| `--memory-pressure-mode` | `observe` (default) reports the level and raises a status issue when it leaves normal; `off` reports figures but raises nothing. **"Nothing remediates in either mode."** |
| `--child-heap-mode` | `observe` (default) models a per-child partition and counts spawns that would have exceeded it; `admit` rejects starts past the limit; `enforce` is experimental |

Read the fine print on `--child-heap-mode`, because it is a genuine trap:

> *"a refusal count of 0 does NOT mean the partition would be safe to apply; children still run on the much larger host-derived ceiling, so a workload needing more old space than the modeled limit looks healthy here."*

For the workshop: set `--memory-budget-mb` to something sane and keep `--max-sessions` low.

```bash
qwen serve --max-sessions 4 --memory-budget-mb 4096
```

---

## Workspaces and multiple machines

### Several projects on one daemon

```bash
qwen serve --workspace /repos/api --workspace /repos/web
```

> *"Repeat to register isolated workspace runtimes; the first is primary. `POST /session` requests with a mismatched cwd return `400 workspace_mismatch`."*

It will not let a session wander into the wrong project. Omit `--workspace` and it defaults to the current directory.

`--memory-project-scope` picks how project memory is partitioned: `workspace` (default — each daemon workspace stays isolated) or `git-root` (legacy shared scope).

### Linking machines

| Flag | Purpose |
|------|---------|
| `--join LINK` | Join another Qwen Code as a runtime, using the one-line link from *Agent → Runtime → Add runtime* |
| `--agent-host-server` | Register this daemon as an Agent Host with a primary Qwen daemon |
| `--agent-host-workspace-id` | Control-plane workspace id printed by the primary daemon |
| `--agent-host-name` | Display name advertised for this Agent Host |
| `--agent-host-allow-http` | Allow unencrypted Agent Host HTTP outside loopback — *"trusted demo networks only"* |

Also: `--channel NAME` starts a daemon-managed channel worker (repeat it, or use `--channel all`) for messaging integrations.

These are powerful and **out of scope for the workshop**. Know they exist; do not teach them.

---

## API surface

The help text names these endpoints explicitly:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/health` | GET | Liveness. **Requires the bearer too when `--require-auth` is set** |
| `/session` | POST | Create a session. Mismatched `cwd` → `400 workspace_mismatch` |
| `/session/:id/prompt` | POST | Send a prompt. Bounded by `--prompt-deadline-ms` |
| `/session/:id/events` | GET | SSE stream; reconnect with `Last-Event-ID` |
| `/session/:id/load` | POST | Late attach; returns a compacted replay snapshot |
| `/session/:id/shell` | POST | Direct shell execution. **Only with `--enable-session-shell`**, and each call still needs a session-bound client id |
| `/workspace/mcp` | GET | Reports MCP state, including `clientCount` |
| `/workspace/auth/provider` | POST | Install a provider auth config. Needs `--allow-private-auth-base-url` for localhost/private-network `baseUrl` values |

Beyond those, run it and read what it prints — the daemon reports its own endpoints at startup, and `qwen serve --help` is unusually thorough. Do not script against an endpoint you have not confirmed.

Note `--allow-private-auth-base-url`:

> *"Allow /workspace/auth/provider to install localhost/private-network baseUrl values. Use only for local development with trusted clients."*

That flag exists precisely so you can point the daemon's own agent at your self-hosted LiteLLM. It is off by default for good reason.

---

## Other flags worth knowing

| Flag | Purpose |
|------|---------|
| `--profile default\|hosted-harness` | `hosted-harness` enables a private, no-tool Managed Session API **on loopback only** |
| `--experimental-lsp` | Forward the experimental LSP opt-in to spawned sessions |
| `--experimental-paired-engines` | Build workspace runtimes with paired Legacy and Managed engines. *"No Managed engine is available yet, so sessions run on Legacy"* |
| `--restore-ask-user-question` | On resume, re-hang a trailing unanswered question instead of synthesising a failed tool result |
| `-d, --debug` | Debug mode |
| `--bare` | Skip implicit startup auto-discovery; honour only explicit CLI inputs |
| `--safe-mode` | Disable **all** customizations — context files, hooks, extensions, skills, MCP. The first thing to try when something behaves strangely |
| `--insecure` | Skip TLS verification. Equivalent to `QWEN_TLS_INSECURE=1`. The help text warns it *"removes protection against man-in-the-middle attacks"* |

`--safe-mode` is genuinely useful: if the daemon misbehaves, starting it with every customization disabled tells you in one step whether your config is the cause.

---

## Recipes

**1 · Local development**

```bash
qwen serve
```

**2 · Phone on the same Wi-Fi, ad-hoc**

```bash
qwen serve --local-control      # prints a QR — scan it
```

**3 · Phone, persistent across restarts**

```bash
qwen serve \
  --hostname 192.168.1.20 \
  --token "$(cat ~/.qwen-serve-token)" \
  --allow-origin http://192.168.1.20:4170
```

**4 · Shared dev box or CI**

```bash
qwen serve --require-auth --no-web --max-sessions 4 --memory-budget-mb 4096
```

**5 · Pointing the daemon at your self-hosted stack**

The sessions it spawns use your normal Qwen Code configuration, so the `settings.json` from [chapter 5](05-qwen-code.md) applies unchanged. Serving on a LAN and needing a private `baseUrl` is what `--allow-private-auth-base-url` is for.

---

## Demo script

Six beats, none needing a GPU or a cloud account:

1. **Start it.** `qwen serve` — note the printed URL, and that loopback needed no token.
2. **Open the Web Shell.** Start a session against your local model.
3. **Kill the network.** Turn off Wi-Fi mid-run, reconnect, watch the SSE ring replay what you missed.
4. **Phone.** Re-run with `--local-control`, scan the QR, drive the same daemon from a handset.
5. **Prove the auth model.** Re-run on a LAN IP; show `401` without `Authorization`, then success with it.
6. **Show the ceiling.** `--max-sessions 2`, open a third, read the `503`.

---

## What to teach, and what to skip

| Teach | Skip |
|-------|------|
| Loopback vs LAN auth model | `--profile hosted-harness` and capability digests |
| Web Shell and phone access | Agent Host control-plane wiring |
| SSE replay surviving a refresh | `--experimental-paired-engines` |
| `--max-sessions` returning `503` | `--child-heap-mode enforce` |
| `--workspace` isolation | `--enable-session-shell` |
| `--local-control` QR pairing | Journal byte-cap tuning |

The left column is durable and easy to demonstrate. The right column is private, experimental, or explicitly documented as not-yet-implemented — teaching it means teaching something that will not survive to next semester.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `403` on every browser request | `Origin` not allowlisted | Add `--allow-origin http://IP:PORT` |
| `401` | Missing bearer token | Send `Authorization: Bearer TOKEN` |
| Refuses to start on a LAN IP | No token available | Pass `--token` or set `QWEN_SERVER_TOKEN` |
| Voice input does not work over LAN | Not a secure context | Serve HTTPS with `--tls-cert` / `--tls-key` (use `mkcert`) |
| Bookmarked phone URL broke | You used `--local-control`; its token rotates on restart | Switch to a static `--token` |
| Machine gets slow with many sessions | One child process per session | Lower `--max-sessions`, set `--memory-budget-mb` |
| Weird behaviour you cannot explain | A customization is interfering | Restart with `--safe-mode` |
| Restart killed unrelated processes | `KillMode=control-group` sweeps the unit cgroup | Check the `CGroup:` block of `systemctl --user status` first |
| Unit does not start at boot | Linger is off | `loginctl enable-linger $USER` |

---

**Back to:** [the README](../README.md) · **Slides:** [slides/qwen-serve.html](../slides/qwen-serve.html)

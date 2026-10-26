# 0 — Prerequisites

Do this **before** the workshop. Setup on the day eats the session; setup at home costs you nothing.

Everything here is free. Total download: roughly 2–4 GB, plus whatever models you pull later.

---

## Checklist

Tick these off. Each one has a verify command — if the verify command works, you are done with that step.

| # | Tool | Why you need it | Verify with |
|---|------|-----------------|-------------|
| 1 | A terminal you are comfortable in | Every tool in this workshop is a CLI | `echo $SHELL` |
| 2 | Git | You clone this repo and push your exercises | `git --version` |
| 3 | Docker | LiteLLM runs in a container | `docker run --rm hello-world` |
| 4 | Node.js ≥ 22 | Qwen Code and OpenCode are Node CLIs | `node --version` |
| 5 | **llama.cpp** | The inference engine. The hands-on cannot start without it | `llama-server --version` |
| 6 | **llama-swap** | Puts several models behind one port | `llama-swap --version` |
| 7 | An editor | VS Code or IntelliJ | open one |
| 8 | ~10 GB free disk | Model weights are the big item | see below |

---

## 1. Terminal / command line

You will paste a lot of commands. Learn these five things and you are fine:

- `cd` / `pwd` / `ls` — move around and look
- `Tab` — autocompletes filenames, use it constantly
- `Ctrl-C` — kills the foreground process (your model server, mostly)
- `↑` — previous command
- `command --help` — every tool in this workshop has one

**Windows users:** do *not* use PowerShell or CMD for this workshop. Use **WSL2** (below). Every command in these docs is written for a POSIX shell, and half of them will not work in PowerShell.

### Windows: install WSL2

Open PowerShell **as Administrator** and run:

```bash
wsl --install
```

Reboot when it asks. Then launch "Ubuntu" from the Start menu, and create the username/password it prompts for. From here on, "your terminal" means that Ubuntu window.

Verify:

```bash
uname -a        # should say Linux ... microsoft-standard-WSL2
lsb_release -d  # should say Ubuntu 22.04 or 24.04
```

> **WSL2 and USB sticks / external drives:** Windows drives are mounted under `/mnt/c`, `/mnt/d`, etc. Reading a model off a USB stick means pointing at something like `/mnt/d/models/`.

### Give WSL2 enough memory (Windows only, important)

WSL2 by default takes only *half* your RAM, and Docker takes a slice of that. On a 16 GB laptop that leaves too little for a model. Create `%UserProfile%\.wslconfig` (that is `C:\Users\YOURNAME\.wslconfig`) containing:

```ini
[wsl2]
memory=12GB
swap=8GB
processors=8
```

Then restart WSL from PowerShell:

```powershell
wsl --shutdown
```

Verify from inside Ubuntu:

```bash
free -h    # 'total' should be near 12Gi
nproc
```

---

## 2. Git

**macOS:**

```bash
xcode-select --install    # skip if already installed
git --version
```

**Ubuntu / WSL2:**

```bash
sudo apt update && sudo apt install -y git
git --version
```

**Windows (native, only if you refuse WSL2):** download from <https://git-scm.com/download/win>.

Then set your identity — commits are attributed to this, so make it real:

```bash
git config --global user.name "YOUR NAME"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
git config --global pull.rebase false
```

Create a free GitHub account at <https://github.com/signup> if you do not have one. You will need it for the exercises.

### Clone this repo

```bash
git clone https://github.com/darius-f96/mhp-ubb-ai-workshop.git
cd mhp-ubb-ai-workshop
ls
```

You should see `README.md`, `docs/`, `configs/`, `scripts/`, `slides/`, `exercises/`.

---

## 3. Docker

Docker runs the LiteLLM proxy and (for the demo) vLLM. You need a working `docker` command in the same terminal where you will do the exercises.

### macOS

Two options — pick **one**:

**Docker Desktop** (easiest, GUI): download from <https://www.docker.com/products/docker-desktop/>. On Apple Silicon choose the "Mac with Apple chip" build. Launch it once and leave it running.

**Colima** (free, no GUI, lighter — good if Docker Desktop's licence is a problem):

```bash
brew install colima docker docker-compose
colima start --cpu 4 --memory 8
```

Colima needs starting after every reboot: `colima start`.

### Windows (WSL2)

Install **Docker Desktop for Windows** from <https://www.docker.com/products/docker-desktop/>. During install, make sure **"Use WSL 2 based engine"** is selected. After install:

- Settings → Resources → WSL Integration → enable your Ubuntu distro.
- Give Docker Desktop at least 8 GB: Settings → Resources → Advanced → Memory.

Then `docker` works *inside your Ubuntu terminal* — you do not install Docker a second time in WSL.

### Linux

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
```

**Log out and back in** for the group change to apply. Then you can run `docker` without `sudo`.

### Verify (all platforms)

```bash
docker --version
docker compose version
docker run --rm hello-world
```

All three must succeed. If the last one says `permission denied`, you are not in the `docker` group — log out and back in.

### Check Docker's memory ceiling

This decides how big a model you can serve. From your terminal:

```bash
docker info --format '{{.MemTotal}}' | awk '{printf "%.1f GB\n", $1/1024/1024/1024}'
```

You want **≥ 6 GB**. If it is lower, raise it (Docker Desktop → Settings → Resources → Memory; Colima → `colima stop && colima start --memory 8`).

---

## 4. Node.js ≥ 22

Qwen Code and OpenCode are Node CLIs. **Qwen Code requires Node >= 22** (verified from the package's own `engines` field), so 20 is not enough.

Check first — you may already have it:

```bash
node --version
```

If that prints `v22.x` or higher, skip ahead.

**macOS / Linux (recommended — nvm):**

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
```

Close and reopen your terminal, then:

```bash
nvm install 22
nvm use 22
node --version
```

**Ubuntu / WSL2 (apt):**

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
node --version
```

**Windows:** install Node 22 LTS from <https://nodejs.org/> — but again, prefer doing everything inside WSL2.

Verify npm came with it:

```bash
npm --version
```

---

## 5. llama.cpp

This is the inference engine — the layer that does the actual matrix multiplication. **The hands-on block cannot start without it**, and building from source in a room of thirty people is how a 45-minute session becomes a two-hour one. Do it at home.

**macOS (Homebrew):**

```bash
brew install llama.cpp
llama-server --version
```

Apple Silicon gets Metal support in this build, so models offload to the GPU automatically.

**Ubuntu / WSL2 — build from source** (there is no good apt package):

```bash
sudo apt update && sudo apt install -y build-essential cmake git
cd ~                                    # ← build in HOME, not inside the workshop repo
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build
cmake --build build --config Release -j"$(nproc)"
```

A few minutes. Then put the binaries on your PATH:

```bash
echo 'export PATH="$HOME/llama.cpp/build/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

> **Build it in `~`, not inside `mhp-ubb-ai-workshop/`.** Cloning it into the workshop repo nests a second Git repository inside the one you commit your exercises to, and your `git status` will be noise for the rest of the day.

**Verify (all platforms):**

```bash
llama-server --version
```

You should see a build number, for example `version: 9761 (721354fbd)`. Write it down — behaviour differs between builds and instructors will ask. Full install paths for other platforms, plus the flag reference: [02-llama-cpp.md](02-llama-cpp.md).

---

## 6. llama-swap

One Go binary that puts several models behind one port. You need it for the second half of the hands-on.

**macOS / Linux (Homebrew):**

```bash
brew tap mostlygeek/llama-swap
brew install llama-swap
```

**Any OS — pre-built binary** (~24 MB, no build step):

```bash
curl -L -o /tmp/llama-swap.tar.gz \
  https://github.com/mostlygeek/llama-swap/releases/download/v267/llama-swap_267_linux_amd64.tar.gz
tar xzf /tmp/llama-swap.tar.gz -C /tmp
sudo mv /tmp/llama-swap /usr/local/bin/
```

macOS Apple Silicon uses `darwin_arm64`, macOS Intel `darwin_amd64`, Windows `windows_amd64.zip`. The full asset table is in [03-llama-swap.md](03-llama-swap.md#install).

**Verify:**

```bash
llama-swap --version
```

> llama-swap ships releases weekly, so do not worry about having the newest. Anything **v252 or newer** supports `--validate`, which the workshop uses.

---

## 7. An editor

**VS Code** (recommended) — <https://code.visualstudio.com/>. Then, so you can edit files inside WSL2 or a remote box:

```bash
code --install-extension ms-vscode-remote.remote-wsl
code --install-extension ms-azuretools.vscode-docker
```

From inside WSL2, running `code .` in a folder opens VS Code on your Windows desktop pointed at that folder. That is the workflow you want.

**IntelliJ IDEA** — Community Edition is free: <https://www.jetbrains.com/idea/download/>.

Either is fine. You mostly need to edit YAML and JSON without a fight, so install a YAML extension if your editor does not ship one.

---

## 8. Disk space

```bash
df -h .
```

You want **10 GB free** in your home directory. Model weights dominate:

| What | Size |
|------|------|
| Docker images (LiteLLM) | ~1.5 GB |
| llama.cpp build or binary | ~100 MB |
| The workshop model set (core) | ~2.6 GB |
| Headroom for experiments | ~3 GB |

See [models.md](models.md) for exactly what to download and how big each file is.

---

## Optional but recommended

**Homebrew (macOS, and Linux too)** — makes installing llama.cpp a one-liner:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew --version
```

**`curl` and `jq`** — used throughout for API calls:

```bash
# macOS
brew install jq
# Ubuntu / WSL2
sudo apt install -y curl jq
jq --version
```

---

## When something fails

Do not sit silently for ten minutes. In order:

1. Re-read the error. The last three lines usually say what is wrong.
2. Check the obvious: is Docker running? Are you in the right directory? Did you paste the whole command?
3. Look it up in [troubleshooting.md](troubleshooting.md).
4. Ask your neighbour, then ask an instructor.

A useful habit — check what you actually have installed:

```bash
for t in git docker node npm jq curl; do printf '%-8s ' "$t"; command -v $t >/dev/null && $t --version 2>&1 | head -1 || echo "MISSING"; done
```

---

**Next:** [01 — What you are actually building](01-concepts.md)

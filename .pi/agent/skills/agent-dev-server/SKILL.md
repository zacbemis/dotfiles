---
name: agent-dev-server
description: Host toolset inventory, container isolation (`agent-container-run`, Docker, devcontainers), language SDKs, Playwright/Xvfb browser testing, database clients, and host operating/security rules for the agent development server. Read when running containers, browser tests, native toolchains, database clients, or checking host capabilities and provisioning flags.
---

# Agent Development Server Guide

This host is intended for coding-agent development, builds, automated tests, browser testing, and clean evaluation of changes. The provisioning script is:

- `/home/zacb/agent-dev/setup-agent-dev-server.sh`

The inventory below describes the expected default toolset **after that script has completed successfully**. Optional tools and settings are marked explicitly.

## Operating rules

1. Read the nearest repository-specific `AGENTS.md` and project documentation before changing code.
2. Keep changes inside the requested workspace. Do not alter host configuration, global packages, services, firewall rules, credentials, or other repositories unless explicitly asked.
3. Treat repository scripts, dependencies, Git hooks, CI files, MCP tools, and downloaded code as potentially untrusted.
4. Never print, copy, commit, or expose secrets, `.env` contents, authentication files, SSH material, browser profiles, or API tokens.
5. Do not mount `/var/run/docker.sock`, `$HOME`, `~/.ssh`, cloud credentials, or agent credentials into containers.
6. Never use `--privileged`, host PID/network namespaces, or added Linux capabilities unless the user explicitly approves and the test requires them.
7. Bind development servers to `127.0.0.1` by default. Do not use `0.0.0.0` merely for convenience.
8. Prefer project lockfiles and local dependencies over global tools. Do not update lockfiles unless dependency changes are part of the task.
9. Do not invoke `/usr/sbin/lxc` merely to check its version. Ubuntu's `lxd-installer` wrapper can automatically install the LXD Snap.
10. Docker group access to the rootful daemon is effectively root access. Use it only for trusted project operations.

## Recommended agent workflow

1. Inspect the repository, manifests, lockfiles, existing tests, and CI configuration.
2. Record the initial Git status and avoid overwriting unrelated user changes.
3. Use the runtime version pinned by the project (`global.json`, lockfile, opam switch, tool-version file, devcontainer, etc.).
4. Install dependencies with frozen/reproducible commands where supported.
5. Run the smallest relevant checks first, then the complete project suite.
6. For untrusted builds or dependency scripts, prefer a devcontainer or `agent-container-run`.
7. Evaluate final changes in a clean worktree/container when practical.
8. Preserve useful reports, traces, logs, and benchmark output under `~/agent-dev/agent-runs/`; do not commit them unless requested.
9. Report commands run, failures, skipped checks, environmental limitations, and generated artifacts.

## Isolation and containers

`agent-container-run` is installed as a safer Docker wrapper:

```bash
# No network by default
cd /path/to/repository
agent-container-run IMAGE COMMAND ARG...

# Explicitly allow ordinary bridge-network egress
agent-container-run --network IMAGE COMMAND ARG...
```

It uses a read-only container root, an ephemeral home and `/tmp`, a writable mount of only the current directory, no Docker socket, no host home/credentials, dropped capabilities, `no-new-privileges`, and CPU/memory/PID limits. It will not pull missing images automatically; pull and preferably verify/pin an image digest before invoking it.

Use project devcontainers where available:

```bash
devcontainer up --workspace-folder .
devcontainer exec --workspace-folder . COMMAND
```

Rootless Docker is supported by the provisioning script but is not enabled by default because it can affect existing Testcontainers/rootful workflows. Enable it with `CONFIGURE_ROOTLESS_DOCKER=1`; remove rootful Docker-group access with `REMOVE_ROOTFUL_DOCKER_ACCESS=1` only after validating compatibility.

## Available tools after default provisioning

### Core shell and collaboration

- Shells/session tools: `bash`, `zsh`, `tmux`, `screen`
- Editors/agents: `nvim`, `vim`, VS Code Server (`code`), Cursor Agent, pi
- Source control: `git`, `git-lfs`, GitHub CLI (`gh`)
- Search/data: `rg`, `jq`, `yq`, `xmlstarlet`, `file`
- Network/API: `curl`, `wget`, `http`, `ssh`, `openssl`, `socat`, `nc`, `dig`, `host`, `nslookup`
- File/archive: `rsync`, `zip`, `unzip`, `7zz`
- Task/environment tools: `just`, `direnv`, `entr`, `hyperfine`

Git identity and GitHub authentication are not fabricated by the script. Configure them explicitly when needed:

```bash
git config --global user.name "NAME"
git config --global user.email "EMAIL"
gh auth login
```

### Native development

- GCC/G++ 15
- Clang/Clang++ and LLVM 21, including Clang tools
- GNU Make, CMake/CTest, Ninja, Meson
- Autoconf, Automake, Libtool, `pkg-config`, `ccache`
- Common OpenSSL, SQLite, compression, FFI, and readline development headers
- Debugging/profiling: `gdb`, `lldb`, `valgrind`, `strace`, `ltrace`, `perf`, `bpftrace`

### JavaScript and TypeScript

- Node.js 24 through NVM
- npm and Corepack
- Pinned Corepack shims for pnpm and Yarn
- Dev Containers CLI (`devcontainer`)
- Shared Playwright package in `/home/zacb/agent-dev/node_modules`
- Shared Playwright CLI: `~/.local/bin/playwright` (or `~/agent-dev/node_modules/.bin/playwright`)
- For shared-tool imports, use the absolute package path; project tests should declare their own Playwright dependency. Do not install packages directly in `~/`.

Use the package manager indicated by the project lockfile:

```bash
npm ci
pnpm install --frozen-lockfile
yarn install --immutable   # when supported by the project's Yarn version
```

ESLint, TypeScript, Vitest, Jest, Cypress, and similar project tools should normally be declared and pinned in each project's `package.json`, not installed globally.

### Python

- System Python 3.14
- `pip`, `venv`, `pipx`
- System testing tools: `pytest`, `coverage`, `tox`
- Isolated pinned CLIs: `uv`, `ruff`, `mypy`, `nox`, `pip-audit`, `pre-commit`
- Existing standalone Python 3.11 remains available at `~/.local/bin/python3.11`

Prefer a project environment:

```bash
uv sync --frozen                 # for a uv-locked project
python3 -m venv .venv            # otherwise
. .venv/bin/activate
python -m pip install -r requirements.txt
python -m pytest
```

Do not install project packages into Ubuntu's externally managed system Python.

### Other language SDKs

Installed by the script's default `INSTALL_EXTRA_LANGUAGES=1` setting:

- .NET SDK 10.0.302 in `~/.dotnet`
- OpenJDK 21 (`java`, `javac`)
- Go (`go`)
- Rust stable through `rustup` (`rustc`, `cargo`)
- Ruby (`ruby`, `gem`, Bundler when supplied by the Ruby packages)
- PHP CLI and Composer
- OCaml and opam

Use repository-pinned versions and dependency locks where available. Do not replace a project's selected opam switch or .NET feature band without approval.

### Containers and reproducible environments

- Docker Engine and CLI
- Docker Compose v2 (`docker compose`)
- Docker Buildx (`docker buildx`)
- Dev Containers CLI
- `agent-container-run` hardened helper
- Rootless Docker prerequisites: `uidmap`, `slirp4netns`, `fuse-overlayfs`, `rootlesskit`

Database servers, queues, and external service dependencies should usually be disposable Compose/Testcontainers services rather than persistent host daemons. Always use dynamically mapped ports where the test framework supports them.

### Database clients

- SQLite CLI (`sqlite3`)
- PostgreSQL client (`psql`, `pg_isready`)
- MySQL client (`mysql`)
- Redis client (`redis-cli`)

No persistent PostgreSQL, MySQL, or Redis server is installed by default.

### Browser, UI, media, and visual testing

- Playwright Chromium, Firefox, and WebKit matching the installed Playwright CLI
- Xvfb, Openbox, X11 utilities, `xdotool`, `scrot`
- ffmpeg and ImageMagick (`convert`/`magick` as packaged)
- Mesa/Vulkan diagnostic tools
- ALSA and PulseAudio utilities
- Liberation, Noto Emoji, Unifont, and FreeFont font coverage

For each project, install browsers from that project's locked Playwright version when versions differ:

```bash
npx playwright install --with-deps
```

For CI-like runs, start with one Playwright worker for stability and reproducibility. Retain HTML/JUnit reports and traces on failure. The official Playwright container image tag should match the project's Playwright version exactly.

A headed X11 session can be created when needed:

```bash
xvfb-run -a -s '-screen 0 1440x900x24' COMMAND
```

Do not use a root-run browser for crawling untrusted websites. Use a non-root container user and an appropriate Chromium seccomp profile.

### Testing, linting, and benchmarking

Host-level tools include:

- `pytest`, Coverage.py, tox, nox
- Ruff, mypy, pip-audit, pre-commit
- ShellCheck, shfmt, Bats
- CTest, GDB, LLDB, Valgrind
- Playwright browser matrix
- `wrk` and `hyperfine`

Framework-specific tools such as Vitest, Jest, xUnit, NUnit, Go test dependencies, Cargo test dependencies, and Testcontainers libraries belong in the project manifest.

### Documentation and code generation

- Graphviz
- Protocol Buffers compiler (`protoc`)
- ffmpeg
- ImageMagick

## Optional provisioning features

These require flags when running `/home/zacb/agent-dev/setup-agent-dev-server.sh`:

- `INSTALL_VM_MOBILE_TOOLS=1`: QEMU x86, QEMU utilities, ADB, Fastboot, and Java. This is not a complete Android SDK/emulator installation.
- `CONFIGURE_ROOTLESS_DOCKER=1`: configure the per-user rootless Docker daemon/context.
- `REMOVE_ROOTFUL_DOCKER_ACCESS=1`: remove the user from the root-equivalent `docker` group after rootless setup.
- `HARDEN_SSH=1`: key-only SSH, no root login, no gateway ports, local forwarding retained.
- `ENABLE_UFW=1`: default-deny inbound firewall with OpenSSH allowed.
- `ALLOW_UNPRIVILEGED_USERNS=1`: disable Ubuntu's AppArmor user-namespace restriction. This weakens isolation and should remain off unless required.
- `RELAX_NATIVE_DEBUG_SECURITY=1`: relax ptrace restrictions and permit core dumps. This weakens security and should remain off unless required.
- `REMOVE_ACCIDENTAL_LXD=1`: remove the LXD/core26/snapd snaps installed during the earlier audit.
- `REBOOT_NOW=1`: reboot automatically after provisioning.

## Resource and server conventions

- Keep generated dependency/build directories out of broad file watchers before requesting higher limits.
- Default configured inotify maxima: 524288 watches, 1024 instances, 32768 queued events.
- The server uses UTC and `en_US.UTF-8`; tests requiring other locales must provision them explicitly.
- Hardware KVM and AMD GPU devices exist. The provisioning script adds the user to `kvm`, `video`, and `render`; logout/reboot is required before access is effective.
- Keep long-running development services supervised and private. Use SSH local forwarding for access rather than public wildcard binds.
- Persistent self-hosted CI runners must not execute untrusted public pull requests. Prefer disposable/ephemeral runners and independent clean evaluation.

## Research basis

The server policy follows guidance from Docker Sandboxes and Docker rootless/security documentation, OWASP Docker Security, Playwright CI/container documentation, Development Containers, VS Code Remote SSH, GitHub Actions security guidance, and SWE-bench's containerized evaluation model. Key themes are disposable isolation, least privilege, no host Docker socket exposure, version pinning, clean evaluators, restricted service exposure, and retained test artifacts.

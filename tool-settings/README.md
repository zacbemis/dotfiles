# Tool settings

Reviewed preferences and integration sources, not accounts or application backups.
`manifest.json` lists managed files; unlisted siblings stay untouched.

## Features

- Herdr configuration, keybindings, wallpaper colors and agent hooks.
- Claude Code, Pi, Codex, Cursor, Copilot, OpenCode and Antigravity preferences.
- VS Code/Cursor settings, keybindings, snippets and extension lists.
- GitHub CLI and htop preferences.
- Allowlisted snapshots for tools that mix preferences with private state.
- Relative, Stow-compatible links with private backups of replaced files.
- Credential guards; auth, sessions, trust, caches and downloaded packages stay local.

## Commands

Run from the repository root:

```bash
python3 scripts/tool-settings.py status
python3 scripts/tool-settings.py link
```

Backups go under `${XDG_STATE_HOME:-~/.local/state}/dotfiles-tool-settings/`.
Install applications and sign in separately.

For selective deployment on a development server, pass managed paths explicitly:

```bash
python3 scripts/tool-settings.py link --only .zshenv .zshrc .p10k.zsh .bashrc .bash_profile .config/herdr/config.toml
```

Repeat with the other terminal/agent files needed on that host. This leaves desktop
settings and server-specific agent instructions untouched. Neovim is separate from
the manifest; an existing `~/.config/nvim` link to this repo stays current automatically.
Zsh respects `NVM_DIR`, otherwise checks the XDG/Arch location then `~/.nvm`, and
preserves SSH-forwarded agents. Bash login retains the host's `~/.profile` SDK setup.

Filtered preferences are captured/restored explicitly, never by the desktop installer:

```bash
python3 scripts/tool-settings.py capture-preferences
# Review snapshots before restoring:
python3 scripts/tool-settings.py apply-preferences
```

Restores preserve unrelated JSON state and leave existing Codex TOML untouched.
**The captured Cursor CLI preferences disable sandboxing and use unrestricted approvals.**
Review before applying; credentials and trust decisions are not exported.

## Pi thread handoffs

Ask Pi to find another thread, hand it work, or bring back its reply. Ask for a visible Herdr tab or a standalone background Pi when you want a new thread. Native handoffs work inside or outside Herdr. The two mailboxes keep requests and replies in a private SQLite database at `~/.pi/agent/remote-thread-state/` (not synced by dotfiles; requires Node 22.13+). A known offline thread can still receive a queued request: if the machine is unreachable, the sender retries when running, including after resuming the same session. The receiver runs queued work when that same saved Pi session is open and idle. Requests that were already running when Pi stopped are reported as interrupted, not rerun.

`send` and `reply` always wait up to 38 seconds for that receipt to reach a terminal state, including time spent retrying delivery. Use `receipts` for a nonblocking progress check. A timeout or interruption does not cancel the work. A native result that did not arrive inline starts a new turn when the same saved sender session is open and idle in TUI or RPC mode. Keep the receipt and end the turn if there is no independent work left; don't poll or resend. This follows [T3 Code's wait and completion-wake pattern](https://github.com/pingdotgg/t3code/blob/eb90b7921721217b26282ca4bab628976a00c1af/docs/orchestration-v2/orchestrator-mcp-server.md).

Open each target Pi session at least once with the extension and discover it from the sending machine while reachable. Use the same saved session to receive its pending work; opening another thread in the same pane won't receive it. Standalone background workers shut down after 15 minutes idle and resume the same saved session when new work is queued and the receiving machine is reachable. Interactive sessions aren't relaunched automatically. A new worker can be launched with an exact model and thinking level. Bash calls inside handoffs have a five-minute ceiling.

After updating the extension, restart any Pi session that still reports “Pi did not register” after about 15 seconds. An older in-memory launcher can be incompatible with the updated worker on disk. Check discovery before retrying.

Each machine keeps its own `~/.pi/agent/remote-thread.json` (not managed by this repo). Map friendly names to a verified SSH alias or `user@host`, or to `null` for a name for the current machine. A link can be bidirectional with one SSH login: `{ "laptop": { "ssh": "user@laptop", "offer": "home" } }` on home and `{ "home": { "via": "home" } }` on the laptop. This opts in to a per-user SSH reverse Unix socket, not a public port. Configure it only between devices you trust to run work as your account. SSH must already work noninteractively and the Pi extension plus Node must be available on both endpoints. If SSH reauthentication is needed, the cross-machine link is unavailable until the user's access is restored. Local messaging doesn't need SSH or Herdr.

A handoff can attach one requested artifact inside the sender's workspace, up to 1 MiB. Native attachments are saved with the request so they can be delivered later. An idle Herdr pane without the extension remains discoverable as a live-only fallback. It cannot wake the sender automatically. Its wait looks for a reply tagged with the receipt rather than treating an idle pane as completion; if the pane blocks for input, resolve that in Herdr and check the same receipt.

## Optional dependencies

- Herdr shortcut helper (Rust/Cargo 1.89+):
  `cargo install --path tools/herdr-control --locked --root "$HOME/.local" --force`.
  Required for Alt+N and Alt+Shift+H/J/K/L; see [behavior and tests](../tools/herdr-control/README.md).
- OpenCode plugin: `npm install --prefix ~/.config/opencode`.
- Claude plugin: `claude plugin install clangd-lsp@claude-plugins-official`.
- Editor extensions: `xargs -r -n 1 code --install-extension < tool-settings/vscode-extensions.txt`
  (use `cursor` and `cursor-extensions.txt` for Cursor).

These commands download third-party code. Herdr hooks are source snapshots;
upgrade integrations separately and review the resulting changes.

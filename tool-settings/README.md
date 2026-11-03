# Tool settings inventory

Audited against the local machine on 2026-11-03. This is a preferences/source backup,
not a backup of accounts, conversations, workspaces or installed applications.
`manifest.json` lists the explicitly managed files; no tool directory is copied wholesale.

## Coverage

| Tool | Tracked | Deliberately local |
|---|---|---|
| Herdr | Config, keys, wallpaper color helpers; agent integration source snapshots | Sockets, logs, session layout/snapshots, release metadata |
| Claude Code | Model/effort, theme, Vim mode, enabled plugin, `CLAUDE.md`, session hook and script | `.credentials.json`, root `.claude.json` account/cache/trust state, projects/history, cloud-synced skills and plugin downloads |
| Pi | Agent settings/packages, multi-pass, web settings, unchanged Herdr extension | Auth, model discovery cache, trust, conversations, npm/git installations and provider sessions |
| Codex | Model/reasoning/features in `codex.json`; session hook config and script | Existing `config.toml` project trust, hook approvals, onboarding, auth, SQLite databases and sessions |
| Cursor editor | Editor settings/keybindings, current `.cursor` session hook/script, extension IDs | Editor storage, account state, downloaded extensions/plugins |
| Cursor CLI | Allowlisted preferences in `cursor-cli.json`; launch options in `cursor-argv.json` | Login/auth metadata, model/cache history, crash-reporting instance ID, chats and sandbox policy state |
| Copilot CLI | Effort setting and session hook/script | `config.json` **contains login tokens**, chats, logs and runtime state |
| OpenCode | Config, TUI plugin declaration, pinned plugin dependency, both Herdr plugin sources | node_modules, caches, lock/runtime state and credentials |
| Antigravity CLI | Model and telemetry preference in `antigravity-cli.json` | Trusted workspaces, auth/ACP settings, machine hostname, databases/history |
| VS Code | User settings, keybindings, Java snippets, extension IDs | Profiles directory was empty; user/workspace storage, sync and extension binaries stay local |
| GitHub CLI | Protocol, alias and presentation preferences | `hosts.yml` / OAuth credentials |
| htop | Display, columns, sort and meter preferences | Process/runtime state |
| Shell, Git, Neovim, Kitty, desktop | Existing configs remain tracked in their normal locations | Shell history, SSH host topology/keys and runtime-generated palettes |

Provider-bundled skills, downloaded marketplaces and Claude's account-synced skill
bucket are not vendored. The locally maintained `skills/system/run-workflow` is
already tracked. Browser/Electron application profiles and password stores are not
part of this public settings backup.

## Restore or check links

Install the desired tools separately, then:

```bash
cd ~/dotfiles
python3 scripts/tool-settings.py status
python3 scripts/tool-settings.py link
```

`status` also checks whether the filtered preference snapshots match the current
local settings, without printing private values. `link` installs only the manifest's
leaf files, backing up any existing files under
`${XDG_STATE_HOME:-~/.local/state}/dotfiles-tool-settings/`. Unlisted sibling files,
including credentials and sessions, are untouched. Standard Stow also deploys these
source files on a fresh machine; this scoped helper avoids broad `--adopt` operations
on existing tool directories.

Hook commands use `$HOME`, not a captured username. Codex may ask you to approve
the portable hook command again: trust hashes are intentionally not exported.
The Herdr hooks are unchanged snapshots of the installed integration code, not
new handwritten integrations. Some installed hooks were reported outdated by
`herdr integration status`; no integrations were upgraded during this backup.
To deliberately update one later, run `herdr integration install <tool>`, review
the resulting changes, and check links again. Current Herdr's Cursor CLI integration
uses `.config/cursor/`, separately from the older Cursor editor hook in `.cursor/`.

The captured `.zshenv` uses the user SSH agent socket. On another machine, enable
the supplied socket unit separately if desired:

```bash
systemctl --user enable --now ssh-agent.socket
```

SSH host definitions/private keys are intentionally not imported. NVM's installed
versions and Node packages are also dependencies, not source settings.

## Mixed preferences and private state

Codex and Cursor CLI mix settings with local state, so their live files must **not**
be symlinked into Git. Refresh only the allowlisted preference snapshots with:

```bash
python3 scripts/tool-settings.py capture-preferences
```

After reviewing the snapshots, restore them explicitly with:

```bash
python3 scripts/tool-settings.py apply-preferences
```

JSON preferences merge at owned top-level keys and preserve account/trust/cache
fields. The command backs up originals privately. An existing Codex TOML is left
untouched; merge `codex.json`'s settings manually if desired. On a fresh machine,
a minimal Codex TOML is created without project trust or hook approval hashes.

**Review security preferences before restoring:** the captured Cursor CLI setup
uses unrestricted approval mode and a disabled sandbox, matching this machine's
existing settings. Restoring preferences is optional and is not run by the desktop
installer. Account credentials, workspace-trust lists and hook approval hashes are
not exported or auto-approved.

## Dependencies and optional extensions

These steps download third-party code; review before running them:

- Pi restores configured packages at startup; `pi update --extensions` explicitly
  reconciles them. Package declarations, not npm/git caches, are the source of truth.
- Claude's enabled plugin is declared in its settings; install it with
  `claude plugin install clangd-lsp@claude-plugins-official` if it is not already available.
- OpenCode's pinned plugin dependency can be restored with
  `npm install --prefix ~/.config/opencode`.
- Editor extension IDs are saved in `vscode-extensions.txt` and
  `cursor-extensions.txt`. With the appropriate editor CLI installed:

  ```bash
  xargs -r -n 1 code --install-extension < tool-settings/vscode-extensions.txt
  xargs -r -n 1 cursor --install-extension < tool-settings/cursor-extensions.txt
  ```

Sign into each tool independently. Do not copy auth files into this repository.
Deny-by-default Git ignore rules and `tests/test_tool_settings.py` guard the boundary.

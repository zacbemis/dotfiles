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

Filtered preferences are captured/restored explicitly, never by the desktop installer:

```bash
python3 scripts/tool-settings.py capture-preferences
# Review snapshots before restoring:
python3 scripts/tool-settings.py apply-preferences
```

Restores preserve unrelated JSON state and leave existing Codex TOML untouched.
**The captured Cursor CLI preferences disable sandboxing and use unrestricted approvals.**
Review before applying; credentials and trust decisions are not exported.

## Optional dependencies

- OpenCode plugin: `npm install --prefix ~/.config/opencode`.
- Claude plugin: `claude plugin install clangd-lsp@claude-plugins-official`.
- Editor extensions: `xargs -r -n 1 code --install-extension < tool-settings/vscode-extensions.txt`
  (use `cursor` and `cursor-extensions.txt` for Cursor).

These commands download third-party code. Herdr hooks are source snapshots;
upgrade integrations separately and review the resulting changes.

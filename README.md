# dotfiles

Hyprland rice for Arch Linux, managed with [GNU Stow](https://www.gnu.org/software/stow/).

Dynamic colorschemes via [pywal](https://github.com/eendroroy/pywal16) and [matugen](https://github.com/InioX/matugen) — change your wallpaper and the entire desktop follows.

## What's included

| Config | Description |
|---|---|
| **hypr** | Hyprland (compositor), Hyprlock (lockscreen), Hypridle (idle daemon), keybindings, window rules, wallpaper scripts |
| **quickshell** | Desktop bar, tray, notifications, Apps/Run/Files and wallpaper pickers, media/quick settings, persistent component selector; checked startup |
| **kitty** | Terminal emulator config |
| **herdr** | Terminal workspace manager and keybindings, inheriting wallpaper colors from Kitty |
| **nvim** | Standalone Neovim setup with LSP, Treesitter, Git tools, and live wallpaper-derived colors |
| **wal** | Pywal templates for all apps + post-hook script that symlinks generated colors everywhere |
| **matugen** | Material You color generation templates and reload hooks |
| **gtk-3.0 / gtk-4.0** | GTK theme settings (adw-gtk3-dark, Ubuntu Sans, Papirus icons, Bibata cursor) |
| **fontconfig** | Ubuntu Sans UI defaults, Ubuntu Mono fixed-width defaults and Nerd glyph fallback |
| **Thunar** | File manager custom actions and keybindings |
| **.zshrc** | Zsh config with Oh My Zsh, Powerlevel10k, vi mode, aliases |
| **.p10k.zsh** | Powerlevel10k prompt configuration |
| **.gitconfig** | Git user settings |
| **pi** | Pi coding agent settings/packages, multi-pass, web settings and Herdr extension |
| **Claude Code / Codex / Copilot / Cursor** | Reviewed preferences, instructions, keybindings and Herdr hooks; filtered snapshots for mixed private-state files |
| **VS Code / Cursor editor** | User settings, keybindings, snippets and extension ID manifests |
| **OpenCode / Antigravity CLI** | OpenCode config/plugins and filtered Antigravity model/telemetry preferences |
| **gh / htop** | GitHub CLI preferences/aliases and process-monitor layout |

## Developer tool settings

[Tool inventory, restore commands and privacy boundaries](tool-settings/README.md)
document what is tracked and what stays local. Check or restore just these files:

```bash
python3 scripts/tool-settings.py status
python3 scripts/tool-settings.py link
```

Credentials, conversations, installed package caches, workspace trust and account
metadata are not exported. Codex/Cursor CLI preferences are filtered snapshots,
not copies of their mixed account/state files. Tool binaries and logins are installed
separately; restoring security-sensitive preference snapshots is opt-in.

## Desktop UI

Quickshell provides the desktop UI. Super+D opens Apps/Run/Files, Super+W opens
wallpapers, and Super+R reloads the shell.

```bash
~/.config/quickshell/desktop.sh status
~/.config/quickshell/desktop.sh start    # idempotent; refuses another notification server
~/.config/quickshell/desktop.sh restart
```

[Capability audit](.config/quickshell/docs/CAPABILITY-AUDIT.md) ·
[Session ownership, logs and recovery](.config/quickshell/docs/MIGRATION.md).
Waybar, Rofi and SwayNC configs, fallback commands and theme outputs have been
removed. The previous setup is preserved on
`snapshot/pre-quickshell-cleanup-2026-11-03`. Installed packages are not automatically
uninstalled. Hyprlock, Hypridle, wallpaper tools and network/Bluetooth applets remain.

## How colors work

Two color systems are set up — use whichever you prefer:

- **pywal** (`wal -i <image>`) generates colors and `wal-post.sh` symlinks them into each app's `colors/` directory
- **matugen** (`matugen image <image>`) generates Material You colors and writes them directly to each app's color file

The wallpaper scripts at `~/.config/hypr/scripts/` handle everything: set wallpaper via awww, generate colors, reload apps.
Quickshell watches `~/.config/quickshell/colors.css` directly; color hooks do not
restart the desktop UI.

Herdr uses its built-in `terminal` theme to inherit Kitty's ANSI palette, so both
Pywal and Matugen work without a separate Herdr color template. Its bars, inactive
tabs, and sidebar inherit the normal terminal background. Selected tabs and
sidebar rows use Kitty's wallpaper accent (`color4`), tinted for at least 2.2:1
contrast against the background and 4.5:1 contrast with label text. Subdued accents
are adjusted to stay visible; palettes without `color4` fall back to the selection
color or foreground. `panel_bg` and `surface_dim` stay `reset` so selected tab
labels inherit the host foreground. Active tabs share Herdr's global accent
token, so other UI accents also use that tint.
After Kitty reloads, `~/.config/herdr/reload-colors.sh` runs `sync-colors.py` to
update only the managed theme tokens, reloads Herdr's config, and signals
attached clients to refresh their palette. Running panes are not restarted.

Neovim uses the newest valid Pywal or Matugen palette for live background colors,
while a local, VS Code–inspired scheme keeps syntax colors consistent (no theme plugin).
Plain `nvim` opens the standalone config; see [its README](.config/nvim/README.md)
for plugins and keybindings.

## Install

Clone the repo and run the install script:

```bash
git clone https://github.com/zacb/dotfiles.git ~/dotfiles
cd ~/dotfiles
chmod +x install.sh
./install.sh
```

The script will:
1. Install `yay` if missing
2. Install desktop dependencies (official + AUR; developer tool CLIs are separate)
3. Install Oh My Zsh and Powerlevel10k
4. Stow the dotfiles
5. Set zsh as default shell

## Manual stow

If you already have dependencies and just want to link the configs:

```bash
cd ~/dotfiles
stow --no-folding .
```

Tests, repository maintenance scripts, filtered tool snapshots and Python bytecode
are excluded by `.stow-local-ignore`; source config scripts and intentional skills
are still linked. On an existing machine, use the scoped tool linker above rather
than adopting entire tool directories.

To unlink:

```bash
cd ~/dotfiles
stow --no-folding -D .
```

## Runtime-generated files (not tracked)

These are created at runtime by pywal/matugen and intentionally excluded:

- `hypr/colors/colors.conf`, `quickshell/colors.css`
- `kitty/colors.conf`
- `nvim/lua/colors/wal-colors.lua`, `nvim/lua/colors/matugen-colors.lua`
- `gtk-*/colors.css`
- `hypr/current_wallpaper`
- `gtk-4.0/gtk.css`, `gtk-4.0/gtk-dark.css`, `gtk-4.0/assets` (managed by nwg-look)

## Notes

- **Hyprland uses Lua only**: `~/.config/hypr/hyprland.lua` loads the modules in `hypr/hyprmodules/`. Edit `monitors.lua` for your display. Hyprlock/Hypridle and the generated color palette still use their own `.conf` files. See [dialog/window behavior and audit notes](.config/hypr/README.md) for floating rules, idle power commands, dependencies and verification.
- **.oh-my-zsh** is not tracked — it's a git repo managed by `omz update`
- **Pi auth, model cache, and sessions** are not tracked — settings, package declarations, multi-subscription routing, and web-search provider config are tracked
- **Fonts used**: regular Ubuntu Sans for GTK;
  SF Pro Display throughout Quickshell (bold headings/bars, regular other UI);
  Ubuntu Mono (`UbuntuMono Nerd Font Mono`) for Kitty, terminal editors/tools,
  generic monospace and code-font requests. The Nerd patch preserves prompt and
  Neovim icons. UI pictograms use Symbols Nerd Font rather than compressed terminal
  glyphs. SF Pro Display bar/lockscreen text and existing JetBrains Nerd
  bar glyphs remain separate. Normal text and terminal defaults are regular
  weight; bold is reserved for headings, bars and intentional emphasis.
- **Font dependencies**: `ttf-ubuntu-mono-nerd` (official) and `ttf-ubuntu-sans`
  (AUR); the older `ttf-ubuntu-font-family` does **not** provide Ubuntu Sans.
  `install.sh` installs both, stows Fontconfig aliases and sets GTK/portal UI and
  monospace font preferences. Restart existing apps to pick up font changes.

## License

[MIT](LICENSE)

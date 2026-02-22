# dotfiles

Hyprland rice for Arch Linux, managed with [GNU Stow](https://www.gnu.org/software/stow/).

Dynamic colorschemes via [pywal](https://github.com/eendroroy/pywal16) and [matugen](https://github.com/InioX/matugen) — change your wallpaper and the entire desktop follows.

## What's included

| Config | Description |
|---|---|
| **hypr** | Hyprland (compositor), Hyprlock (lockscreen), Hypridle (idle daemon), keybindings, window rules, wallpaper scripts |
| **waybar** | Top bar with workspaces, clock, battery, brightness, volume, notification indicator |
| **rofi** | App launcher + wallpaper picker with thumbnail previews |
| **swaync** | Notification center with Material Design theming, update checker widget |
| **kitty** | Terminal emulator config |
| **nvim** | LazyVim-based Neovim setup with dynamic base16 colorscheme |
| **wal** | Pywal templates for all apps + post-hook script that symlinks generated colors everywhere |
| **matugen** | Material You color generation templates and reload hooks |
| **gtk-3.0 / gtk-4.0** | GTK theme settings (adw-gtk3-dark, Papirus icons, Bibata cursor) |
| **Thunar** | File manager custom actions and keybindings |
| **rofi wallpaper** | Script-mode wallpaper selector with thumbnail generation |
| **.zshrc** | Zsh config with Oh My Zsh, Powerlevel10k, vi mode, aliases |
| **.p10k.zsh** | Powerlevel10k prompt configuration |
| **.gitconfig** | Git user settings |

## How colors work

Two color systems are set up — use whichever you prefer:

- **pywal** (`wal -i <image>`) generates colors and `wal-post.sh` symlinks them into each app's `colors/` directory
- **matugen** (`matugen image <image>`) generates Material You colors and writes them directly to each app's color file

The wallpaper scripts at `~/.config/hypr/scripts/` handle everything: set wallpaper via swww, generate colors, reload apps.

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
2. Install all dependencies (official + AUR)
3. Install Oh My Zsh and Powerlevel10k
4. Stow the dotfiles
5. Set zsh as default shell

## Manual stow

If you already have dependencies and just want to link the configs:

```bash
cd ~/dotfiles
stow --no-folding .
```

To unlink:

```bash
cd ~/dotfiles
stow --no-folding -D .
```

## Runtime-generated files (not tracked)

These are created at runtime by pywal/matugen and intentionally excluded:

- `*/colors/colors.css`, `*/colors/colors.conf`, `*/colors/colors.rasi`
- `kitty/colors.conf`
- `nvim/lua/colors/wal-colors.lua`, `nvim/lua/colors/matugen-colors.lua`
- `gtk-*/colors.css`
- `hypr/current_wallpaper`
- `gtk-4.0/gtk.css`, `gtk-4.0/gtk-dark.css`, `gtk-4.0/assets` (managed by nwg-look)

## Notes

- **Monitor config** is in `hypr/hyprmodules/monitors.conf` — you will likely need to change this for your display
- **.oh-my-zsh** is not tracked — it's a git repo managed by `omz update`
- **Fonts used**: SF Pro Display, Mononoki Nerd Font, JetBrainsMono Nerd Font

## License

[MIT](LICENSE)

# Dotfiles

Arch Linux desktop and developer configs, managed with GNU Stow.

## Features

- **[Hyprland](.config/hypr/README.md):** Lua configuration, window rules, keybindings, lockscreen and idle power management.
- **[Quickshell](.config/quickshell/README.md):** desktop bar, tray, launcher, wallpapers, notifications, media and system controls.
- **Wallpaper themes:** Pywal or Matugen colors shared across the desktop, Kitty, GTK, Herdr and Neovim.
- **[Neovim](.config/nvim/README.md):** file explorer, fuzzy search, LSP, completion, Treesitter and Git review.
- **Terminal:** Kitty, Herdr workspaces, Zsh, Oh My Zsh and Powerlevel10k.
- **Desktop apps:** Thunar actions, GTK themes, Ubuntu fonts, Papirus icons and Bibata cursors.
- **[Developer tools](tool-settings/README.md):** editor and coding-agent preferences, keybindings, extensions and Herdr hooks.
- **[Tests](tests/README.md):** installer, deployment, editor and desktop checks.

## Install

Run as your normal user on Arch Linux with sudo access:

```bash
sudo pacman -Syu --needed git
git clone https://github.com/zacbemis/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

Installs desktop dependencies, sets up Zsh, links configs and starts network/Bluetooth services.
Reviewed shell/tool conflicts are backed up; other conflicts stop installation.
Developer-tool applications and logins are separate installs. Credentials and sessions stay local.

To link configs without installing dependencies:

```bash
stow --simulate --verbose --no-folding --target="$HOME" .
stow --no-folding --target="$HOME" .
```

Review conflicts rather than using `--adopt`, which imports local files into Git.
Edit `.config/hypr/hyprmodules/monitors.lua` for your display.

[MIT License](LICENSE)

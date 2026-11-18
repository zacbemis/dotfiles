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

## SSH keys across restarts

The desktop uses GCR's SSH agent and GNOME Keyring instead of a bare, empty
OpenSSH agent. SSH keys keep their passphrases; saved passphrases live in the
encrypted login keyring, not in these dotfiles.

For an existing installation, run:

```bash
bash scripts/setup-ssh-keyring.sh
```

Then log out and back in **with your account password**. Ly already includes
`pam_gnome_keyring.so` authentication and `auto_start` session hooks. Other login
managers need the equivalent [PAM configuration](https://wiki.archlinux.org/title/GNOME/Keyring#PAM_step).
Autologin and fingerprint-only login cannot unlock the keyring automatically.

One-time setup in **Seahorse / Passwords and Keys**:

1. Make **Login** the default password keyring. Its password must match your
   account password; do not use a blank password. Existing keyrings need not be deleted.
2. Connect with `ssh lenovohome` and select **Automatically unlock this key whenever
   I'm logged in** in the SSH passphrase dialog.

`~/.ssh/config` must not force the old agent with
`IdentityAgent /run/user/%i/ssh-agent.socket`. Remove that setting to use
`SSH_AUTH_SOCK`, or point it to `/run/user/%i/gcr/ssh`.
The desktop environment sets `SSH_AUTH_SOCK` to `$XDG_RUNTIME_DIR/gcr/ssh`;
Zsh preserves inherited agents, including forwarded SSH agents.

After another login, `ssh -o BatchMode=yes lenovohome true` and
`herdr machine status lenovohome` should work without another SSH passphrase.
Herdr retries failed connections automatically; it does not need a custom
reconnect hook. Never store a passphrase in a shell script or remove the key's
passphrase to work around login setup.

[MIT License](LICENSE)

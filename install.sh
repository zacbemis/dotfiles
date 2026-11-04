#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { printf "${GREEN}[+]${NC} %s\n" "$1"; }
warn()  { printf "${YELLOW}[!]${NC} %s\n" "$1"; }
error() { printf "${RED}[x]${NC} %s\n" "$1"; }

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -eq 1 && ( "$1" == --help || "$1" == -h ) ]]; then
    printf '%s\n' \
        'Usage: ./install.sh' \
        'Install the Arch desktop packages and restore tracked dotfiles.' \
        'Run as your normal user with sudo access and an internet connection.' \
        'Reviewed shell/tool conflicts are backed up; other Stow conflicts stop the install.' \
        'Developer tool CLIs and authentication are installed separately.'
    exit 0
fi
if [[ $# -gt 0 ]]; then
    error "Unsupported arguments. Use ./install.sh --help; there is no live --dry-run mode."
    exit 2
fi

# Run as the intended user: makepkg refuses root, and HOME is the Stow target.
if [[ "$(id -u)" -eq 0 ]]; then
    error "Run ./install.sh as your normal user, not with sudo."
    exit 1
fi
if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
    error "HOME must point to an existing user home directory."
    exit 1
fi
if ! command -v pacman &>/dev/null || ! command -v sudo &>/dev/null; then
    error "This installer requires Arch Linux (pacman) and sudo access."
    exit 1
fi

# ── yay ──────────────────────────────────────────────────────────────
if ! command -v yay &>/dev/null; then
    info "Installing yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm base-devel git
    tmpdir="$(mktemp -d)"
    trap 'rm -rf -- "$tmpdir"' EXIT
    git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"
    (cd "$tmpdir/yay-bin" && makepkg -si --noconfirm)
    rm -rf -- "$tmpdir"
    trap - EXIT
fi

# ── official repo packages ───────────────────────────────────────────
OFFICIAL=(
    # AUR build prerequisites, including when yay was already installed
    base-devel

    # compositor & tools
    hyprland
    hyprlock
    hypridle
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk # fallback file chooser/settings portal

    # desktop bar, launcher, notifications
    quickshell
    python
    python-gobject
    gtk3
    qt6-svg
    qt6-imageformats
    xdg-utils
    pacman-contrib

    # terminal, shell & Git authentication helper
    curl
    git
    github-cli
    kitty
    zsh
    fzf
    bat
    jq
    direnv
    stow

    # file manager
    thunar

    # editor
    neovim

    # wallpaper & colors
    awww
    imagemagick

    # wayland clipboard & screenshot
    wl-clipboard
    grim
    slurp

    # audio
    pipewire
    pipewire-pulse
    wireplumber
    libpulse # pactl: Bluetooth card profiles absent from Quickshell's native API

    # brightness & media
    brightnessctl
    playerctl

    # networking & bluetooth
    networkmanager
    libnm
    network-manager-applet
    nm-connection-editor
    bluez
    bluez-utils
    blueman

    # night light
    wlsunset

    # theming
    nwg-look
    papirus-icon-theme

    # node version manager
    nvm

    # flatpak (for the Quickshell update widget)
    flatpak

    # fonts
    ttf-jetbrains-mono-nerd
    ttf-ubuntu-mono-nerd
    ttf-nerd-fonts-symbols
)

# ── AUR packages ─────────────────────────────────────────────────────
AUR=(
    helium-browser-bin # Super+B and the default HTML/HTTP handlers
    python-pywal16
    matugen
    bibata-cursor-theme
    adw-gtk-theme
    apple-fonts
    ttf-ubuntu-sans
)

info "Installing official packages..."
yay -S --needed --noconfirm "${OFFICIAL[@]}"

info "Installing AUR packages..."
yay -S --needed --noconfirm "${AUR[@]}"

# ── oh-my-zsh ────────────────────────────────────────────────────────
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "Installing Oh My Zsh..."
    omz_installer="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ZSH="$HOME/.oh-my-zsh" RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$omz_installer"
fi

# ── powerlevel10k ────────────────────────────────────────────────────
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [[ ! -d "$P10K_DIR" ]]; then
    info "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

# ── zsh plugins ──────────────────────────────────────────────────────
ZSH_PLUGIN_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
mkdir -p "$ZSH_PLUGIN_DIR"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [[ ! -d "$ZSH_PLUGIN_DIR/$plugin" ]]; then
        info "Installing $plugin..."
        git clone --depth=1 "https://github.com/zsh-users/$plugin.git" "$ZSH_PLUGIN_DIR/$plugin"
    fi
done

# ── nvm ──────────────────────────────────────────────────────────────
# Arch ships the implementation in /usr/share/nvm. Its initializer creates
# the user-side nvm.sh/nvm-exec links expected by .zshenv and .zshrc.
if [[ -r /usr/share/nvm/init-nvm.sh ]]; then
    info "Preparing NVM loader links..."
    NVM_DIR="$HOME/.config/nvm" bash -c 'source /usr/share/nvm/init-nvm.sh'
fi

# ── stow ─────────────────────────────────────────────────────────────
info "Stowing dotfiles..."

# create dirs that receive runtime-generated color files
mkdir -p "$HOME/.config/quickshell" \
         "$HOME/.config/hypr/colors" \
         "$HOME/.config/nvim/lua/colors" \
         "$HOME/.config/kitty" \
         "$HOME/.config/gtk-3.0" \
         "$HOME/.config/gtk-4.0"

# Hyprlock sources this file directly, unlike the compositor's Lua fallback.
# Make a first login lockable before the first wallpaper is selected. Do not
# replace existing palettes or interfere with an existing generator's recovery.
palette="$HOME/.config/hypr/colors/colors.conf"
generator_state="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/color-generator"
if [[ ! -s "$palette" && ! -s "$generator_state" ]]; then
    info "Creating a first-login lockscreen palette..."
    palette_tmp="$(mktemp "$palette.XXXXXX")"
    printf '%s\n' '$primary = rgba(89b4faff)' '$secondary = rgba(cba6f7ff)' \
        '$inverse_primary = rgba(ffffffff)' > "$palette_tmp"
    mv -f -- "$palette_tmp" "$palette"
fi

cd "$DOTFILES_DIR"
# Arch skeleton files and Oh My Zsh's generated .zshrc are expected conflicts.
# Restore only the reviewed manifest, with private backups; never adopt into Git.
python3 "$DOTFILES_DIR/scripts/tool-settings.py" link
if ! stow --no-folding --target="$HOME" .; then
    error "Stow found conflicting files or links; no existing settings were adopted."
    warn "Back up and resolve the reported conflicts, then rerun Stow."
    warn "For reviewed developer-tool files, use: python3 scripts/tool-settings.py link"
    exit 1
fi

# GTK/portal settings also need the proportional UI / fixed-width editor split.
# Fontconfig aliases (stowed above) cover other apps and Nerd glyph fallback.
if command -v gsettings &>/dev/null && \
        gsettings list-schemas | grep -x org.gnome.desktop.interface >/dev/null; then
    info "Applying Ubuntu UI and monospace fonts..."
    if ! { gsettings set org.gnome.desktop.interface font-name 'Ubuntu Sans 11' &&
           gsettings set org.gnome.desktop.interface monospace-font-name 'UbuntuMono Nerd Font Mono 11'; }; then
        warn "Could not apply GTK/portal font preferences; retry from a graphical user session."
    fi
fi

# ── default shell ────────────────────────────────────────────────────
# SHELL can still name the old shell until the next login; inspect passwd so
# rerunning the installer does not repeat chsh or depend on SHELL being set.
login_entry="$(getent passwd "$(id -u)")"
login_shell="${login_entry##*:}"
if [[ "$login_shell" != */zsh ]]; then
    info "Changing default shell to zsh..."
    chsh -s "$(command -v zsh)"
    warn "Log out and back in for the shell change to take effect."
fi

# ── enable services ──────────────────────────────────────────────────
# enable --now is idempotent and also starts an enabled-but-inactive service.
for service in NetworkManager bluetooth; do
    info "Enabling and starting $service..."
    sudo systemctl enable --now "$service"
done

# ── done ─────────────────────────────────────────────────────────────
echo ""
info "Done! Next steps:"
echo "  1. Log out and log into a Hyprland session"
echo "  2. Set a wallpaper:  ~/.config/hypr/scripts/set-wallpaper.sh ~/Pictures/wallpapers/something.png"
echo "  3. Edit monitor config if needed:  ~/.config/hypr/hyprmodules/monitors.lua"
echo "  4. Start the desktop UI: ~/.config/quickshell/desktop.sh start"
echo "     Stop any other notification server first; Quickshell will not evict it."
echo ""
warn "The monitor is set to 2880x1800@60 — change this in monitors.lua for your display."

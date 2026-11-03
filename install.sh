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

# ── yay ──────────────────────────────────────────────────────────────
if ! command -v yay &>/dev/null; then
    info "Installing yay (AUR helper)..."
    sudo pacman -S --needed --noconfirm base-devel git
    tmpdir="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay-bin.git "$tmpdir/yay-bin"
    (cd "$tmpdir/yay-bin" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
fi

# ── official repo packages ───────────────────────────────────────────
OFFICIAL=(
    # compositor & tools
    hyprland
    hyprlock
    hypridle
    xdg-desktop-portal-hyprland

    # daily bar, launcher, notifications (legacy stack is opt-in below)
    quickshell
    python
    python-gobject
    gtk3
    qt6-svg
    qt6-imageformats
    xdg-utils
    pacman-contrib

    # terminal & shell
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

# Retain a runnable rollback stack when explicitly requested; do not uninstall
# existing packages during migration.
if [[ "${INSTALL_LEGACY_UI:-0}" == 1 ]]; then
    OFFICIAL+=(waybar rofi swaync)
fi

# ── AUR packages ─────────────────────────────────────────────────────
AUR=(
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
    RUNZSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# ── powerlevel10k ────────────────────────────────────────────────────
P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
if [[ ! -d "$P10K_DIR" ]]; then
    info "Installing Powerlevel10k..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
fi

# ── stow ─────────────────────────────────────────────────────────────
info "Stowing dotfiles..."

# create dirs that receive runtime-generated color files
mkdir -p "$HOME/.config/quickshell" \
         "$HOME/.config/hypr/colors" \
         "$HOME/.config/waybar/colors" \
         "$HOME/.config/rofi/colors" \
         "$HOME/.config/swaync/colors" \
         "$HOME/.config/nvim/lua/colors" \
         "$HOME/.config/kitty" \
         "$HOME/.config/gtk-3.0" \
         "$HOME/.config/gtk-4.0"

cd "$DOTFILES_DIR"
stow --no-folding --adopt .

# GTK/portal settings also need the proportional UI / fixed-width editor split.
# Fontconfig aliases (stowed above) cover other apps and Nerd glyph fallback.
if command -v gsettings &>/dev/null && \
        gsettings list-schemas | grep -qx org.gnome.desktop.interface; then
    info "Applying Ubuntu UI and monospace fonts..."
    gsettings set org.gnome.desktop.interface font-name 'Ubuntu Sans 11'
    gsettings set org.gnome.desktop.interface monospace-font-name 'UbuntuMono Nerd Font Mono 11'
fi

# ── default shell ────────────────────────────────────────────────────
if [[ "$SHELL" != */zsh ]]; then
    info "Changing default shell to zsh..."
    chsh -s "$(which zsh)"
    warn "Log out and back in for the shell change to take effect."
fi

# ── enable services ──────────────────────────────────────────────────
if ! systemctl is-enabled NetworkManager &>/dev/null; then
    info "Enabling NetworkManager..."
    sudo systemctl enable --now NetworkManager
fi

if ! systemctl is-enabled bluetooth &>/dev/null; then
    info "Enabling Bluetooth..."
    sudo systemctl enable --now bluetooth
fi

# ── done ─────────────────────────────────────────────────────────────
echo ""
info "Done! Next steps:"
echo "  1. Log out and log into a Hyprland session"
echo "  2. Set a wallpaper:  ~/.config/hypr/scripts/set-wallpaper.sh ~/Pictures/wallpapers/something.png"
echo "  3. Edit monitor config if needed:  ~/.config/hypr/hyprmodules/monitors.lua"
echo "  4. For a live-session handoff: ~/.config/quickshell/desktop.sh activate"
echo "     Rollback: ~/.config/quickshell/desktop.sh legacy (requires legacy packages)"
echo ""
warn "The monitor is set to 2880x1800@60 — change this in monitors.lua for your display."

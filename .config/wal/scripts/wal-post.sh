#!/usr/bin/env bash
set -euo pipefail

CACHE="$HOME/.cache/wal"

mkdir -p "$HOME/.config/quickshell" \
         "$HOME/.config/hypr/colors" \
         "$HOME/.config/waybar/colors" \
         "$HOME/.config/rofi/colors" \
         "$HOME/.config/swaync/colors" \
         "$HOME/.config/nvim/lua/colors" \
         "$HOME/.config/gtk-3.0" \
         "$HOME/.config/gtk-4.0"

ln -sf "$CACHE/colors-hyprland-custom.conf" "$HOME/.config/hypr/colors/colors.conf"
ln -sf "$CACHE/colors-waybar-custom.css"    "$HOME/.config/quickshell/colors.css"
ln -sf "$CACHE/colors-waybar-custom.css"    "$HOME/.config/waybar/colors/colors.css"
ln -sf "$CACHE/colors-rofi-custom.rasi"     "$HOME/.config/rofi/colors/colors.rasi"
ln -sf "$CACHE/colors-swaync-custom.css"    "$HOME/.config/swaync/colors/colors.css"
ln -sf "$CACHE/colors-kitty-custom.conf"    "$HOME/.config/kitty/colors.conf"
ln -sf "$CACHE/colors-nvim-custom.lua"      "$HOME/.config/nvim/lua/colors/wal-colors.lua"
ln -sf "$CACHE/colors-gtk-custom.css"       "$HOME/.config/gtk-3.0/colors.css"
ln -sf "$CACHE/colors-gtk-custom.css"       "$HOME/.config/gtk-4.0/colors.css"

# Remember the generator only after its palette has been installed.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
mkdir -p "$STATE"
printf '%s\n' pywal > "$STATE/color-generator"

# Lua reads colors.conf via io.open(), which does not register a config watch.
# Reload only after the generated palette is linked into place.
hyprctl reload >/dev/null 2>&1 || true

if [[ -x "$HOME/.config/quickshell/desktop.sh" ]]; then
    "$HOME/.config/quickshell/desktop.sh" palette || true
else
    pkill -SIGUSR2 waybar 2>/dev/null || true
    if pgrep -x swaync >/dev/null 2>&1; then
        swaync-client -R >/dev/null 2>&1 || true
        swaync-client -rs >/dev/null 2>&1 || true
    fi
fi
pkill -USR1 -x kitty 2>/dev/null || true
if [[ -x "$HOME/.config/herdr/reload-colors.sh" ]]; then
    "$HOME/.config/herdr/reload-colors.sh" || true
fi
# Legacy reloads are handled only by desktop.sh's explicit rollback mode.
gsettings set org.gnome.desktop.interface gtk-theme "" 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark" 2>/dev/null || true

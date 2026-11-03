#!/usr/bin/env bash
set -euo pipefail

CACHE="$HOME/.cache/wal"

mkdir -p "$HOME/.config/quickshell" \
         "$HOME/.config/hypr/colors" \
         "$HOME/.config/nvim/lua/colors" \
         "$HOME/.config/gtk-3.0" \
         "$HOME/.config/gtk-4.0"

ln -sf "$CACHE/colors-hyprland-custom.conf" "$HOME/.config/hypr/colors/colors.conf"
ln -sf "$CACHE/colors-quickshell-custom.css" "$HOME/.config/quickshell/colors.css"
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

# Quickshell watches colors.css directly; no shell restart or signal is needed.
pkill -USR1 -x kitty 2>/dev/null || true
if [[ -x "$HOME/.config/herdr/reload-colors.sh" ]]; then
    "$HOME/.config/herdr/reload-colors.sh" || true
fi
gsettings set org.gnome.desktop.interface gtk-theme "" 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark" 2>/dev/null || true

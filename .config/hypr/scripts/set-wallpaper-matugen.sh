#!/usr/bin/env bash
set -euo pipefail

img="${1:-}"
[[ -n "$img" && -f "$img" ]] || exit 1

# 1) Hyprlock background: keep a stable path that always points to current wallpaper
ln -sf "$img" "$HOME/.config/hypr/current_wallpaper"

# 2) Run matugen (handles swww + regenerates themes)
# Background it so rofi never waits.
(matugen image "$img" >/dev/null 2>&1) &
disown || true

# 3) Optional: ensure swaync picks up CSS (config + style)
# (remove if matugen already triggers this)
(
  swaync-client -R >/dev/null 2>&1
  swaync-client -rs >/dev/null 2>&1
) &
disown || true

exit 0

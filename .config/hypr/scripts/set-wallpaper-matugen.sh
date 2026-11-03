#!/usr/bin/env bash
set -euo pipefail

img="${1:-}"
[[ -n "$img" && -f "$img" ]] || exit 1

# 1) Hyprlock background: keep a stable path that always points to current wallpaper
ln -sf "$img" "$HOME/.config/hypr/current_wallpaper"

# 2) Run matugen (handles awww + regenerates themes)
# Background it so the wallpaper picker never waits.
(matugen image "$img" >/dev/null 2>&1) &
disown || true

# Quickshell watches its palette. Matugen's mode-aware hooks handle an explicit
# legacy rollback; never auto-activate SwayNC after the daily-shell cutover.

exit 0

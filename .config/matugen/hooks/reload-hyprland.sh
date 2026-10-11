#!/usr/bin/env bash
set -euo pipefail

# This template hook runs after Matugen has written the Hyprland palette.
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
mkdir -p "$STATE"
printf '%s\n' matugen > "$STATE/color-generator"

# Lua's io.open() color bridge does not register a config watch.
hyprctl reload >/dev/null 2>&1 || true

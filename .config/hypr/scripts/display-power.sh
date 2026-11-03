#!/usr/bin/env bash
# Hyprland's Lua CLI expects a typed dispatcher, not the old "dpms on/off".
set -euo pipefail

case "${1:-}" in
    on|off) exec hyprctl dispatch "hl.dsp.dpms({action=\"$1\"})" ;;
    *) printf 'usage: %s on|off\n' "${0##*/}" >&2; exit 2 ;;
esac

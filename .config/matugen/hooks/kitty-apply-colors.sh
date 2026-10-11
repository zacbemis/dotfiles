#!/usr/bin/env bash
pkill -USR1 -x kitty 2>/dev/null || true
if [[ -x "$HOME/.config/herdr/reload-colors.sh" ]]; then
    "$HOME/.config/herdr/reload-colors.sh" || true
fi

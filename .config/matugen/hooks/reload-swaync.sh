#!/usr/bin/env bash
set -euo pipefail
# Compatibility hook for the retained rollback palette. It must never revive a
# retired notification daemon while Quickshell owns org.freedesktop.Notifications.
if [[ -x "$HOME/.config/quickshell/desktop.sh" ]]; then
    exec "$HOME/.config/quickshell/desktop.sh" palette
fi
# Pre-deployment fallback: reload only an already-running legacy server.
if pgrep -x swaync >/dev/null 2>&1; then
    swaync-client -R >/dev/null 2>&1 || true
    swaync-client -rs >/dev/null 2>&1 || true
fi

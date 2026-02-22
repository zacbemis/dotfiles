#!/usr/bin/env bash
set -euo pipefail

# Make sure PATH is sane when run from hooks
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

# Give matugen a moment to finish writing files (prevents race)
sleep 0.15

# Prefer DBus reloads (safe, no freezes)
if command -v swaync-client >/dev/null 2>&1; then
  # Reload config then CSS (sequential is the reliable way)
  swaync-client -R  >/dev/null 2>&1 || true
  swaync-client -rs >/dev/null 2>&1 || true
  exit 0
fi

# Fallback: restart gently
pkill -TERM swaync >/dev/null 2>&1 || true
sleep 0.2
nohup swaync >/dev/null 2>&1 &

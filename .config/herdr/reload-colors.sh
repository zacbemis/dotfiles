#!/usr/bin/env bash
set -euo pipefail

# Keep bars/inactive tabs/sidebar on the normal terminal background, with
# selected tabs/sidebar rows on the darker Neovim explorer shade.
python3 "$(dirname -- "${BASH_SOURCE[0]}")/sync-colors.py" || true

# SIGWINCH makes attached clients re-query Kitty's ANSI palette, also refreshing
# the palette inherited by their panes. Never signal headless Herdr servers.
pids=$(ps -u "$(id -u)" -o pid=,comm=,tty= |
    awk '$2 == "herdr" && $3 != "?" { print $1 }')
[[ -n "$pids" ]] || exit 0

# Kitty's SIGUSR1 reload is asynchronous; let it apply the new palette first.
sleep 0.2
# Notify attached clients that the custom background tokens changed, too.
herdr server reload-config >/dev/null 2>&1 || true
while IFS= read -r pid; do
    kill -WINCH "$pid" 2>/dev/null || true
done <<< "$pids"

#!/usr/bin/env bash
set -euo pipefail

img="${1:-}"
[[ -n "$img" && -f "$img" ]] || exit 1

ln -sf "$img" "$HOME/.config/hypr/current_wallpaper"

(
  swww img "$img" --transition-type center
  wal -n -q -i "$img" --cols16 lighten \
      -o "$HOME/.config/wal/scripts/wal-post.sh"
) &
disown || true

exit 0

#!/usr/bin/env bash
set -euo pipefail

# ---- user config ----
WALL_DIR="${WALL_DIR:-$HOME/Pictures/wallpapers}"
THUMB_DIR="${THUMB_DIR:-$HOME/.cache/rofi-wallpaper-thumbs}"
SETTER="${SETTER:-$HOME/.config/hypr/scripts/set-wallpaper.sh}"  # your existing script
THUMB_SIZE="${THUMB_SIZE:-256}"  # px
# ---------------------

mkdir -p "$THUMB_DIR"

# If rofi calls us with an argument, it's the selected entry.
# We store the real path after a NUL separator so names can be pretty.
if [[ $# -gt 0 ]]; then
  # Extract everything after the last \0 (rofi passes the displayed text, not raw)
  # We'll map by displayed basename -> real file path
  selection="$1"
  # Strip any icon markup or extra spaces (safe-ish)
  selection="${selection##* }"
  chosen="$(find "$WALL_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    -printf '%f\t%p\n' | awk -F'\t' -v s="$selection" '$1==s {print $2; exit}')"

  [[ -n "${chosen:-}" ]] || exit 0
  exec "$SETTER" "$chosen"
fi

# List wallpapers with thumbnails as icons.
# Requires: ImageMagick (magick/convert) OR imv-thumb alternative
# We'll try magick first, then convert.
gen_thumb() {
  local src="$1"
  local base
  base="$(basename "$src")"
  local out="$THUMB_DIR/$base.png"

  if [[ -f "$out" ]]; then
    printf '%s\n' "$out"
    return
  fi

  if command -v magick >/dev/null 2>&1; then
    magick "$src" -auto-orient -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}^" -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" "$out" >/dev/null 2>&1 || true
  elif command -v convert >/dev/null 2>&1; then
    convert "$src" -auto-orient -thumbnail "${THUMB_SIZE}x${THUMB_SIZE}^" -gravity center -extent "${THUMB_SIZE}x${THUMB_SIZE}" "$out" >/dev/null 2>&1 || true
  else
    # No thumbnail tool available; return empty
    : > /dev/null
  fi

  [[ -f "$out" ]] && printf '%s\n' "$out" || printf '\n'
}

# Output in rofi script-mode format:
# label\0icon\x1f/path/to/icon\n
while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  icon="$(gen_thumb "$f")"

  if [[ -n "$icon" ]]; then
    printf '%s\0icon\x1f%s\n' "$name" "$icon"
  else
    printf '%s\n' "$name"
  fi
done < <(find "$WALL_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) -print0 | sort -z)

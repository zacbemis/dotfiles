#!/usr/bin/env bash
set -euo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
CACHE="${PYWAL_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/wal}"
wallpaper="$CONFIG/hypr/current_wallpaper"
generator=pywal

# Older installations used Pywal unconditionally; retain that default.
if [[ -s "$STATE/color-generator" ]]; then
    generator="$(< "$STATE/color-generator")"
fi

case "$generator" in
    matugen)
        # Matugen's output files already persist across logins. Do not overwrite
        # them with Pywal's cache, or discard custom Matugen mode/type settings.
        if [[ ! -s "$CONFIG/hypr/colors/colors.conf" && -f "$wallpaper" ]]; then
            matugen image "$wallpaper"
        fi
        ;;
    pywal)
        hook="$CONFIG/wal/scripts/wal-post.sh"
        if [[ -s "$CACHE/colors.json" ]]; then
            wal -R -n -q -o "$hook"
        elif [[ -f "$wallpaper" ]]; then
            # Cache cleanup should not leave the compositor on fallback colors.
            wal -n -q -i "$wallpaper" --cols16 lighten -o "$hook"
        fi
        ;;
    *)
        printf 'Unknown color generator: %s; leaving existing colors intact\n' "$generator" >&2
        exit 1
        ;;
esac

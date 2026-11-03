#!/usr/bin/env bash
# No installers, downloads, process killing, persistent settings or live server.
set -euo pipefail
config="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
case "${1:-current}" in
    list|--list)
        printf '%s\n' 'current   Local wallpaper-derived pill bar' \
            'enzo      EnzoNotNice: floating Catppuccin bar + workspace pills (MIT)' \
            'mm2103    MM-2103: flat monochrome + numbered chips + optional auto-hide (MIT)'
        exit 0 ;;
    -h|--help)
        printf '%s\n' 'Usage: compare.sh [current|enzo|mm2103] [qs options]' \
            'Click the comparison panel to switch layouts without restarting.' \
            'Always preview notifications; existing desktop services remain running.'
        exit 0 ;;
    current|enzo|mm2103) profile="${1:-current}"; if (( $# )); then shift; fi ;;
    *) printf 'Unknown comparison profile: %s\n' "$1" >&2; exit 2 ;;
esac
export QUICKSHELL_BAR=1
exec bash "$config/run.sh" --compare --profile "$profile" "$@"

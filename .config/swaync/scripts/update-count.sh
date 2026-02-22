#!/usr/bin/env bash
set -euo pipefail

CFG="$HOME/.config/swaync/config.json"
TMP="$(mktemp)"

UPDATES_CMD="kitty -e bash -lc 'yay -Syu; flatpak update; ~/.config/swaync/scripts/clear-updates.sh'"

pac=0
aur=0
flat=0

command -v checkupdates >/dev/null 2>&1 && pac="$(checkupdates 2>/dev/null | wc -l || true)"
command -v yay >/dev/null 2>&1 && aur="$(yay -Qua 2>/dev/null | wc -l || true)"
command -v flatpak >/dev/null 2>&1 && flat="$(flatpak remote-ls --updates 2>/dev/null | wc -l || true)"

total=$((pac + aur + flat))

if (( total > 0 )); then
  label=""
else
  label=""
fi

jq --arg label "$label" --arg cmd "$UPDATES_CMD" '
  .["widget-config"]["buttons-grid"]["actions"] |=
    (map(if .command == $cmd then .label = $label else . end))
' "$CFG" > "$TMP"

mv "$TMP" "$CFG"
/usr/bin/swaync-client -R >/dev/null 2>&1 || true


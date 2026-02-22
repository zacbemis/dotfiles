#!/usr/bin/env bash
set -euo pipefail

CFG="$HOME/.config/swaync/config.json"
TMP="$(mktemp)"

label=""

jq --arg label "$label" \
  '.["widget-config"]["buttons-grid"]["actions"][0]["label"] = $label' \
  "$CFG" > "$TMP"

mv "$TMP" "$CFG"
swaync-client -R >/dev/null 2>&1 || true


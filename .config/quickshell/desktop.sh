#!/usr/bin/env bash
set -euo pipefail
config="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$config/scripts/desktop-session.py" "$@"

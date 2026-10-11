#!/usr/bin/env bash
set -euo pipefail
config="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Long-lived terminals can inherit a signature from an earlier Hyprland login.
# Only repair it when there is exactly one live compositor; never guess between
# multiple sessions. This does not alter the compositor or systemd environment.
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ ! -S "$runtime/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket.sock" ]]; then
    shopt -s nullglob
    sockets=("$runtime"/hypr/*/.socket.sock)
    if (( ${#sockets[@]} == 1 )); then
        signature="${sockets[0]%/.socket.sock}"
        export HYPRLAND_INSTANCE_SIGNATURE="${signature##*/}"
    fi
fi

# QML animates the card, not its screen-sized transparent input surface. Avoid
# an additional compositor fade/pop-in on these three development namespaces.
# This named runtime rule affects no existing UI and changes no Hyprland files.
if command -v hyprctl >/dev/null 2>&1 && [[ -S "$runtime/hypr/${HYPRLAND_INSTANCE_SIGNATURE:-}/.socket.sock" ]]; then
    hyprctl -i "$HYPRLAND_INSTANCE_SIGNATURE" eval \
        "hl.layer_rule({name='quickshell-dev-card-motion',match={namespace='^quickshell-dev-(launcher|wallpaper|notifications)$'},no_anim=true})" \
        >/dev/null 2>&1 || true
fi

while (( $# )); do
    case "$1" in
        --preview) export QUICKSHELL_NOTIFICATIONS=preview; shift ;;
        --no-bar) export QUICKSHELL_BAR=0; shift ;;
        *) break ;;
    esac
done
exec qs -p "$config/shell.qml" "$@"

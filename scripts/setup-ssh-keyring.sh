#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
    printf '%s\n' 'Run this as your normal desktop user, not with sudo.' >&2
    exit 1
fi

packages=(openssh gcr-4 gnome-keyring seahorse)
if ! pacman -Q "${packages[@]}" >/dev/null 2>&1; then
    sudo pacman -S --needed "${packages[@]}"
fi

# Leave the old agent running for existing terminals until logout.
systemctl --user disable ssh-agent.socket ssh-agent.service
systemctl --user enable --now gnome-keyring-daemon.socket gcr-ssh-agent.socket

printf '%s\n' \
    'SSH now uses GCR and an encrypted desktop keyring.' \
    'Log out and log back in using your account password.' \
    'In Seahorse (Passwords and Keys), make Login the default keyring and' \
    'ensure its password matches your account password; never use a blank password.' \
    'Then connect with ssh lenovohome and select the option to remember the SSH passphrase.' \
    'See README.md#ssh-keys-across-restarts for verification and login requirements.'

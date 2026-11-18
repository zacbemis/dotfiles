export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/nvm.sh" ] && nvm use default >/dev/null 2>&1
# Do not replace a forwarded agent supplied by SSH.
if [[ -z "${SSH_AUTH_SOCK:-}" && -n "${XDG_RUNTIME_DIR:-}" ]]; then
    export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gcr/ssh"
fi

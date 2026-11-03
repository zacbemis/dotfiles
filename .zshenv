export NVM_DIR="$HOME/.config/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/nvm.sh" ] && nvm use default >/dev/null 2>&1
export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/ssh-agent.socket"

if [[ -z ${NVM_DIR:-} ]]; then
  export NVM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvm"
  if [[ ! -s "$NVM_DIR/nvm.sh" && -s "$HOME/.nvm/nvm.sh" ]]; then
    export NVM_DIR="$HOME/.nvm"
  fi
fi
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  source "$NVM_DIR/nvm.sh"
  nvm use default >/dev/null 2>&1
fi

# Preserve forwarded agents; the desktop socket does not exist on every host.
if [[ -z ${SSH_AUTH_SOCK:-} && -n ${XDG_RUNTIME_DIR:-} && -S "$XDG_RUNTIME_DIR/gcr/ssh" ]]; then
  export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gcr/ssh"
fi

typeset -U path
path=("$HOME/.local/bin" "$HOME/.cargo/bin" $path)
if [[ -d "$HOME/.dotnet" ]]; then
  export DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
fi

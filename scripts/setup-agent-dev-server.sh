#!/usr/bin/env bash
# Provision this Ubuntu server for agentic software development and testing.
#
# Research-informed principles used here:
# - Prefer reproducible project/devcontainer dependencies over global project tools.
# - Provide multiple browser engines whose versions match the installed Playwright CLI.
# - Prefer isolated, disposable test environments; never mount docker.sock into test containers.
# - Default development services to loopback and keep SSH/network hardening opt-in to avoid lockout.
# - Keep security relaxations opt-in.
#
# References:
#   https://docs.docker.com/ai/sandboxes/security/
#   https://docs.docker.com/engine/security/rootless/
#   https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html
#   https://playwright.dev/docs/ci
#   https://playwright.dev/docs/docker
#   https://containers.dev/
#   https://code.visualstudio.com/docs/remote/ssh
#   https://docs.github.com/en/actions/reference/security/secure-use
#   https://github.com/SWE-bench/SWE-bench

set -Eeuo pipefail

# ------------------------------ Configuration ------------------------------

INSTALL_BROWSER_MATRIX="${INSTALL_BROWSER_MATRIX:-1}"
INSTALL_DATABASE_CLIENTS="${INSTALL_DATABASE_CLIENTS:-1}"
INSTALL_EXTRA_LANGUAGES="${INSTALL_EXTRA_LANGUAGES:-1}"
INSTALL_VM_MOBILE_TOOLS="${INSTALL_VM_MOBILE_TOOLS:-0}"
INSTALL_DEVCONTAINER_CLI="${INSTALL_DEVCONTAINER_CLI:-1}"
INSTALL_PYTHON_CLI_TOOLS="${INSTALL_PYTHON_CLI_TOOLS:-1}"

TUNE_FILE_WATCHERS="${TUNE_FILE_WATCHERS:-1}"
ADD_DEVICE_GROUPS="${ADD_DEVICE_GROUPS:-1}"
UPGRADE_OS="${UPGRADE_OS:-1}"
REBOOT_NOW="${REBOOT_NOW:-0}"

# Rootless Docker materially reduces risk, but can affect Testcontainers and
# existing rootful Docker workflows. Enable after checking project compatibility.
CONFIGURE_ROOTLESS_DOCKER="${CONFIGURE_ROOTLESS_DOCKER:-0}"
REMOVE_ROOTFUL_DOCKER_ACCESS="${REMOVE_ROOTFUL_DOCKER_ACCESS:-0}"

# Network hardening is disabled by default to avoid locking out remote access.
HARDEN_SSH="${HARDEN_SSH:-0}"
ENABLE_UFW="${ENABLE_UFW:-0}"

# These weaken host isolation and should only be enabled for a demonstrated need.
ALLOW_UNPRIVILEGED_USERNS="${ALLOW_UNPRIVILEGED_USERNS:-0}"
RELAX_NATIVE_DEBUG_SECURITY="${RELAX_NATIVE_DEBUG_SECURITY:-0}"

# Set to 1 to undo the LXD/core26/snapd Snap installation from the prior audit.
REMOVE_ACCIDENTAL_LXD="${REMOVE_ACCIDENTAL_LXD:-0}"

# Pinned host CLI versions. Projects should additionally pin their own versions
# in lockfiles, devcontainer definitions, global.json, mise.toml, etc.
DEVCONTAINER_CLI_VERSION="${DEVCONTAINER_CLI_VERSION:-0.89.0}"
PNPM_VERSION="${PNPM_VERSION:-11.25.0}"
YARN_VERSION="${YARN_VERSION:-1.22.22}"
UV_VERSION="${UV_VERSION:-0.12.9}"
RUFF_VERSION="${RUFF_VERSION:-0.16.6}"
MYPY_VERSION="${MYPY_VERSION:-2.3.1}"
NOX_VERSION="${NOX_VERSION:-2026.8.17}"
PIP_AUDIT_VERSION="${PIP_AUDIT_VERSION:-2.10.1}"
PRE_COMMIT_VERSION="${PRE_COMMIT_VERSION:-4.6.2}"
DOTNET_SDK_VERSION="${DOTNET_SDK_VERSION:-10.0.302}"

# Optional Git identity. Authentication is intentionally not automated.
GIT_NAME="${GIT_NAME:-}"
GIT_EMAIL="${GIT_EMAIL:-}"

# ------------------------------- Utilities ---------------------------------

log() {
    printf '\n\033[1;34m==> %s\033[0m\n' "$*"
}

warn() {
    printf '\n\033[1;33mWARNING: %s\033[0m\n' "$*" >&2
}

die() {
    printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2
    exit 1
}

on_error() {
    local exit_code=$?
    printf '\nSetup failed at line %s with exit code %s.\n' "${BASH_LINENO[0]}" "$exit_code" >&2
    exit "$exit_code"
}
trap on_error ERR

[[ $EUID -ne 0 ]] || die "Run this as the normal development user, not root."

DEV_USER="$(id -un)"
DEV_UID="$(id -u)"
USER_HOME="$(getent passwd "$DEV_USER" | cut -d: -f6)"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || die "Cannot determine home for $DEV_USER"

export PATH="$USER_HOME/.local/bin:$PATH"

log "Requesting sudo access"
sudo -v

# ---------------------------- Operating system -----------------------------

log "Refreshing APT metadata"
sudo apt-get update

BASE_PACKAGES=(
    # Core build systems and compilers
    build-essential autoconf automake libtool cmake meson ninja-build
    pkg-config ccache clang clang-tools llvm-dev

    # Debugging, profiling, and diagnostics
    gdb lldb valgrind strace ltrace linux-tools-common

    # Common native build headers
    libbz2-dev libffi-dev liblzma-dev libreadline-dev libsqlite3-dev
    libssl-dev zlib1g-dev

    # Python and generic test tooling
    python3-dev python3-venv python3-pip pipx
    python3-pytest python3-coverage tox

    # Source control and remote collaboration
    git git-lfs gh openssh-client

    # Containers, reproducible environments, and rootless prerequisites
    docker.io docker-compose-v2 docker-buildx
    uidmap slirp4netns fuse-overlayfs rootlesskit

    # Shells, editors, task runners, and file watching
    bash zsh tmux screen neovim direnv just entr

    # Data, archive, and network utilities
    curl wget ca-certificates jq yq xmlstarlet ripgrep
    rsync zip unzip 7zip file lsof socat netcat-openbsd bind9-dnsutils httpie

    # Shell tests/quality and lightweight load testing
    shellcheck shfmt bats wrk hyperfine

    # Documentation, media, and code generation
    graphviz imagemagick ffmpeg protobuf-compiler

    # Headed/headless UI automation support
    xvfb openbox xdotool scrot xauth x11-utils x11-xserver-utils
    mesa-utils vulkan-tools pulseaudio-utils alsa-utils

    # Stable screenshot/font coverage
    fonts-liberation fonts-noto-color-emoji fonts-unifont fonts-freefont-ttf

    # Security administration/inspection; no policy is changed by installation
    apparmor-utils ufw
)

log "Installing baseline agent development packages"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${BASE_PACKAGES[@]}"

if [[ "$INSTALL_DATABASE_CLIENTS" == 1 ]]; then
    log "Installing database clients (servers should normally run ephemerally in containers)"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        sqlite3 postgresql-client default-mysql-client redis-tools
fi

if [[ "$INSTALL_EXTRA_LANGUAGES" == 1 ]]; then
    log "Installing broad language SDK coverage"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        openjdk-21-jdk golang-go rustup ruby-full \
        php-cli php-curl php-mbstring php-xml composer opam

    if command -v rustup >/dev/null 2>&1; then
        rustup toolchain install stable
        rustup default stable
    fi
fi

if [[ "$INSTALL_VM_MOBILE_TOOLS" == 1 ]]; then
    log "Installing optional VM and Android platform tools"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        qemu-system-x86 qemu-utils openjdk-21-jdk adb fastboot
    warn "ADB/Fastboot are installed, but this does not install Android Studio or an emulator image."
fi

if [[ "$UPGRADE_OS" == 1 ]]; then
    log "Installing available operating-system updates"
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
fi

# --------------------------- Language-level CLIs ----------------------------

if [[ -s "$USER_HOME/.nvm/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    source "$USER_HOME/.nvm/nvm.sh"
fi

if command -v corepack >/dev/null 2>&1; then
    log "Enabling pinned pnpm and Yarn through Corepack"
    corepack enable
    corepack install --global "pnpm@$PNPM_VERSION" "yarn@$YARN_VERSION"
else
    warn "Corepack is unavailable; npm remains usable, but pnpm/Yarn setup was skipped."
fi

if [[ "$INSTALL_DEVCONTAINER_CLI" == 1 ]]; then
    if command -v npm >/dev/null 2>&1; then
        log "Installing the pinned Dev Containers CLI"
        npm install --global "@devcontainers/cli@$DEVCONTAINER_CLI_VERSION"
    else
        warn "npm is unavailable; Dev Containers CLI installation skipped."
    fi
fi

if [[ "$INSTALL_PYTHON_CLI_TOOLS" == 1 ]]; then
    log "Installing pinned Python CLIs in isolated pipx environments"
    pipx install --force "uv==$UV_VERSION"
    pipx install --force "ruff==$RUFF_VERSION"
    pipx install --force "mypy==$MYPY_VERSION"
    pipx install --force "nox==$NOX_VERSION"
    pipx install --force "pip-audit==$PIP_AUDIT_VERSION"
    pipx install --force "pre-commit==$PRE_COMMIT_VERSION"
fi

# Preserve the project-required SDK even if Ubuntu's feature band is older.
if ! command -v dotnet >/dev/null 2>&1 || \
   ! dotnet --list-sdks 2>/dev/null | grep -q "^${DOTNET_SDK_VERSION//./\\.} "; then
    log "Installing .NET SDK $DOTNET_SDK_VERSION for the current user"
    dotnet_installer="$(mktemp)"
    curl --proto '=https' --tlsv1.2 -fsSL \
        https://dot.net/v1/dotnet-install.sh -o "$dotnet_installer"
    bash "$dotnet_installer" --version "$DOTNET_SDK_VERSION" --install-dir "$USER_HOME/.dotnet"
    rm -f "$dotnet_installer"
    mkdir -p "$USER_HOME/.local/bin"
    ln -sfn "$USER_HOME/.dotnet/dotnet" "$USER_HOME/.local/bin/dotnet"
fi

# ----------------------------- Browser testing -----------------------------

if [[ "$INSTALL_BROWSER_MATRIX" == 1 ]]; then
    PLAYWRIGHT="$USER_HOME/node_modules/.bin/playwright"
    if [[ -x "$PLAYWRIGHT" ]]; then
        log "Installing version-matched Playwright Chromium, Firefox, and WebKit"
        export PLAYWRIGHT_BROWSERS_PATH="$USER_HOME/.cache/ms-playwright"
        "$PLAYWRIGHT" install --with-deps chromium firefox webkit
    else
        warn "No Playwright CLI found at $PLAYWRIGHT. Install browsers from each project's locked Playwright version with: npx playwright install --with-deps"
    fi
fi

# ------------------------------ Host settings -------------------------------

if [[ "$ADD_DEVICE_GROUPS" == 1 ]]; then
    log "Granting the development user access to available KVM/GPU devices"
    for group in kvm video render; do
        if getent group "$group" >/dev/null 2>&1; then
            sudo usermod -aG "$group" "$DEV_USER"
        fi
    done
fi

if [[ "$TUNE_FILE_WATCHERS" == 1 ]]; then
    log "Configuring file watcher limits for IDEs and monorepos"
    sudo tee /etc/sysctl.d/90-agent-development.conf >/dev/null <<'SYSCTL'
# Exclude node_modules, build outputs, caches, and vendor trees in IDE settings
# before relying on higher limits. These are maxima, not preallocated memory.
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=1024
fs.inotify.max_queued_events=32768
SYSCTL
    sudo sysctl --load=/etc/sysctl.d/90-agent-development.conf
fi

install -d -m 700 "$USER_HOME/agent-runs"

# Install a safer helper for executing tests in a disposable container. It does
# not mount credentials, HOME, or docker.sock. Network is disabled unless the
# caller explicitly supplies --network.
log "Installing hardened agent-container-run helper"
sudo tee /usr/local/bin/agent-container-run >/dev/null <<'HELPER'
#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: agent-container-run [--network] IMAGE [COMMAND [ARG...]]

Runs IMAGE against the current directory with:
  - no Docker socket, host HOME, SSH keys, or credentials
  - no network by default (--network opts into ordinary bridge egress)
  - read-only container root filesystem
  - writable current workspace and ephemeral HOME/tmp
  - all Linux capabilities dropped and no-new-privileges enabled
  - CPU, memory, process, and shared-memory limits

The image must already contain the tools needed by the project.
EOF
}

network="none"
if [[ "${1:-}" == "--network" ]]; then
    network="bridge"
    shift
fi

[[ $# -ge 1 ]] || { usage >&2; exit 2; }
image="$1"
shift
workspace="$(pwd -P)"
tty=()
[[ -t 0 && -t 1 ]] && tty=(-it)

exec docker run --rm "${tty[@]}" \
    --init \
    --pull=never \
    --network="$network" \
    --user="$(id -u):$(id -g)" \
    --workdir=/workspace \
    --mount="type=bind,src=$workspace,dst=/workspace" \
    --read-only \
    --tmpfs=/tmp:rw,nosuid,nodev,exec,size=2g,mode=1777 \
    --tmpfs="/home/agent:rw,nosuid,nodev,exec,size=2g,uid=$(id -u),gid=$(id -g),mode=0700" \
    --env=HOME=/home/agent \
    --env=CI=true \
    --cap-drop=ALL \
    --security-opt=no-new-privileges:true \
    --pids-limit="${AGENT_CONTAINER_PIDS:-2048}" \
    --memory="${AGENT_CONTAINER_MEMORY:-10g}" \
    --cpus="${AGENT_CONTAINER_CPUS:-10}" \
    --shm-size="${AGENT_CONTAINER_SHM:-1g}" \
    "$image" "$@"
HELPER
sudo chmod 0755 /usr/local/bin/agent-container-run

# ---------------------------- Optional hardening ----------------------------

if [[ "$CONFIGURE_ROOTLESS_DOCKER" == 1 ]]; then
    log "Configuring rootless Docker for $DEV_USER"
    sudo loginctl enable-linger "$DEV_USER"
    export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$DEV_UID}"
    /usr/share/docker.io/contrib/dockerd-rootless-setuptool.sh install --force
    docker context use rootless

    if [[ "$REMOVE_ROOTFUL_DOCKER_ACCESS" == 1 ]]; then
        log "Removing $DEV_USER from the root-equivalent docker group"
        sudo gpasswd --delete "$DEV_USER" docker || true
        warn "The current login retains its old supplementary groups until logout/reboot."
    fi
fi

if [[ "$HARDEN_SSH" == 1 ]]; then
    [[ -s "$USER_HOME/.ssh/authorized_keys" ]] || \
        die "Refusing to disable password SSH because authorized_keys is missing or empty."

    log "Applying key-only SSH hardening while preserving local port forwarding"
    sudo tee /etc/ssh/sshd_config.d/90-agent-dev-server.conf >/dev/null <<'SSHD'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
GatewayPorts no
AllowTcpForwarding local
X11Forwarding no
SSHD
    sudo sshd -t
    sudo systemctl reload ssh
fi

if [[ "$ENABLE_UFW" == 1 ]]; then
    log "Enabling a default-deny inbound firewall while retaining SSH"
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow OpenSSH
    sudo ufw --force enable
fi

if [[ "$ALLOW_UNPRIVILEGED_USERNS" == 1 ]]; then
    warn "Disabling Ubuntu's AppArmor user-namespace restriction weakens host isolation."
    sudo tee /etc/sysctl.d/91-agent-development-userns.conf >/dev/null <<'USERNS'
kernel.apparmor_restrict_unprivileged_userns=0
USERNS
    sudo sysctl --load=/etc/sysctl.d/91-agent-development-userns.conf
fi

if [[ "$RELAX_NATIVE_DEBUG_SECURITY" == 1 ]]; then
    warn "Allowing broad ptrace and core dumps weakens host security."
    sudo tee /etc/sysctl.d/91-agent-development-debug.conf >/dev/null <<'DEBUGSYSCTL'
kernel.yama.ptrace_scope=0
DEBUGSYSCTL
    sudo tee /etc/security/limits.d/91-agent-development-core.conf >/dev/null <<DEBUGLIMITS
$DEV_USER soft core unlimited
$DEV_USER hard core unlimited
DEBUGLIMITS
    sudo sysctl --load=/etc/sysctl.d/91-agent-development-debug.conf
fi

# ------------------------------ User settings -------------------------------

if [[ -n "$GIT_NAME" && -n "$GIT_EMAIL" ]]; then
    log "Configuring Git identity"
    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    git config --global init.defaultBranch main
else
    warn "Git identity was not changed. Supply GIT_NAME and GIT_EMAIL if desired."
fi

# Authentication is deliberately interactive and excluded from unattended setup.
if command -v gh >/dev/null 2>&1 && ! gh auth status >/dev/null 2>&1; then
    warn "GitHub CLI is installed but not authenticated. Run 'gh auth login' interactively if needed."
fi

if [[ "$REMOVE_ACCIDENTAL_LXD" == 1 ]]; then
    log "Removing the LXD snaps installed during the previous audit"
    if snap list lxd >/dev/null 2>&1; then
        sudo snap remove --purge lxd
    fi
    if snap list core26 >/dev/null 2>&1; then
        sudo snap remove --purge core26 || warn "core26 is required by another snap."
    fi
    if snap list snapd >/dev/null 2>&1; then
        sudo snap remove --purge snapd || warn "The snap-packaged snapd could not be removed."
    fi
fi

# -------------------------------- Verify ------------------------------------

log "Tool verification"
check_tool() {
    local tool="$1"
    if command -v "$tool" >/dev/null 2>&1; then
        printf '  %-20s %s\n' "$tool" "$(command -v "$tool")"
    else
        printf '  %-20s MISSING\n' "$tool"
    fi
}

for tool in \
    git gh git-lfs curl wget jq yq rg shellcheck shfmt bats just direnv \
    gcc g++ clang clang++ cmake ctest ninja meson make gdb lldb valgrind \
    python3 pip3 pipx uv ruff mypy pytest tox nox pip-audit pre-commit \
    node npm corepack pnpm yarn devcontainer dotnet java javac go rustc cargo \
    ruby php composer opam docker sqlite3 psql mysql redis-cli \
    Xvfb openbox xdotool scrot ffmpeg convert; do
    check_tool "$tool"
done

if [[ -x "$USER_HOME/node_modules/.bin/playwright" ]]; then
    printf '\nPlaywright browser inventory:\n'
    "$USER_HOME/node_modules/.bin/playwright" install --list
fi

printf '\nDocker access is root-equivalent when using the rootful docker group.\n'
printf 'Never mount /var/run/docker.sock into an agent/test container.\n'
printf 'Use agent-container-run for untrusted or dependency-heavy test commands.\n'
printf 'Bind development servers to 127.0.0.1 unless remote exposure is deliberate.\n'

if [[ -e /var/run/reboot-required ]]; then
    warn "A reboot is required for the installed kernel and new group memberships."
fi

if [[ "$REBOOT_NOW" == 1 ]]; then
    log "Rebooting"
    sudo systemctl reboot
else
    log "Provisioning complete"
    echo "Log out and back in, or reboot, before relying on KVM/GPU/group changes."
fi

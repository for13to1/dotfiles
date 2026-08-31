#!/usr/bin/env bash
# _install/install-by-curl.sh — installs fnm, rustup, uv via official installers

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

download_installer() {
    curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location "$1"
}

install_fnm() {
    download_installer https://fnm.vercel.app/install | bash -s -- --skip-shell
}

install_rustup() {
    download_installer https://sh.rustup.rs | sh -s -- -y --no-modify-path
}

install_uv() {
    download_installer https://astral.sh/uv/install.sh | sh
}

main() {
    if ! is_installed fnm "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm"; then
        info "fnm not found; installing it via the official installer..."
        install_fnm
        ok "fnm installed"
    fi

    if ! is_installed rustup "$HOME/.cargo/bin/rustup"; then
        info "rustup not found; installing it via the official installer..."
        install_rustup
        ok "rustup installed"
    fi

    if ! is_installed uv "$HOME/.local/bin/uv"; then
        info "uv not found; installing it via the official installer..."
        install_uv
        ok "uv installed"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

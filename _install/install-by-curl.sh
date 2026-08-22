#!/usr/bin/env bash
# _install/install-by-curl.sh — tool managers via their official installers

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

install_fnm() {
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
}

install_rustup() {
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
}

install_uv() {
    curl -LsSf https://astral.sh/uv/install.sh | sh
}

main() {
    install_with_prompt \
        "fnm" \
        "fnm not found; install it via the official installer?" \
        "install_fnm" \
        "fnm installed" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm"

    install_with_prompt \
        "rustup" \
        "rustup not found; install it via the official installer?" \
        "install_rustup" \
        "rustup installed" \
        "$HOME/.cargo/bin/rustup"

    install_with_prompt \
        "uv" \
        "uv not found; install it via the official installer?" \
        "install_uv" \
        "uv installed" \
        "$HOME/.local/bin/uv"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

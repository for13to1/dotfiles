#!/usr/bin/env bash
# _install/install-by-uv.sh — Python CLI installs via uv tool

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

find_uv_bin() {
    if command -v uv &>/dev/null; then
        command -v uv
    elif [[ -x "$HOME/.local/bin/uv" ]]; then
        printf '%s\n' "$HOME/.local/bin/uv"
    fi
}

install_ruff() {
    local uv_bin
    uv_bin="$(find_uv_bin)" || return 1
    "$uv_bin" tool install ruff
}

main() {
    if [[ -z "$(find_uv_bin || true)" ]]; then
        warn "uv not found; skipping Python CLI installs"
        return 0
    fi

    install_with_prompt \
        "ruff" \
        "ruff not found; install it via uv tool?" \
        "install_ruff" \
        "ruff installed" \
        "$HOME/.local/bin/ruff"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

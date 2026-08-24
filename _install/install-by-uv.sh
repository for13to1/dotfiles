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

install_ytdlp() {
    local uv_bin
    uv_bin="$(find_uv_bin)" || return 1
    "$uv_bin" tool install yt-dlp
}

main() {
    if [[ -z "$(find_uv_bin || true)" ]]; then
        warn "uv not found; skipping Python CLI installs"
        return 0
    fi

    if ! is_installed ruff "$HOME/.local/bin/ruff"; then
        info "ruff not found; installing it via uv tool..."
        install_ruff
        ok "ruff installed"
    fi

    if ! is_installed yt-dlp "$HOME/.local/bin/yt-dlp"; then
        info "yt-dlp not found; installing it via uv tool..."
        install_ytdlp
        ok "yt-dlp installed"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

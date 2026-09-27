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

# The single uv-channel installer. uv tool install needs no per-tool flags
# today, so $2 is reserved for future use.
uv_install_one() {
    local uv_bin
    uv_bin="$(find_uv_bin)" || return 1
    "$uv_bin" tool install "$1"
}

# ── uv CLI registry ──────────────────────────────────────────────
eco_cli ruff    ruff    ""  --always
eco_cli yt-dlp  yt-dlp  ""  --always

main() {
    validate_cli_registry

    if [[ -z "$(find_uv_bin || true)" ]]; then
        warn "uv not found; skipping Python CLI installs"
        return 0
    fi

    run_cli_registry uv_install_one "uv tool" path
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

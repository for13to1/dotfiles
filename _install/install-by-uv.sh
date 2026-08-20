#!/usr/bin/env bash
# _install/install-by-uv.sh — uv tool 途径的 Python CLI 安装

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
    is_debian_like || return 0

    if [[ -z "$(find_uv_bin || true)" ]]; then
        warn "未检测到 uv，Python CLI 安装跳过"
        return 0
    fi

    install_with_prompt \
        "ruff" \
        "未检测到 ruff，是否通过 uv tool 安装？" \
        "install_ruff" \
        "ruff 安装完成" \
        "$HOME/.local/bin/ruff"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

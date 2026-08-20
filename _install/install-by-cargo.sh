#!/usr/bin/env bash
# _install/install-by-cargo.sh — Cargo 途径的 Rust CLI 安装

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

find_cargo_bin() {
    if command -v cargo &>/dev/null; then
        command -v cargo
    elif [[ -x "$HOME/.cargo/bin/cargo" ]]; then
        printf '%s\n' "$HOME/.cargo/bin/cargo"
    fi
}

install_stylua() {
    local cargo_bin
    cargo_bin="$(find_cargo_bin)" || return 1
    "$cargo_bin" install stylua --features lua54
}

main() {
    is_debian_like || return 0

    if [[ -z "$(find_cargo_bin || true)" ]]; then
        warn "未检测到 cargo，Rust CLI 安装跳过"
        return 0
    fi

    install_with_prompt \
        "stylua" \
        "未检测到 stylua，是否通过 cargo 安装？（需要本地编译）" \
        "install_stylua" \
        "stylua 安装完成" \
        "$HOME/.cargo/bin/stylua"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

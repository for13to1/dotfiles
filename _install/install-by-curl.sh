#!/usr/bin/env bash
# _install/install-by-curl.sh — 语言生态包管理器（fnm/rustup/uv）途径的软件安装

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

install_with_prompt \
    "fnm" \
    "未检测到 fnm，是否通过官网安装器安装？" \
    "install_fnm" \
    "fnm 安装完成" \
    "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm"

install_with_prompt \
    "rustup" \
    "未检测到 rustup，是否通过官网安装器安装？" \
    "install_rustup" \
    "rustup 安装完成" \
    "$HOME/.cargo/bin/rustup"

install_with_prompt \
    "uv" \
    "未检测到 uv，是否通过官网安装器安装？" \
    "install_uv" \
    "uv 安装完成" \
    "$HOME/.local/bin/uv"

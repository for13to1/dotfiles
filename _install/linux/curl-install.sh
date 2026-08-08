#!/usr/bin/env bash
# _install/linux/curl-install.sh — 语言生态包管理器（fnm/rustup/uv）途径的软件安装

set -euo pipefail

# ── 彩色输出 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; exit 1; }

# 仅在 Debian / Ubuntu 路线下接管工具链管理器的官网安装器。
is_debian_like=false
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    if [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" || "${ID_LIKE:-}" == *"debian"* ]]; then
        is_debian_like=true
    fi
fi

install_with_prompt() {
    local check_cmd="$1"
    local known_paths="$2"
    local prompt="$3"
    local install_fn="$4"
    local success_msg="$5"

    if command -v "$check_cmd" &>/dev/null; then
        return 0
    fi

    local p
    for p in $known_paths; do
        [[ -x "$p" ]] && return 0
    done

    if ! $is_debian_like; then
        return 0
    fi

    warn "$prompt"
    read -rp "是否现在安装？ [y/N]: " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        if "$install_fn"; then
            ok "$success_msg"
        else
            warn "安装未完成，请稍后手动重试"
        fi
    fi
}

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
    "fnm" "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm" \
    "未检测到 fnm，是否通过官网安装器安装？" \
    "install_fnm" \
    "fnm 安装完成"

install_with_prompt \
    "rustup" "$HOME/.cargo/bin/rustup" \
    "未检测到 rustup，是否通过官网安装器安装？" \
    "install_rustup" \
    "rustup 安装完成"

install_with_prompt \
    "uv" "$HOME/.local/bin/uv" \
    "未检测到 uv，是否通过官网安装器安装？" \
    "install_uv" \
    "uv 安装完成"

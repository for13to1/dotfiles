#!/usr/bin/env bash
# _install/linux/curl-install.sh — 非系统包管理器途径的软件安装

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
    local prompt="$2"
    local install_fn="$3"
    local success_msg="$4"

    if command -v "$check_cmd" &>/dev/null; then
        return 0
    fi

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

install_with_prompt \
    "fnm" \
    "未检测到 fnm，是否通过官网安装器安装？" \
    "install_fnm" \
    "fnm 安装完成"

install_with_prompt \
    "rustup" \
    "未检测到 rustup，是否通过官网安装器安装？" \
    "install_rustup" \
    "rustup 安装完成"

if $is_debian_like && ! command -v node &>/dev/null && command -v fnm &>/dev/null; then
    info "已安装 fnm，但尚未检测到 Node。你之后可以运行: fnm install --lts"
fi

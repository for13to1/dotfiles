#!/usr/bin/env bash
# _scripts/common.sh — 跨脚本共享的 shell 基础设施（仅允许被 source 加载）

# 防止被当作脚本直接执行
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "common.sh 是共享库，请用 source 加载" >&2
    exit 1
fi

# ── 彩色输出 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── 发行版检测 ────────────────────────────────────────────────────
# Debian / Ubuntu 系返回 0。
is_debian_like() {
    [[ -r /etc/os-release ]] || return 1
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" || "${ID_LIKE:-}" == *"debian"* ]]
}

# ── 已装判断 ──────────────────────────────────────────────────────
# 命令在 PATH 上，或任一已知安装路径可执行，即视为已装。
is_installed() {
    local cmd="$1"; shift
    command -v "$cmd" &>/dev/null && return 0
    local p
    for p in "$@"; do
        [[ -x "$p" ]] && return 0
    done
    return 1
}

# ── 交互式安装 ────────────────────────────────────────────────────
# 用法: install_with_prompt <check_cmd> <prompt> <install_fn> <success_msg> [known_paths...]
# 已装（command -v 或已知路径存在）则跳过；非 Debian 系也跳过。
install_with_prompt() {
    local check_cmd="$1" prompt="$2" install_fn="$3" success_msg="$4"
    shift 4

    is_installed "$check_cmd" "$@" && return 0

    is_debian_like || return 0

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

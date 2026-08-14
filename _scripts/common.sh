#!/usr/bin/env bash
# _scripts/common.sh — 跨脚本共享的 shell 基础设施（仅允许被 source 加载）

# 防止被当作脚本直接执行
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "common.sh 是共享库，请用 source 加载" >&2
    exit 1
fi

# ── 彩色输出 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# msg <level> <text>: 统一打印入口，level 取 info|ok|warn|error。
msg() {
    local level="$1"
    shift
    case "$level" in
        info)  echo -e "${BLUE}ℹ️  $*${NC}" ;;
        ok)    echo -e "${GREEN}✅ $*${NC}" ;;
        warn)  echo -e "${YELLOW}⚠️  $*${NC}" ;;
        error) echo -e "${RED}❌ $*${NC}" ;;
        *)     echo -e "$*" ;;
    esac
}

info()      { msg 'info'  "$*"; }
ok()        { msg 'ok'    "$*"; }
warn()      { msg 'warn'  "$*"; }
# error_msg 仅打印错误信息不退出；error 在其基础上终止脚本。
error_msg() { msg 'error' "$*"; }
error()     { error_msg "$*"; exit 1; }

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

# ── Stow 路径与忽略规则 ───────────────────────────────────────────
# 这些目录/文件不参与 Stow 检查、备份和挂载。
STOW_IGNORE_NAMES=(
    "__pycache__"
    ".pytest_cache"
    ".ruff_cache"
    ".mypy_cache"
    ".venv"
    ".stow-local-ignore"
    ".DS_Store"
    ".git"
    ".gitignore"
    "history.json"
)

# find 的 Stow 版包装：统一追加忽略规则与 NUL 输出。
stow_find() {
    local root="$1"
    shift
    local -a args=(find "$root" "$@")
    local name
    for name in "${STOW_IGNORE_NAMES[@]}"; do
        args+=( -name "$name" -prune -o )
    done
    args+=( -print0 )
    "${args[@]}"
}

physical_path() {
    local path="$1"
    printf '%s' "$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path")"
}

resolved_link_target() {
    local target="$1" link
    link="$(readlink "$target")"
    [[ "$link" == /* ]] || link="$(dirname "$target")/$link"
    physical_path "$link"
}

# ── 非交互式输入 ──────────────────────────────────────────────────
# DOTFILES_NON_INTERACTIVE=1 时直接返回默认值，不读取 stdin。
ask_value() {
    local prompt="$1" default="$2" reply
    if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
        printf '%s\n' "$default"
        return 0
    fi
    read -rp "$prompt" reply || true
    printf '%s\n' "${reply:-$default}"
}

# default: 1 = 是（回车/非交互返回 0），0 = 否（返回 1）
confirm() {
    local prompt="$1" default="$2" reply
    local default_ret=$((1 - default))
    if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
        return "$default_ret"
    fi
    read -rp "$prompt" reply || return "$default_ret"
    [[ -z "$reply" ]] && return "$default_ret"
    [[ "$reply" =~ ^[Yy](es)?$ ]]
}

# ── 主题清单合并去重 ──────────────────────────────────────────────
# 主题清单读取：跳过 # 开头的注释行与空行（apt/pacman 纯包名，brew 为 brew/cask 行）。
theme_list_lines() {
    grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -v '^[[:space:]]*$' || true
}

# 通用保序去重（stdin → stdout）：按整行去重，保留首次出现的行。
dedupe_lines() {
    awk '!seen[$0]++'
}

# Brewfile 去重（stdin → stdout）：按「brew/cask + 包名」去重，保留首次出现的完整行
# （含 restart_service 等选项）；非 brew/cask 行原样透传。
# 仅用 awk 基础特性，兼容 macOS 自带 BSD awk。
dedupe_brewfile() {
    awk '
        /^[[:space:]]*(brew|cask)[[:space:]]+"[^"]+"/ {
            name = $2
            sub(/,.*/, "", name)
            key = $1 " " name
            if (seen[key]++) next
        }
        { print }
    '
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
    if confirm "是否现在安装？ [y/N]: " 0; then
        if "$install_fn"; then
            ok "$success_msg"
        else
            warn "安装未完成，请稍后手动重试"
        fi
    fi
}

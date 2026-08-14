#!/usr/bin/env bash
# _install/install-by-npm.sh — npm 生态工具链安装（复用本地 fnm/Node 环境）

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../_scripts/common.sh"

# 仅在 Debian / Ubuntu 路线下接管 npm 生态工具链安装。
is_debian_like || exit 0

# ── Node 环境激活 ─────────────────────────────────────────────────
# 复用本地 fnm 管理的 Node，不自装运行时。所有 Node/npm 调用都通过
# fnm exec 进入指定运行时，避免依赖 fnm multishell 的内部路径布局。
FNM_BIN=""

find_fnm_bin() {
    if command -v fnm &>/dev/null; then
        command -v fnm
    elif [[ -x "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm" ]]; then
        printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm"
    fi
}

fnm_exec() {
    "$FNM_BIN" exec --using lts-latest -- "$@"
}

ensure_fnm_node_env() {
    FNM_BIN="$(find_fnm_bin || true)"
    if [[ -z "$FNM_BIN" ]]; then
        warn "未检测到 fnm，npm 生态工具链安装跳过"
        return 1
    fi

    info "检测到 fnm，正在准备 Node LTS 环境..."
    "$FNM_BIN" install --lts &>/dev/null || true
    "$FNM_BIN" default lts-latest &>/dev/null || true

    if fnm_exec node --version &>/dev/null; then
        ok "fnm Node $(fnm_exec node --version) 已就绪"
        return 0
    fi

    warn "Node 环境准备失败，请稍后手动运行: fnm install --lts"
    return 1
}

install_pi() {
    # npm >= 11.10 引入 release-age 门禁，官方安装器用 --min-release-age=0 绕过
    local npm_version
    local -a extra=()
    npm_version="$(fnm_exec npm --version)"
    if awk -F. '{ exit !($1 > 11 || ($1 == 11 && $2 >= 10)) }' <<<"$npm_version"; then
        extra=(--min-release-age=0)
    fi
    fnm_exec npm install -g --ignore-scripts "${extra[@]}" @earendil-works/pi-coding-agent
}

if ! ensure_fnm_node_env; then
    exit 0
fi

if ! fnm_exec npm --version &>/dev/null; then
    warn "未检测到 npm，npm 生态工具链安装跳过"
    exit 0
fi

install_with_prompt \
    "pi" \
    "未检测到 pi，是否通过 npm 安装？" \
    "install_pi" \
    "pi 安装完成"

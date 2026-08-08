#!/usr/bin/env bash
# _install/linux/npm-install.sh — npm 生态工具链安装（复用本地 fnm/Node 环境）

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../_scripts/common.sh"

# 仅在 Debian / Ubuntu 路线下接管 npm 生态工具链安装。
is_debian_like || exit 0

# ── Node 环境激活 ─────────────────────────────────────────────────
# 复用本地 fnm 管理的 Node，不自装运行时。fnm 安装时带 --skip-shell，
# 且 bootstrap 在 bash 下运行，这里显式激活一次。
find_fnm_bin() {
    if command -v fnm &>/dev/null; then
        command -v fnm
    elif [[ -x "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm" ]]; then
        printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm"
    fi
}

node_from_fnm() {
    local node_bin fnm_root
    node_bin="$(command -v node 2>/dev/null || true)"
    [[ -n "$node_bin" ]] || return 1

    fnm_root="${FNM_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/fnm}"
    case "$node_bin" in
        "$fnm_root"/*|"${XDG_STATE_HOME:-$HOME/.local/state}/fnm_multishells"/*)
            return 0
            ;;
    esac

    return 1
}

ensure_node_env() {
    local fnm_bin
    fnm_bin="$(find_fnm_bin || true)"
    if [[ -z "$fnm_bin" ]]; then
        warn "未检测到 fnm，npm 生态工具链安装跳过"
        return 1
    fi

    info "检测到 fnm，正在激活 Node LTS 环境..."
    "$fnm_bin" install --lts &>/dev/null || true
    "$fnm_bin" default lts-latest &>/dev/null || true
    eval "$("$fnm_bin" env --use-on-cd --shell bash 2>/dev/null)" || true
    "$fnm_bin" use lts-latest &>/dev/null || true

    if node_from_fnm; then
        ok "fnm Node $(node --version) 已就绪"
        return 0
    fi

    if command -v node &>/dev/null; then
        warn "当前 node 不来自 fnm，npm 生态工具链安装跳过: $(command -v node)"
    else
        warn "Node 环境激活失败，请稍后手动运行: fnm install --lts"
    fi
    return 1
}

node_version_ok() {
    local ver major minor
    ver="$(node --version 2>/dev/null)"; ver="${ver#v}"
    major="${ver%%.*}"; minor="${ver#*.}"; minor="${minor%%.*}"
    [[ -n "$major" && -n "$minor" ]] || return 1
    [[ "$major" -gt 22 ]] || { [[ "$major" -eq 22 ]] && [[ "$minor" -ge 19 ]]; }
}

install_pi() {
    # npm >= 11.10 引入 release-age 门禁，官方安装器用 --min-release-age=0 绕过
    local -a extra=()
    if awk -F. '{ exit !($1 > 11 || ($1 == 11 && $2 >= 10)) }' <<<"$(npm --version)"; then
        extra=(--min-release-age=0)
    fi
    npm install -g --ignore-scripts "${extra[@]}" @earendil-works/pi-coding-agent
}

if ! ensure_node_env; then
    exit 0
fi

if ! command -v npm &>/dev/null; then
    warn "未检测到 npm，npm 生态工具链安装跳过"
    exit 0
fi

if ! node_version_ok; then
    warn "Node 版本过低（需要 >= 22.19），当前: $(node --version)。请通过 fnm 升级 Node"
    exit 0
fi

install_with_prompt \
    "pi" \
    "未检测到 pi，是否通过 npm 安装？" \
    "install_pi" \
    "pi 安装完成"

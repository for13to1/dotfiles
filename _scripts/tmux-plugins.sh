#!/usr/bin/env bash
#
# _scripts/tmux-plugins.sh — 同步 tmux 插件
#
# 安装 tpm，并同步 ~/.tmux.conf 中声明的插件。
# 用法: bash _scripts/tmux-plugins.sh
#

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

command -v tmux &>/dev/null || error "未安装 tmux，无法安装 tmux 插件"
[[ -f "$HOME/.tmux.conf" ]] \
    || error "未找到 ~/.tmux.conf（请先完成 Stow 挂载），无法安装 tmux 插件"

# 与 tmux/.tmux.conf 的 fallback 路径保持一致，并供新 server 继承。
export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"

# 返回包含 bin/install_plugins 的 tpm 根目录。
find_tpm() {
    if [[ -x "$TMUX_PLUGIN_MANAGER_PATH/tpm/bin/install_plugins" ]]; then
        printf '%s\n' "$TMUX_PLUGIN_MANAGER_PATH/tpm"
        return 0
    fi
    # 测试时隔离宿主机已安装的 tpm。
    if [[ -n "${DOTFILES_TMUX_NO_SYSTEM_TPM:-}" ]]; then
        return 1
    fi
    case "$(uname -s)" in
        Darwin)
            if [[ -x "/opt/homebrew/opt/tpm/share/tpm/bin/install_plugins" ]]; then
                printf '%s\n' "/opt/homebrew/opt/tpm/share/tpm"
                return 0
            fi
            if [[ -x "/usr/local/opt/tpm/share/tpm/bin/install_plugins" ]]; then
                printf '%s\n' "/usr/local/opt/tpm/share/tpm"
                return 0
            fi
            ;;
    esac
    if is_debian_like; then
        if [[ -x "/usr/share/tmux-plugin-manager/bin/install_plugins" ]]; then
            printf '%s\n' "/usr/share/tmux-plugin-manager"
            return 0
        fi
    fi
    return 1
}

if ! TPM_DIR="$(find_tpm)"; then
    mkdir -p "$TMUX_PLUGIN_MANAGER_PATH"
    TPM_DIR="$TMUX_PLUGIN_MANAGER_PATH/tpm"
    if [[ -e "$TPM_DIR" ]]; then
        error "发现不完整的 tpm 目录: $TPM_DIR，请删除后重试"
    fi
    info "未找到 tpm，正在克隆到 $TPM_DIR ..."
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" \
        || error "tpm 克隆失败"
fi
info "使用 tpm: $TPM_DIR"

# 已有 server 时更新其环境；无 server 时由 tpm 继承导出的默认路径。
tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$TMUX_PLUGIN_MANAGER_PATH" 2>/dev/null || true
info "正在安装 tmux 插件（已安装的自动跳过）..."
bash "$TPM_DIR/bin/install_plugins"
ok "tmux 插件同步完成"

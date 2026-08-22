#!/usr/bin/env bash
# Ensure Oh My Zsh, plugins, default shell, and local shell config.
# Usage: shell.sh <os> [selected-brew-mirror]
# Inputs: detected OS and mirror choice from bootstrap; HOME/SHELL/non-interactive mode from the environment.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

omz_install_plugin() {
    local name="$1" url="$2"
    if [[ ! -d "$ZSH_CUSTOM/plugins/$name" ]]; then
        info "正在安装 OMZ 插件: $name..."
        git clone "$url" "$ZSH_CUSTOM/plugins/$name"
        ok "$name 安装完毕"
    else
        ok "$name 已存在，跳过"
    fi
}

write_local_config() {
    local os="$1" selected_mirror="$2"

    [[ -f "$HOME/.zshrc.local" ]] && return 0
    info "正在生成 ~/.zshrc.local 示例模板..."
    printf '%s\n' '# ~/.zshrc.local — 本地配置，不纳入版本控制，可按需修改' > "$HOME/.zshrc.local"

    if [[ "$os" == Darwin* ]]; then
        printf '\n%s\n%s\n%s\n' \
            '# ==========================================================' \
            '# Homebrew 镜像源切换 (函数定义见 ~/.zsh.d/brew_mirror.sh)' \
            '# ==========================================================' >> "$HOME/.zshrc.local"
        if [[ -n "$selected_mirror" ]]; then
            printf 'brew_mirror -q %s\n' "$selected_mirror" >> "$HOME/.zshrc.local"
        else
            printf '%s\n' '# brew_mirror -q ustc  # 取消注释以启用 USTC 镜像源' >> "$HOME/.zshrc.local"
        fi
    fi

    cat >> "$HOME/.zshrc.local" <<'EOF'

# ==========================================================
# API Keys
# ==========================================================
# export OPENAI_API_KEY="sk-..."
# export OPENAI_BASE_URL="https://api.openai.com/v1"

# export ANTHROPIC_API_KEY="sk-ant-..."
# export ANTHROPIC_BASE_URL="https://api.anthropic.com"

# export GEMINI_API_KEY="your-api-key"
# export GEMINI_BASE_URL="https://generativelanguage.googleapis.com"
EOF
    ok "$HOME/.zshrc.local 示例模板已生成"
}

main() {
    local os="${1:-}" selected_mirror="${2:-}"
    local zsh_path

    [[ -n "$os" ]] || error "用法: $0 <os> [selected-brew-mirror]"
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        info "正在安装 Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        ok "Oh My Zsh 安装完毕"
    else
        ok "Oh My Zsh 已存在，跳过"
    fi

    if [[ "${SHELL:-}" != *"zsh"* ]] && command -v zsh &>/dev/null; then
        zsh_path="$(command -v zsh)"
        if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
            info "非交互模式跳过默认 Shell 切换；请稍后手动执行: chsh -s $zsh_path"
        else
            info "检测到当前默认 Shell 不是 zsh，正在尝试为您切换..."
            if ! grep -Fxq "$zsh_path" /etc/shells; then
                warn "Zsh 路径 ($zsh_path) 不在 /etc/shells 中，正在添加..."
                echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
            fi
            chsh -s "$zsh_path" || warn "切换默认 Shell 失败，您可以稍后手动执行: chsh -s $zsh_path"
            ok "已退出 chsh 流程"
        fi
    fi

    ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    omz_install_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions
    omz_install_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting
    write_local_config "$os" "$selected_mirror"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

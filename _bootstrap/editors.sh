#!/usr/bin/env bash
# synchronize optional Neovim and Vim plugins.
# Usage: editors.sh
# Inputs: HOME and DOTFILES_NON_INTERACTIVE from the environment; interactive choice on stdin.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

main() {
    local editor_choice

    if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
        info "非交互模式，跳过编辑器插件同步"
        return 0
    fi

    info "📋 请选择要同步的编辑器插件："
    echo "   1) Neovim (lazy.nvim) - [默认]"
    echo "   2) Vim (vim-plug)"
    echo "   3) 两者都要"
    echo "   4) 跳过"
    editor_choice="$(ask_value "请输入数字 [1-4]: " "1")"

    if [[ "$editor_choice" == "1" || "$editor_choice" == "3" ]]; then
        if command -v nvim &>/dev/null; then
            info "正在同步 Neovim 插件 (lazy.nvim)..."
            nvim --headless "+Lazy! sync" +qa || warn "Neovim 插件同步过程中有报错，请稍后手动打开 nvim 查看"
            ok "Neovim 插件就绪"
        fi
    fi

    if [[ "$editor_choice" == "2" || "$editor_choice" == "3" ]]; then
        if [[ ! -f "$HOME/.vim/autoload/plug.vim" ]]; then
            info "正在安装 vim-plug..."
            curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
                https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
            ok "vim-plug 安装完毕"
        else
            ok "vim-plug 已存在，跳过"
        fi

        if command -v vim &>/dev/null; then
            if vim -Nu "$HOME/.vimrc" -n -es \
                '+if !exists(":PlugInstall") | cquit 2 | endif' '+qa!'; then
                info "正在安装/更新 Vim 插件..."
                if vim -Nu "$HOME/.vimrc" -n -es '+PlugUpdate --sync' '+qa!'; then
                    ok "Vim 插件就绪"
                else
                    warn "Vim 插件同步失败，请检查上方输出后重试"
                fi
            else
                warn "vim-plug 未能加载，请检查 ~/.vimrc 与 runtimepath"
            fi
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

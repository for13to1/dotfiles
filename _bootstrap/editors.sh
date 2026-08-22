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
        info "Non-interactive mode; skipping editor plugin sync"
        return 0
    fi

    info "📋 Select the editor plugins to sync:"
    echo "   1) Neovim (lazy.nvim) - [default]"
    echo "   2) Vim (vim-plug)"
    echo "   3) Both"
    echo "   4) Skip"
    editor_choice="$(ask_value "Enter a number [1-4]: " "1")"

    if [[ "$editor_choice" == "1" || "$editor_choice" == "3" ]]; then
        if command -v nvim &>/dev/null; then
            info "Syncing Neovim plugins (lazy.nvim)..."
            nvim --headless "+Lazy! sync" +qa || warn "Neovim plugin sync had errors; open nvim manually to inspect"
            ok "Neovim plugins ready"
        fi
    fi

    if [[ "$editor_choice" == "2" || "$editor_choice" == "3" ]]; then
        if [[ ! -f "$HOME/.vim/autoload/plug.vim" ]]; then
            info "Installing vim-plug..."
            curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
                https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
            ok "vim-plug installed"
        else
            ok "vim-plug already present; skipping"
        fi

        if command -v vim &>/dev/null; then
            if vim -Nu "$HOME/.vimrc" -n -es \
                '+if !exists(":PlugInstall") | cquit 2 | endif' '+qa!'; then
                info "Installing/updating Vim plugins..."
                if vim -Nu "$HOME/.vimrc" -n -es '+PlugUpdate --sync' '+qa!'; then
                    ok "Vim plugins ready"
                else
                    warn "Vim plugin sync failed; check the output above and retry"
                fi
            else
                warn "vim-plug failed to load; check ~/.vimrc and runtimepath"
            fi
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

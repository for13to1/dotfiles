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
        info "Installing OMZ plugin: $name..."
        git clone "$url" "$ZSH_CUSTOM/plugins/$name"
        ok "$name installed"
    else
        ok "$name already present; skipping"
    fi
}

write_local_config() {
    local os="$1" selected_mirror="$2"

    [[ -f "$HOME/.zshrc.local" ]] && return 0
    info "Generating the ~/.zshrc.local example template..."
    printf '%s\n' '# ~/.zshrc.local — local config, not version controlled, edit as needed' > "$HOME/.zshrc.local"

    if [[ "$os" == Darwin* ]]; then
        printf '\n%s\n%s\n%s\n' \
            '# ==========================================================' \
            '# Homebrew mirror switch (function defined in ~/.zsh.d/brew_mirror.sh)' \
            '# ==========================================================' >> "$HOME/.zshrc.local"
        if [[ -n "$selected_mirror" ]]; then
            printf 'brew_mirror -q %s\n' "$selected_mirror" >> "$HOME/.zshrc.local"
        else
            printf '%s\n' '# brew_mirror -q ustc  # uncomment to enable the USTC mirror' >> "$HOME/.zshrc.local"
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
    ok "$HOME/.zshrc.local example template created"
}

main() {
    local os="${1:-}" selected_mirror="${2:-}"
    local zsh_path

    [[ -n "$os" ]] || error "Usage: $0 <os> [selected-brew-mirror]"
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        info "Installing Oh My Zsh..."
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        ok "Oh My Zsh installed"
    else
        ok "Oh My Zsh already present; skipping"
    fi

    if [[ "${SHELL:-}" != *"zsh"* ]] && command -v zsh &>/dev/null; then
        zsh_path="$(command -v zsh)"
        if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
            info "Skipping the default shell switch in non-interactive mode; run 'chsh -s $zsh_path' manually later"
        else
            info "The default shell is not zsh; attempting to switch it for you..."
            if ! grep -Fxq "$zsh_path" /etc/shells; then
                warn "Zsh path ($zsh_path) is not in /etc/shells; adding it..."
                echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
            fi
            chsh -s "$zsh_path" || warn "Default shell switch failed; run 'chsh -s $zsh_path' manually later"
            ok "chsh flow finished"
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

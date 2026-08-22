#!/usr/bin/env bash
#
# _scripts/tmux-plugins.sh — sync tmux plugins
#
# Install tpm and sync the plugins declared in ~/.tmux.conf.
# Usage: bash _scripts/tmux-plugins.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

command -v tmux &>/dev/null || error "tmux is not installed; cannot install tmux plugins"
[[ -f "$HOME/.tmux.conf" ]] \
    || error "$HOME/.tmux.conf not found (finish the Stow mount first); cannot install tmux plugins"

# Match the fallback path in tmux/.tmux.conf and let new servers inherit it.
export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"

# Return the tpm root that contains bin/install_plugins.
find_tpm() {
    if [[ -x "$TMUX_PLUGIN_MANAGER_PATH/tpm/bin/install_plugins" ]]; then
        printf '%s\n' "$TMUX_PLUGIN_MANAGER_PATH/tpm"
        return 0
    fi
    # Isolate the host's already-installed tpm during tests.
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
        error "Incomplete tpm dir found: $TPM_DIR; remove it and retry"
    fi
    info "tpm not found; cloning to $TPM_DIR ..."
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" \
        || error "tpm clone failed"
fi
info "Using tpm: $TPM_DIR"

# For an existing server, refresh its environment; when no server is running, tpm
# inherits the exported default path.
tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$TMUX_PLUGIN_MANAGER_PATH" 2>/dev/null || true
info "Installing tmux plugins (already-installed are skipped)..."
bash "$TPM_DIR/bin/install_plugins"
ok "tmux plugin sync complete"

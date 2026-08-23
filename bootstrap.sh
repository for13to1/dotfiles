#!/usr/bin/env bash
#
# bootstrap.sh — one-shot development environment bootstrap
# Usage: git clone https://github.com/for13to1/dotfiles.git ~/dotfiles
#        cd ~/dotfiles && bash bootstrap.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ── Shared infrastructure (colored output etc., see _scripts/common.sh) ─
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_scripts/common.sh"

# ── 1. Detect the operating system ──────────────────────────────
OS="$(uname -s)"
info "Detected OS: $OS"

# ── 2. Package manager & environment bootstrap ────────────────
SELECTED_MIRROR=""
case "$OS" in
    Darwin*)
        if ! SELECTED_MIRROR="$(bash "$DOTFILES_DIR/_bootstrap/pkg-mac.sh" "$DOTFILES_DIR")"; then
            error "macOS package bootstrap did not complete. Please address the requirements above and rerun bootstrap.sh."
        fi
        ;;
    Linux*)
        if ! bash "$DOTFILES_DIR/_bootstrap/pkg-linux.sh" "$DOTFILES_DIR"; then
            error "Linux package bootstrap did not complete. Please address the requirements above and rerun bootstrap.sh."
        fi
        ;;
    *)
        error "Unsupported OS: $OS"
        ;;
esac

# ── 3-5. Host base configuration ────────────────────────────────
bash "$DOTFILES_DIR/_bootstrap/ssh.sh"
bash "$DOTFILES_DIR/_bootstrap/git.sh" "$DOTFILES_DIR"
bash "$DOTFILES_DIR/_bootstrap/shell.sh" "$OS" "${SELECTED_MIRROR:-}"

# ── 6. Mount configuration files (Stow) ─────────────────────────
info "Mounting configuration files with Stow..."

## 1. Resolve the module list (single source of truth, see _scripts/modules.conf).
# The module list is emitted one module per line and read into an array.
STOW_MODULES=()
if [[ -f "$DOTFILES_DIR/_scripts/modules.conf" && -f "$DOTFILES_DIR/_scripts/list-modules.sh" ]]; then
    # macOS ships bash 3.2 without mapfile, so use a while-read loop.
    while IFS= read -r _module; do
        STOW_MODULES+=("$_module")
    done < <(bash "$DOTFILES_DIR/_scripts/list-modules.sh" "$DOTFILES_DIR/_scripts/modules.conf")
    unset _module
fi

if (( ${#STOW_MODULES[@]} == 0 )); then
    warn "No modules found in _scripts/modules.conf; nothing to mount"
else
    info "Loaded modules from _scripts/modules.conf: ${STOW_MODULES[*]}"
fi

## 2. Run the Stow mount.
# The single entry point handles preflight, conflict backup, shared dir creation,
# `stow -R`, and post-mount verification. Mount failures only warn, never block.
if bash "$DOTFILES_DIR/_scripts/stow-sync.sh" \
    "$DOTFILES_DIR" "$HOME" "${STOW_MODULES[@]}"; then
    ok "Stow configuration mounted"
else
    warn "Stow mount had failures (see errors above); run 'make sync' later to fix"
fi

# ── 7. Sync tmux plugins (tpm) ──────────────────────────────────
echo ""
info "Syncing tmux plugins (tpm)..."
if bash "$DOTFILES_DIR/_scripts/tmux-plugins.sh"; then
    ok "tmux plugins ready"
else
    warn "tmux plugin sync had errors; run 'bash _scripts/tmux-plugins.sh' later to retry"
fi

# ── 8. Sync editor plugins ──────────────────────────────────────
echo ""
bash "$DOTFILES_DIR/_bootstrap/editors.sh"

# ── 9. Deploy custom scripts ────────────────────────────────────
bash "$DOTFILES_DIR/_bootstrap/tools.sh" "$DOTFILES_DIR"

# ── 10. Done ────────────────────────────────────────────────────
echo ""
ok "🎉 All done! Restart your terminal or run 'source ~/.zshrc' to apply the config."
echo ""

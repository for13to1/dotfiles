#!/usr/bin/env bash
# deploy repository-owned command-line tools.
# Usage: tools.sh [dotfiles-dir]
# Inputs: the repository path defaults to the repo root; HOME from the environment.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

main() {
    local repo_dir="${1:-$DOTFILES_DIR}"
    local resolved_dir=""

    resolved_dir="$(dotfiles_dir "$repo_dir")" || error "Cannot access dotfiles dir: $repo_dir"
    repo_dir="$resolved_dir"

    mkdir -p "$HOME/.local/bin"

    info "Deploying custom scripts..."
    if [[ -f "$repo_dir/proj-setup/bin/proj-setup.sh" ]]; then
        ln -sf "$repo_dir/proj-setup/bin/proj-setup.sh" "$HOME/.local/bin/proj-setup"
        ok "proj-setup deployed to ~/.local/bin/proj-setup"
    else
        warn "proj-setup.sh not found; skipping deployment"
    fi

    if is_debian_like; then
        if command -v fdfind &>/dev/null && [[ ! -e "$HOME/.local/bin/fd" ]]; then
            ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            ok "fd symlinked from fdfind"
        fi
        if command -v batcat &>/dev/null && [[ ! -e "$HOME/.local/bin/bat" ]]; then
            ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
            ok "bat symlinked from batcat"
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

#!/usr/bin/env bash
# deploy repository-owned command-line tools.
# Usage: tools.sh <dotfiles-dir>
# Inputs: explicit repository path and HOME from the environment.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

main() {
    local repo_dir="${1:-}"
    local resolved_dir=""

    [[ -n "$repo_dir" ]] || error "Usage: $0 <dotfiles-dir>"
    resolved_dir="$(dotfiles_dir "$repo_dir")" || error "Cannot access dotfiles dir: $repo_dir"
    repo_dir="$resolved_dir"
    info "Deploying custom scripts..."
    if [[ -f "$repo_dir/proj-setup/bin/proj-setup.sh" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$repo_dir/proj-setup/bin/proj-setup.sh" "$HOME/.local/bin/proj-setup"
        ok "proj-setup deployed to ~/.local/bin/proj-setup"
    else
        warn "proj-setup.sh not found; skipping deployment"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

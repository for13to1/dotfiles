#!/usr/bin/env bash
# Ensure local Git identity and repository hooks.
# Usage: git.sh [dotfiles-dir]
# Inputs: HOME and DOTFILES_NON_INTERACTIVE from the environment; the repository path defaults to the repo root.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

main() {
    local repo_dir="${1:-$DOTFILES_DIR}"
    local resolved_dir=""
    local git_name git_email

    resolved_dir="$(dotfiles_dir "$repo_dir")" || error "Cannot access dotfiles dir: $repo_dir"
    repo_dir="$resolved_dir"

    info "Configuring the Git environment..."
    if [[ ! -f "$HOME/.gitconfig.local" ]]; then
        echo ""
        warn "$HOME/.gitconfig.local not found (it stores your Git name and email)"
        if confirm "Create it now? [y/N]: " 0; then
            git_name="$(ask_value "Enter your Git name (default: for13to1): " "for13to1")"
            git_email="$(ask_value "Enter your Git email (default: for13to1@outlook.com): " "for13to1@outlook.com")"
            printf '[user]\n    name = %s\n    email = %s\n' "$git_name" "$git_email" > "$HOME/.gitconfig.local"
            ok ".gitconfig.local created"
        else
            info "Skipped. You can create it manually later with the following content:"
            info "  [user]"
            info "      name = for13to1"
            info "      email = for13to1@outlook.com"
        fi
    fi

    git -C "$repo_dir" config core.hooksPath "$repo_dir/_scripts/hooks"
    info "Git hooks enabled: core.hooksPath=$repo_dir/_scripts/hooks"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

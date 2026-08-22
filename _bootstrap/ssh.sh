#!/usr/bin/env bash
# Ensure SSH infrastructure, optional key generation, and permissions.
# Usage: ssh.sh
# Inputs: HOME and DOTFILES_NON_INTERACTIVE from the environment.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

main() {
    local f

    info "Checking the SSH environment..."
    mkdir -p "$HOME/.ssh"
    [[ -f "$HOME/.ssh/config" ]] || touch "$HOME/.ssh/config"

    if [[ ! -f "$HOME/.ssh/id_ed25519" && ! -f "$HOME/.ssh/id_rsa" ]]; then
        warn "No SSH key pair found"
        if confirm "Generate an ed25519 key now? [y/N]: " 0; then
            ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$HOME/.ssh/id_ed25519" -N ""
            ok "SSH key generated: ~/.ssh/id_ed25519"
        else
            info "💡 You can run this manually later: ssh-keygen -t ed25519 -C \"$(whoami)@$(hostname)\""
        fi
    else
        ok "SSH keys ready"
    fi

    info "Hardening SSH directory and file permissions..."
    chmod 700 "$HOME/.ssh"
    find "$HOME/.ssh" -type f \( -name "id_*" -o -name "*.pem" \) ! -name "*.pub" -exec chmod 600 {} +
    for f in config authorized_keys known_hosts known_hosts.old; do
        [[ -f "$HOME/.ssh/$f" ]] && chmod 600 "$HOME/.ssh/$f"
    done
    find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} +
    ok "SSH environment configured"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

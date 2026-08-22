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

    info "正在检查 SSH 环境..."
    mkdir -p "$HOME/.ssh"
    [[ -f "$HOME/.ssh/config" ]] || touch "$HOME/.ssh/config"

    if [[ ! -f "$HOME/.ssh/id_ed25519" && ! -f "$HOME/.ssh/id_rsa" ]]; then
        warn "未发现 SSH 密钥对"
        if confirm "是否立即为您生成一个 ed25519 密钥？ [y/N]: " 0; then
            ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$HOME/.ssh/id_ed25519" -N ""
            ok "SSH 密钥已生成：~/.ssh/id_ed25519"
        else
            info "💡 您稍后可以手动执行：ssh-keygen -t ed25519 -C \"$(whoami)@$(hostname)\""
        fi
    else
        ok "SSH 密钥已就绪"
    fi

    info "正在加固 SSH 目录及文件权限..."
    chmod 700 "$HOME/.ssh"
    find "$HOME/.ssh" -type f \( -name "id_*" -o -name "*.pem" \) ! -name "*.pub" -exec chmod 600 {} +
    for f in config authorized_keys known_hosts known_hosts.old; do
        [[ -f "$HOME/.ssh/$f" ]] && chmod 600 "$HOME/.ssh/$f"
    done
    find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} +
    ok "SSH 环境配置完成"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

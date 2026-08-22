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

    [[ -n "$repo_dir" ]] || error "用法: $0 <dotfiles-dir>"
    resolved_dir="$(dotfiles_dir "$repo_dir")" || error "无法访问 dotfiles 目录: $repo_dir"
    repo_dir="$resolved_dir"
    info "正在部署自定义脚本..."
    if [[ -f "$repo_dir/proj-setup/bin/proj-setup.sh" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$repo_dir/proj-setup/bin/proj-setup.sh" "$HOME/.local/bin/proj-setup"
        ok "proj-setup 已部署到 ~/.local/bin/proj-setup"
    else
        warn "proj-setup.sh 未找到，跳过部署"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

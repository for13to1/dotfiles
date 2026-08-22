#!/usr/bin/env bash
# Ensure local Git identity and repository hooks.
# Usage: git.sh <dotfiles-dir>
# Inputs: explicit repository path; HOME and DOTFILES_NON_INTERACTIVE from the environment.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

main() {
    local repo_dir="${1:-}"
    local resolved_dir=""
    local git_name git_email

    [[ -n "$repo_dir" ]] || error "用法: $0 <dotfiles-dir>"
    resolved_dir="$(dotfiles_dir "$repo_dir")" || error "无法访问 dotfiles 目录: $repo_dir"
    repo_dir="$resolved_dir"

    info "正在配置 Git 环境..."
    if [[ ! -f "$HOME/.gitconfig.local" ]]; then
        echo ""
        warn "未发现 ~/.gitconfig.local （用于存储 Git 用户名和邮箱）"
        if confirm "是否立即创建？ [y/N]: " 0; then
            git_name="$(ask_value "请输入 Git 用户名 (默认: for13to1): " "for13to1")"
            git_email="$(ask_value "请输入 Git 邮箱 (默认: for13to1@outlook.com): " "for13to1@outlook.com")"
            printf '[user]\n    name = %s\n    email = %s\n' "$git_name" "$git_email" > "$HOME/.gitconfig.local"
            ok ".gitconfig.local 已生成"
        else
            info "已跳过。您稍后可以手动创建并填入以下内容："
            info "  [user]"
            info "      name = for13to1"
            info "      email = for13to1@outlook.com"
        fi
    fi

    git -C "$repo_dir" config core.hooksPath "$repo_dir/_scripts/hooks"
    info "已启用 Git 钩子: core.hooksPath=$repo_dir/_scripts/hooks"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

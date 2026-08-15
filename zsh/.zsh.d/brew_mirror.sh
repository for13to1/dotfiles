# shellcheck shell=bash
# brew_mirror — Homebrew 镜像源切换
# 用法: brew_mirror [-q] [tuna | ustc | ali | reset]
#   -q / --quiet  静默模式，不打印切换提示（适合在 .zshrc.local 中调用）
#
# 切换镜像仅设置 API/BOTTLE 变量；git remote 始终指向官方 GitHub。
function restore_brew_git_remotes() {
    local brew_repo repo url
    brew_repo="$(brew --repo 2>/dev/null)" || return 0
    # zsh 与 bash 数组索引语义不同，逐项处理
    for repo in "$brew_repo" \
        "$brew_repo/Library/Taps/homebrew/homebrew-core" \
        "$brew_repo/Library/Taps/homebrew/homebrew-cask"; do
        [[ -d "$repo/.git" ]] || continue
        case "$repo" in
            "$brew_repo")                url="https://github.com/Homebrew/brew.git" ;;
            *"/homebrew-core")          url="https://github.com/Homebrew/homebrew-core.git" ;;
            *"/homebrew-cask")          url="https://github.com/Homebrew/homebrew-cask.git" ;;
            *)                           continue ;;
        esac
        # 仅在与官方不一致时写入
        [[ "$(git -C "$repo" remote get-url origin 2>/dev/null)" == "$url" ]] \
            || git -C "$repo" remote set-url origin "$url" 2>/dev/null
    done
    return 0
}

function brew_mirror() {
    local quiet=0
    if [[ "${1:-}" == "-q" || "${1:-}" == "--quiet" ]]; then
        quiet=1
        shift
    fi

    local target=${1:-}

    # 无参数 → 仅显示当前状态
    if [[ -z "$target" ]]; then
        if (( quiet )); then return 0; fi
        echo -e "当前 Homebrew 镜像源状态:"
        echo -e "  HOMEBREW_API_DOMAIN:      \033[1;33m${HOMEBREW_API_DOMAIN:-[未设置 (官方默认)]}\033[0m"
        echo -e "  HOMEBREW_BOTTLE_DOMAIN:   \033[1;33m${HOMEBREW_BOTTLE_DOMAIN:-[未设置]}\033[0m"
        echo -e "  git remote (brew):        \033[1;33m$(git -C "$(brew --repo 2>/dev/null)" remote get-url origin 2>/dev/null || echo '[无法获取]')\033[0m"
        return 0
    fi

    case $target in
        --help|-h)
            echo "用法: brew_mirror [-q] [tuna | ustc | ali | reset]"
            echo "  -q / --quiet  静默模式，不打印切换提示"
            echo ""
            echo "示例:"
            echo "  brew_mirror              # 查看当前镜像源状态"
            echo "  brew_mirror tuna         # 切换至清华大学镜像源"
            echo "  brew_mirror -q ustc      # 静默切换至 USTC 镜像源"
            echo "  brew_mirror reset        # 重置为官方源"
            return 0
            ;;
        tuna|tsinghua)
            restore_brew_git_remotes
            export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
            (( quiet )) || echo -e "\033[1;32m✅ 已切换至 清华大学 (TUNA) 镜像源\033[0m"
            ;;
        ustc)
            restore_brew_git_remotes
            export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
            (( quiet )) || echo -e "\033[1;32m✅ 已切换至 中国科学技术大学 (USTC) 镜像源\033[0m"
            ;;
        aliyun|ali)
            restore_brew_git_remotes
            export HOMEBREW_API_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles"
            (( quiet )) || echo -e "\033[1;32m✅ 已切换至 阿里巴巴 (Aliyun) 镜像源\033[0m"
            ;;
        reset|default)
            unset HOMEBREW_API_DOMAIN
            unset HOMEBREW_BOTTLE_DOMAIN
            unset HOMEBREW_BREW_GIT_REMOTE
            unset HOMEBREW_CORE_GIT_REMOTE
            unset HOMEBREW_CASK_GIT_REMOTE
            restore_brew_git_remotes
            (( quiet )) || echo -e "\033[1;34m🔄 已重置为 Homebrew 官方源\033[0m"
            ;;
        *)
            echo -e "\033[1;31m错误:\033[0m 未知镜像源 '$target'"
            echo "用法: brew_mirror [-q] [tuna | ustc | ali | reset]"
            return 1
            ;;
    esac
}

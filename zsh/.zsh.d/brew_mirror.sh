# brew_mirror — Homebrew 镜像源切换
# 用法: brew_mirror [-q] [tuna | ustc | ali | reset]
#   -q / --quiet  静默模式，不打印切换提示（适合在 .zshrc.local 中调用）
function brew_mirror() {
    local quiet=0
    if [[ "$1" == "-q" || "$1" == "--quiet" ]]; then
        quiet=1
        shift
    fi

    local target=$1

    # 无参数 → 仅显示当前状态
    if [[ -z "$target" ]]; then
        (( quiet )) && return 0
        echo -e "当前 Homebrew 镜像源状态:"
        echo -e "  HOMEBREW_API_DOMAIN:      \033[1;33m${HOMEBREW_API_DOMAIN:-[未设置 (官方默认)]}\033[0m"
        echo -e "  HOMEBREW_BOTTLE_DOMAIN:   \033[1;33m${HOMEBREW_BOTTLE_DOMAIN:-[未设置]}\033[0m"
        echo -e "  HOMEBREW_BREW_GIT_REMOTE: \033[1;33m${HOMEBREW_BREW_GIT_REMOTE:-[未设置]}\033[0m"
        echo -e "  HOMEBREW_CORE_GIT_REMOTE: \033[1;33m${HOMEBREW_CORE_GIT_REMOTE:-[未设置]}\033[0m"
        echo -e "  HOMEBREW_CASK_GIT_REMOTE: \033[1;33m${HOMEBREW_CASK_GIT_REMOTE:-[未设置]}\033[0m"
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
            echo "  brew_mirror reset        # 重置为官方默认源"
            return 0
            ;;
        tuna|tsinghua)
            export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
            export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
            export HOMEBREW_CASK_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-cask.git"
            (( quiet )) || echo -e "\033[1;32m✅ 已切换至 清华大学 (TUNA) 镜像源\033[0m"
            ;;
        ustc)
            export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/git/homebrew/brew.git"
            export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/git/homebrew/homebrew-core.git"
            export HOMEBREW_CASK_GIT_REMOTE="https://mirrors.ustc.edu.cn/git/homebrew/homebrew-cask.git"
            (( quiet )) || echo -e "\033[1;32m✅ 已切换至 中国科学技术大学 (USTC) 镜像源\033[0m"
            ;;
        aliyun|ali)
            export HOMEBREW_API_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/brew.git"
            export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/homebrew-core.git"
            export HOMEBREW_CASK_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/homebrew-cask.git"
            (( quiet )) || echo -e "\033[1;32m✅ 已切换至 阿里巴巴 (Aliyun) 镜像源\033[0m"
            ;;
        reset|default)
            unset HOMEBREW_API_DOMAIN
            unset HOMEBREW_BOTTLE_DOMAIN
            unset HOMEBREW_BREW_GIT_REMOTE
            unset HOMEBREW_CORE_GIT_REMOTE
            unset HOMEBREW_CASK_GIT_REMOTE
            (( quiet )) || echo -e "\033[1;34m🔄 已重置为 Homebrew 官方默认源\033[0m"
            ;;
        *)
            echo -e "\033[1;31m错误:\033[0m 未知镜像源 '$target'"
            echo "用法: brew_mirror [-q] [tuna | ustc | ali | reset]"
            return 1
            ;;
    esac
}

# brew_mirror — Homebrew 镜像源切换
# 用法: brew_mirror [tuna | ustc | ali | reset]
function brew_mirror() {
    local target=$1
    case $target in
        tuna|tsinghua)
            export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
            export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git"
            export HOMEBREW_CASK_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-cask.git"
            echo -e "\033[1;32m✅ 已切换至 清华大学 (TUNA) 镜像源\033[0m"
            ;;
        ustc)
            export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/git/homebrew/brew.git"
            export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/git/homebrew/homebrew-core.git"
            export HOMEBREW_CASK_GIT_REMOTE="https://mirrors.ustc.edu.cn/git/homebrew/homebrew-cask.git"
            echo -e "\033[1;32m✅ 已切换至 中国科学技术大学 (USTC) 镜像源\033[0m"
            ;;
        aliyun|ali)
            export HOMEBREW_API_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/brew.git"
            export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/homebrew-core.git"
            export HOMEBREW_CASK_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/homebrew-cask.git"
            echo -e "\033[1;32m✅ 已切换至 阿里巴巴 (Aliyun) 镜像源\033[0m"
            ;;
        reset|default)
            unset HOMEBREW_API_DOMAIN
            unset HOMEBREW_BOTTLE_DOMAIN
            unset HOMEBREW_BREW_GIT_REMOTE
            unset HOMEBREW_CORE_GIT_REMOTE
            unset HOMEBREW_CASK_GIT_REMOTE
            echo -e "\033[1;34m🔄 已重置为 Homebrew 官方默认源\033[0m"
            ;;
        *)
            echo "用法: brew_mirror [tuna | ustc | ali | reset]"
            echo -e "当前状态: \033[1;33m${HOMEBREW_API_DOMAIN:-官方默认}\033[0m"
            return 1
            ;;
    esac
}

# shellcheck shell=bash
# brew_mirror — switch Homebrew mirror sources
# Usage: brew_mirror [-q] [tuna | ustc | ali | reset]
#   -q / --quiet  quiet mode: no switch message (for use in .zshrc.local)

function restore_brew_git_remotes() {
    local brew_repo repo url
    brew_repo="$(brew --repo 2>/dev/null)" || return 0
    # Iterate each repo explicitly so the function works in both zsh and bash
    # (a literal list avoids the differing array semantics between the two shells).
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
        # Write only when it differs from the official remote.
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

    # No argument → show only the current state.
    if [[ -z "$target" ]]; then
        if (( quiet )); then return 0; fi
        echo -e "Current Homebrew mirror status:"
        echo -e "  HOMEBREW_API_DOMAIN:      \033[1;33m${HOMEBREW_API_DOMAIN:-[not set (official default)]}\033[0m"
        echo -e "  HOMEBREW_BOTTLE_DOMAIN:   \033[1;33m${HOMEBREW_BOTTLE_DOMAIN:-[not set]}\033[0m"
        echo -e "  HOMEBREW_BREW_GIT_REMOTE: \033[1;33m${HOMEBREW_BREW_GIT_REMOTE:-[not set]}\033[0m"
        echo -e "  git remote (brew):        \033[1;33m$(git -C "$(brew --repo 2>/dev/null)" remote get-url origin 2>/dev/null || echo '[unavailable]')\033[0m"
        return 0
    fi

    case $target in
        --help|-h)
            echo "Usage: brew_mirror [-q] [tuna | ustc | ali | reset]"
            echo "  -q / --quiet  quiet mode: no switch message"
            echo ""
            echo "Examples:"
            echo "  brew_mirror              # show the current mirror status"
            echo "  brew_mirror tuna         # switch to the Tsinghua (TUNA) mirror"
            echo "  brew_mirror -q ustc      # quietly switch to the USTC mirror"
            echo "  brew_mirror reset        # reset to the official sources"
            return 0
            ;;
        tuna|tsinghua)
            export HOMEBREW_API_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git"
            (( quiet )) || echo -e "\033[1;32m✅ Switched to the Tsinghua (TUNA) mirror\033[0m"
            ;;
        ustc)
            export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
            (( quiet )) || echo -e "\033[1;32m✅ Switched to the USTC mirror\033[0m"
            ;;
        aliyun|ali)
            export HOMEBREW_API_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles/api"
            export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.aliyun.com/homebrew/homebrew-bottles"
            export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.aliyun.com/homebrew/brew.git"
            (( quiet )) || echo -e "\033[1;32m✅ Switched to the Aliyun mirror\033[0m"
            ;;
        reset|default)
            unset HOMEBREW_API_DOMAIN
            unset HOMEBREW_BOTTLE_DOMAIN
            unset HOMEBREW_BREW_GIT_REMOTE
            unset HOMEBREW_CORE_GIT_REMOTE
            unset HOMEBREW_CASK_GIT_REMOTE
            restore_brew_git_remotes
            (( quiet )) || echo -e "\033[1;34m🔄 Reset to the official Homebrew sources\033[0m"
            ;;
        *)
            echo -e "\033[1;31mError:\033[0m unknown mirror '$target'"
            echo "Usage: brew_mirror [-q] [tuna | ustc | ali | reset]"
            return 1
            ;;
    esac
}

#!/usr/bin/env bash
#
# bootstrap.sh — 一键装机入口脚本
# 用法: git clone https://github.com/for13to1/dotfiles.git ~/dotfiles
#       cd ~/dotfiles && bash bootstrap.sh
#

set -euo pipefail

# ── 彩色输出 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; exit 1; }

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── 1. 检测操作系统 ──────────────────────────────────────────────
OS="$(uname -s)"
info "检测到操作系统: $OS"

# ── 2. 安装系统级包 ──────────────────────────────────────────────
case "$OS" in
    Darwin*)
        info "🍎 macOS 环境，开始配置..."

        # Xcode 开发工具检测：优先使用完整版 Xcode.app，否则退而安装精简版 CLT
        if [[ -d "/Applications/Xcode.app" ]]; then
            # 完整版 Xcode 已安装，测试 xcodebuild 是否可用
            if ! xcodebuild -version &>/dev/null; then
                info "检测到 Xcode.app 但当前路径未正确指向它，正在切换 xcode-select 路径..."
                sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
            fi
            ok "Xcode.app 已就绪"
        elif ! xcode-select -p &>/dev/null; then
            # 没有完整版 Xcode，也没有 CLT，安装精简版 CLT
            info "未检测到 Xcode.app，正在安装 Command Line Tools..."
            xcode-select --install
            echo "请在弹出的窗口中点击\"安装\"，安装完成后重新运行本脚本。"
            exit 0
        else
            ok "Xcode Command Line Tools 已就绪"
        fi

        # 安装 Homebrew（如果没装过）
        if ! command -v brew &>/dev/null; then
            info "正在安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Apple Silicon 需要手动加入 PATH
            if [[ "$(uname -m)" == "arm64" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
        fi
        ok "Homebrew 已就绪"

        # 安装必备软件（完整清单见 Brewfile，可稍后按需手动安装）
        if [[ -f "$DOTFILES_DIR/_install/mac/Brewfile.essential" ]]; then
            # brew bundle 某些 cask 可能因网络、密码弹窗等原因失败，
            # 不应阻断后续步骤（Oh My Zsh、Stow 等），失败的包可稍后手动重试
            info "正在安装必备软件（Brewfile.essential）..."
            if brew bundle --verbose --file="$DOTFILES_DIR/_install/mac/Brewfile.essential"; then
                ok "必备软件安装完毕"
            else
                warn "部分软件安装失败，请稍后运行 brew bundle --file=_install/mac/Brewfile.essential 重试"
            fi
            info "💡 其余软件请参考 _install/mac/Brewfile 按需安装"
        else
            warn "未找到 _install/mac/Brewfile.essential，跳过软件安装"
        fi

        # 执行 macOS 偏好设置脚本
        if [[ -f "$DOTFILES_DIR/_install/mac/setup.sh" ]]; then
            info "正在应用 macOS 系统偏好设置..."
            bash "$DOTFILES_DIR/_install/mac/setup.sh"
            ok "macOS 偏好设置已应用"
        fi
        ;;

    Linux*)
        info "🐧 Linux 环境，开始配置..."

        if command -v apt &>/dev/null; then
            if [[ -f "$DOTFILES_DIR/_install/linux/apt-list.txt" ]]; then
                info "正在通过 apt 安装软件..."
                sudo apt update
                xargs sudo apt install -y < "$DOTFILES_DIR/_install/linux/apt-list.txt"
                ok "apt 软件安装完毕"
            else
                warn "未找到 _install/linux/apt-list.txt，跳过软件安装"
            fi
        elif command -v pacman &>/dev/null; then
            if [[ -f "$DOTFILES_DIR/_install/linux/pacman-list.txt" ]]; then
                info "正在通过 pacman 安装软件..."
                sudo pacman -Syu --noconfirm
                xargs sudo pacman -S --noconfirm --needed < "$DOTFILES_DIR/_install/linux/pacman-list.txt"
                ok "pacman 软件安装完毕"
            else
                warn "未找到 _install/linux/pacman-list.txt，跳过软件安装"
            fi
        else
            warn "未识别的 Linux 包管理器，请手动安装所需软件"
        fi

        if [[ -f "$DOTFILES_DIR/_install/linux/setup.sh" ]]; then
            bash "$DOTFILES_DIR/_install/linux/setup.sh"
        fi
        ;;

    *)
        error "不支持的操作系统: $OS"
        ;;
esac

# ── 3. 安装 Oh My Zsh（如果没装过）──────────────────────────────
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "正在安装 Oh My Zsh..."
    # --unattended: 不自动切换默认 shell，不启动新 zsh 会话
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "Oh My Zsh 安装完毕"
else
    ok "Oh My Zsh 已存在，跳过"
fi

# 因为使用了 --unattended 模式安装 OMZ，会导致原生脚本跳过 chsh 切换 Shell 的步骤
# 我们在这里手动检测并切换默认 Shell 为 zsh
if [[ "$SHELL" != *"zsh"* ]] && command -v zsh &>/dev/null; then
    info "检测到当前默认 Shell 不是 zsh，正在尝试为您切换..."
    chsh -s "$(command -v zsh)" || warn "切换默认 Shell 失败，您可以稍后手动执行: chsh -s \$(which zsh)"
    ok "已退出 chsh 流程"
fi

# ── 4. 安装 Oh My Zsh 第三方插件 ─────────────────────────────────
# 注意：macOS 自带 bash 3.2 不支持 declare -A，使用普通数组代替
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

omz_install_plugin() {
    local name="$1" url="$2"
    if [[ ! -d "$ZSH_CUSTOM/plugins/$name" ]]; then
        info "正在安装 OMZ 插件: $name..."
        git clone "$url" "$ZSH_CUSTOM/plugins/$name"
        ok "$name 安装完毕"
    else
        ok "$name 已存在，跳过"
    fi
}

omz_install_plugin zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions
omz_install_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting

# ── 5. 使用 Stow 挂载配置文件 ───────────────────────────────────
if ! command -v stow &>/dev/null; then
    error "stow 未安装！请先通过包管理器安装 stow (brew/apt/pacman install stow)，然后重新执行本脚本。"
fi

info "正在使用 Stow 挂载配置文件..."

# 删除 OMZ 可能生成的默认 .zshrc，避免 stow 冲突
if [[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
    warn "发现已有的 ~/.zshrc（非软链接），备份为 ~/.zshrc.bak"
    mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
fi

# 备份已有的 .gitconfig 和 .vimrc，避免 stow 冲突
for conflict_file in ".gitconfig" ".vimrc"; do
    if [[ -f "$HOME/$conflict_file" && ! -L "$HOME/$conflict_file" ]]; then
        warn "发现已有的 ~/$conflict_file（非软链接），备份为 ~/$conflict_file.bak"
        mv "$HOME/$conflict_file" "$HOME/$conflict_file.bak"
    fi
done

cd "$DOTFILES_DIR"
stow zsh git vim nvim codestyle

ok "Stow 挂载完成"

# ── 6. 编辑器插件初始化 ──────────────────────────────────────
echo ""
info "📋 请选择要初始化的编辑器插件："
echo "   1) Neovim (lazy.nvim) - [默认]"
echo "   2) Vim (vim-plug)"
echo "   3) 两者都要"
echo "   4) 跳过"
read -rp "请输入数字 [1-4]: " editor_choice

# Neovim 插件 (lazy.nvim)
if [[ "$editor_choice" == "1" || "$editor_choice" == "3" || -z "$editor_choice" ]]; then
    if command -v nvim &>/dev/null; then
        info "正在同步 Neovim 插件 (lazy.nvim)..."
        # nvim --headless "+Lazy! sync" +qa 可能会因为某些插件编译失败返回非零值，
        # 但通常不影响基础使用，所以加个 || true
        nvim --headless "+Lazy! sync" +qa || warn "Neovim 插件同步过程中有报错，请稍后手动打开 nvim 查看"
        ok "Neovim 插件就绪"
    fi
fi

# Vim 插件
if [[ "$editor_choice" == "2" || "$editor_choice" == "3" ]]; then
    # 安装 vim-plug（如果没装过）
    if [[ ! -f "$HOME/.vim/autoload/plug.vim" ]]; then
        info "正在安装 vim-plug..."
        curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
        ok "vim-plug 安装完毕"
    else
        ok "vim-plug 已存在，跳过"
    fi

    # 安装/更新 Vim 插件（静默模式）
    if command -v vim &>/dev/null; then
        info "正在安装/更新 Vim 插件..."
        vim +PlugInstall +PlugUpdate +qall
        ok "Vim 插件就绪"
    fi
fi

# ── 7. Git 一次性初始化 ──────────────────────────────────────────
# 清理可能残留的代理设置
git config --global --unset http.proxy 2>/dev/null || true
git config --global --unset https.proxy 2>/dev/null || true

# 初始化 Git LFS
if command -v git-lfs &>/dev/null; then
    git lfs install
    ok "Git LFS 已初始化"
fi

# ── 8. SSH 密钥检测 ──────────────────────────────────────────────
if [[ ! -f "$HOME/.ssh/id_ed25519" && ! -f "$HOME/.ssh/id_rsa" ]]; then
    warn "未发现 SSH 密钥（~/.ssh/id_ed25519 或 id_rsa）"
    info "💡 建议运行以下命令生成：ssh-keygen -t ed25519 -C \"$(whoami)@$(hostname)\""
fi

# ── 9. 完成 ───────────────────────────────────────────────────────
echo ""
ok "🎉 全部搞定！请重启终端（或执行 source ~/.zshrc）使配置生效。"
echo ""
info "提示：请确保已创建以下本地配置文件（不纳入版本控制）："
if [[ ! -f "$HOME/.zshrc.local" ]]; then
    info "  touch ~/.zshrc.local       — 本地环境变量、API Key 等"
fi
if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    echo ""
    warn "未发现 ~/.gitconfig.local（用于存储 Git 用户名和邮箱）"
    read -rp "是否立即创建？ [y/N]: " create_local
    if [[ "$create_local" =~ ^[Yy]$ ]]; then
        read -rp "请输入 Git 用户名 (默认: for13to1): " git_name
        git_name=${git_name:-for13to1}
        read -rp "请输入 Git 邮箱 (默认: for13to1@outlook.com): " git_email
        git_email=${git_email:-for13to1@outlook.com}

        cat <<EOF > "$HOME/.gitconfig.local"
[user]
    name = $git_name
    email = $git_email
EOF
        ok ".gitconfig.local 已生成"
    else
        info "已跳过。您稍后可以手动创建并填入以下内容："
        info "  [user]"
        info "      name = for13to1"
        info "      email = for13to1@outlook.com"
    fi
fi
echo ""
info "别忘了配置 SSH 密钥并添加至 GitHub，详见 README.md"

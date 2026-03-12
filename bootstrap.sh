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

        # 安装 Homebrew （如果没装过）
        if ! command -v brew &>/dev/null; then
            info "正在安装 Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Apple Silicon 需要手动加入 PATH
            if [[ "$(uname -m)" == "arm64" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
        fi
        ok "Homebrew 已就绪"

        # 确保脚本硬依赖已安装
        if ! command -v stow &>/dev/null; then
            info "正在安装 stow..."
            brew install stow
        fi

        # 安装必备软件（完整清单见 Brewfile，可稍后按需手动安装）
        if [[ -f "$DOTFILES_DIR/_install/mac/Brewfile.essential" ]]; then
            # brew bundle 某些 cask 可能因网络、密码弹窗等原因失败，
            # 不应阻断后续步骤（Oh My Zsh、Stow 等），失败的包可稍后手动重试
            info "正在更新 Homebrew 索引并安装必备软件..."
            brew update
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
            sudo apt update

            # 确保脚本硬依赖已安装（zsh + stow）
            if ! command -v zsh &>/dev/null; then
                info "正在安装 zsh..."
                sudo apt install -y zsh
            fi
            if ! command -v stow &>/dev/null; then
                info "正在安装 stow..."
                sudo apt install -y stow
            fi

            if [[ -f "$DOTFILES_DIR/_install/linux/apt-list.txt" ]]; then
                info "正在通过 apt 安装软件..."
                xargs sudo apt install -y < "$DOTFILES_DIR/_install/linux/apt-list.txt"
                ok "apt 软件安装完毕"
            else
                warn "未找到 _install/linux/apt-list.txt，跳过其他软件安装"
            fi
        elif command -v pacman &>/dev/null; then
            sudo pacman -Syu --noconfirm

            # 确保脚本硬依赖已安装（zsh + stow）
            if ! command -v zsh &>/dev/null; then
                info "正在安装 zsh..."
                sudo pacman -S --noconfirm zsh
            fi
            if ! command -v stow &>/dev/null; then
                info "正在安装 stow..."
                sudo pacman -S --noconfirm stow
            fi

            if [[ -f "$DOTFILES_DIR/_install/linux/pacman-list.txt" ]]; then
                info "正在通过 pacman 安装软件..."
                xargs sudo pacman -S --noconfirm --needed < "$DOTFILES_DIR/_install/linux/pacman-list.txt"
                ok "pacman 软件安装完毕"
            else
                warn "未找到 _install/linux/pacman-list.txt，跳过其他软件安装"
            fi
        else
            warn "未识别的 Linux 包管理器，请手动安装 zsh 及所需软件"
        fi

        if [[ -f "$DOTFILES_DIR/_install/linux/setup.sh" ]]; then
            bash "$DOTFILES_DIR/_install/linux/setup.sh"
        fi
        ;;

    *)
        error "不支持的操作系统: $OS"
        ;;
esac

# ── 3. SSH 基础设施与密钥 ───────────────────────────────────────
info "正在检查 SSH 环境..."

## 1. 基础设施：确保目录和基础文件存在
mkdir -p "$HOME/.ssh"
[[ ! -f "$HOME/.ssh/config" ]] && touch "$HOME/.ssh/config"

## 2. 交互式密钥检测与生成
if [[ ! -f "$HOME/.ssh/id_ed25519" && ! -f "$HOME/.ssh/id_rsa" ]]; then
    warn "未发现 SSH 密钥对"
    read -rp "是否立即为您生成一个 ed25519 密钥？ [y/N]: " gen_key
    if [[ "$gen_key" =~ ^[Yy]$ ]]; then
        ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$HOME/.ssh/id_ed25519" -N ""
        ok "SSH 密钥已生成：~/.ssh/id_ed25519"
    else
        info "💡 您稍后可以手动执行：ssh-keygen -t ed25519 -C \"$(whoami)@$(hostname)\""
    fi
else
    ok "SSH 密钥已就绪"
fi

## 3. 权限加固
info "正在加固 SSH 目录及文件权限..."
chmod 700 "$HOME/.ssh"
# 私钥、config、授权列表以及指纹文件设置为 600
find "$HOME/.ssh" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} +
[[ -f "$HOME/.ssh/config" ]] && chmod 600 "$HOME/.ssh/config"
[[ -f "$HOME/.ssh/authorized_keys" ]] && chmod 600 "$HOME/.ssh/authorized_keys"
[[ -f "$HOME/.ssh/known_hosts" ]] && chmod 600 "$HOME/.ssh/known_hosts"
[[ -f "$HOME/.ssh/known_hosts.old" ]] && chmod 600 "$HOME/.ssh/known_hosts.old"
# 公钥使用标准的 644
find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} +

ok "SSH 环境配置完成"

# ── 4. Git 身份与基础配置 ─────────────────────────────────────────
info "正在配置 Git 环境..."

## 1. 清理可能残留的代理设置
git config --global --unset http.proxy 2>/dev/null || true
git config --global --unset https.proxy 2>/dev/null || true

## 2. 初始化 Git LFS
if command -v git-lfs &>/dev/null; then
    git lfs install
    ok "Git LFS 已初始化"
fi

## 3. Git 本地用户信息 (~/.gitconfig.local)
if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    echo ""
    warn "未发现 ~/.gitconfig.local （用于存储 Git 用户名和邮箱）"
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

# ── 5. Shell 环境设置 (Oh My Zsh & Plugins) ──────────────────────
## 1. 安装 Oh My Zsh
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "正在安装 Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    ok "Oh My Zsh 安装完毕"
else
    ok "Oh My Zsh 已存在，跳过"
fi

## 2. 切换默认 Shell
if [[ "$SHELL" != *"zsh"* ]] && command -v zsh &>/dev/null; then
    info "检测到当前默认 Shell 不是 zsh，正在尝试为您切换..."
    chsh -s "$(command -v zsh)" || warn "切换默认 Shell 失败，您可以稍后手动执行: chsh -s \$(which zsh)"
    ok "已退出 chsh 流程"
fi

## 3. 安装 Oh My Zsh 第三方插件
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

## 4. 初始化 ~/.zshrc.local
if [[ ! -f "$HOME/.zshrc.local" ]]; then
    info "正在生成 ~/.zshrc.local 示例模板..."
    cat <<'EOF' > "$HOME/.zshrc.local"
# ~/.zshrc.local — 本地配置，不纳入版本控制，可按需修改

# API Keys
export OPENAI_API_KEY="sk-..."
export OPENAI_BASE_URL="https://api.openai.com/v1"

export ANTHROPIC_API_KEY="sk-ant-..."
export ANTHROPIC_BASE_URL="https://api.anthropic.com"

export GEMINI_API_KEY="your-api-key"
export GEMINI_BASE_URL="https://generativelanguage.googleapis.com"

# 代理设置（取消注释前请确保本地代理已启动，否则会导致网络请求失败）
# export proxy_addr="127.0.0.1:7890"
# export http_proxy="http://$proxy_addr"
# export https_proxy="http://$proxy_addr"
# export all_proxy="socks5://$proxy_addr"
# export HTTP_PROXY=$http_proxy
# export HTTPS_PROXY=$https_proxy
# export ALL_PROXY=$all_proxy
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1"
export NO_PROXY=$no_proxy
EOF
    ok "~/.zshrc.local 示例模板已生成"
fi

# ── 6. 配置文件挂载 (Stow) ──────────────────────────────────────────
info "正在使用 Stow 挂载配置文件..."

if [[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
    warn "发现已有的 ~/.zshrc （非软链接），备份为 ~/.zshrc.bak"
    mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
fi

for conflict_file in ".gitconfig" ".vimrc"; do
    if [[ -f "$HOME/$conflict_file" && ! -L "$HOME/$conflict_file" ]]; then
        warn "发现已有的 ~/$conflict_file（非软链接），备份为 ~/$conflict_file.bak"
        mv "$HOME/$conflict_file" "$HOME/$conflict_file.bak"
    fi
done

cd "$DOTFILES_DIR"
stow zsh git vim nvim codestyle
ok "Stow 挂载完成"

# ── 7. VS Code 配置 ──────────────────────────────────────────────
# echo ""
# info "📋 是否部署 VS Code 个人配置？"
# echo "   1) 是"
# echo "   2) 否"
# read -rp "请输入数字 [1-2]: " vscode_choice
vscode_choice="2"

if [[ "$vscode_choice" == "1" ]]; then
    info "正在部署 VS Code 配置..."
    if [[ "$OS" == "Darwin"* ]]; then
        VSCODE_USER_DIR="$HOME/Library/Application Support/Code/User"
    elif [[ "$OS" == "Linux"* ]]; then
        VSCODE_USER_DIR="$HOME/.config/Code/User"
    else
        VSCODE_USER_DIR=""
    fi

    if [[ -n "$VSCODE_USER_DIR" ]]; then
        mkdir -p "$VSCODE_USER_DIR"
        ln -sf "$DOTFILES_DIR/vscode/settings.json" "$VSCODE_USER_DIR/settings.json" && ok "VS Code settings.json 已链接"
    fi
fi

# ── 8. 编辑器插件同步 ──────────────────────────────────────
echo ""
info "📋 请选择要同步的编辑器插件："
echo "   1) Neovim (lazy.nvim) - [默认]"
echo "   2) Vim (vim-plug)"
echo "   3) 两者都要"
echo "   4) 跳过"
read -rp "请输入数字 [1-4]: " editor_choice

## 1. Neovim 插件 (lazy.nvim)
if [[ "$editor_choice" == "1" || "$editor_choice" == "3" || -z "$editor_choice" ]]; then
    if command -v nvim &>/dev/null; then
        info "正在同步 Neovim 插件 (lazy.nvim)..."
        nvim --headless "+Lazy! sync" +qa || warn "Neovim 插件同步过程中有报错，请稍后手动打开 nvim 查看"
        ok "Neovim 插件就绪"
    fi
fi

## 2. Vim 插件 (vim-plug)
if [[ "$editor_choice" == "2" || "$editor_choice" == "3" ]]; then
    if [[ ! -f "$HOME/.vim/autoload/plug.vim" ]]; then
        info "正在安装 vim-plug..."
        curl -fLo "$HOME/.vim/autoload/plug.vim" --create-dirs \
            https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
        ok "vim-plug 安装完毕"
    else
        ok "vim-plug 已存在，跳过"
    fi

    if command -v vim &>/dev/null; then
        info "正在安装/更新 Vim 插件..."
        vim +PlugInstall +PlugUpdate +qall
        ok "Vim 插件就绪"
    fi
fi

# ── 9. 完成 ───────────────────────────────────────────────────────
echo ""
ok "🎉 全部搞定！请重启终端（或执行 source ~/.zshrc ）使配置生效。"
echo ""

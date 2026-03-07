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
            # 完整版 Xcode 已安装，确保 xcode-select 指向它
            if [[ "$(xcode-select -p 2>/dev/null)" != "/Applications/Xcode.app/Contents/Developer" ]]; then
                info "检测到 Xcode.app，正在切换 xcode-select 路径..."
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

        # 根据 Brewfile 安装所有软件
        if [[ -f "$DOTFILES_DIR/_install/mac/Brewfile" ]]; then
            info "正在根据 Brewfile 安装软件（可能需要较长时间）..."
            brew bundle --file="$DOTFILES_DIR/_install/mac/Brewfile"
            ok "Brewfile 中的软件安装完毕"
        else
            warn "未找到 _install/mac/Brewfile，跳过软件安装"
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
                sudo pacman -S --noconfirm --needed $(cat "$DOTFILES_DIR/_install/linux/pacman-list.txt")
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

# ── 4. 使用 Stow 挂载配置文件 ───────────────────────────────────
if ! command -v stow &>/dev/null; then
    error "stow 未安装！请先安装 stow 后重试。"
fi

info "正在使用 Stow 挂载配置文件..."

# 删除 OMZ 可能生成的默认 .zshrc，避免 stow 冲突
if [[ -f "$HOME/.zshrc" && ! -L "$HOME/.zshrc" ]]; then
    warn "发现已有的 ~/.zshrc（非软链接），备份为 ~/.zshrc.bak"
    mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
fi

cd "$DOTFILES_DIR"
stow zsh

ok "Stow 挂载完成"

# ── 5. 完成 ─────────────────────────────────────────────────────
echo ""
ok "🎉 全部搞定！请重启终端（或执行 source ~/.zshrc）使配置生效。"
echo ""
info "提示：如果需要机器专属配置（API Key 等），请创建 ~/.zshrc.local"

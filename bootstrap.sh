#!/usr/bin/env bash
#
# bootstrap.sh — 一键装机入口脚本
# 用法: git clone https://github.com/for13to1/dotfiles.git ~/dotfiles
#       cd ~/dotfiles && bash bootstrap.sh
#

set -euo pipefail

# ── 脚本路径解析（支持软链接/相对路径调用）─────────────────────────
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"

# ── 共享基础设施（彩色输出等，见 _scripts/common.sh）──────────────
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_scripts/common.sh"

# ── 1. 检测操作系统 ──────────────────────────────────────────────
OS="$(uname -s)"
info "检测到操作系统: $OS"

# ── 2. 软件安装 ──────────────────────────────────────────────
# ── 可选组提示：枚举某平台除 default 组外的其余组，便于按需选装 ──
hint_optional_groups() {
    local platform="$1"
    local groups=() _f _t
    for _f in "$DOTFILES_DIR/_install/$platform"/*.group; do
        [[ -f "$_f" ]] || continue
        _t="$(basename "$_f")"
        [[ "$_t" == "default.group" ]] && continue
        groups+=("${_t%.group}")
    done
    if (( ${#groups[@]} > 0 )); then
        info "💡 其余组请按需选装: bash _install/install --$platform ${groups[*]}"
    fi
}

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

        if [[ -f "$DOTFILES_DIR/zsh/.zsh.d/brew_mirror.sh" ]]; then
            # shellcheck disable=SC1091
            source "$DOTFILES_DIR/zsh/.zsh.d/brew_mirror.sh"
        else
            error "未找到 brew_mirror.sh"
        fi

        # 询问是否需要使用镜像源加速
        echo ""
        info "🌍 Homebrew 镜像源选择："
        echo "   1) 清华大学 (TUNA) - [默认]"
        echo "   2) 中国科大 (USTC)"
        echo "   3) 阿里巴巴 (Aliyun)"
        echo "   4) 跳过 (使用官方源)"
        mirror_choice="$(ask_value "请输入数字 [1-4]: " "1")"

        SELECTED_MIRROR=""
        case "$mirror_choice" in
            1) SELECTED_MIRROR="tuna" ;;
            2) SELECTED_MIRROR="ustc" ;;
            3) SELECTED_MIRROR="ali"  ;;
            *) SELECTED_MIRROR=""     ;;
        esac

        if [[ -n "$SELECTED_MIRROR" ]]; then
            brew_mirror -q "$SELECTED_MIRROR"
            ok "已临时设置 $SELECTED_MIRROR 镜像源以加速安装"
        elif command -v brew &>/dev/null; then
            brew_mirror -q reset
            ok "已重置为 Homebrew 官方源"
        else
            info "默认使用 Homebrew 官方源"
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

        # 安装默认组
        info "正在更新 Homebrew 并安装默认组..."
        brew update || warn "Homebrew 索引更新未能全量完成，尝试继续安装..."
        if bash "$DOTFILES_DIR/_install/install" --brew; then
            ok "默认组安装完毕"
        else
            warn "默认组部分软件安装失败，可稍后运行 bash _install/install --brew 重试"
        fi
        hint_optional_groups brew

        # 执行 macOS 偏好设置脚本
        if [[ -f "$DOTFILES_DIR/_setup/mac/setup.sh" ]]; then
            info "正在应用 macOS 系统偏好设置..."
            bash "$DOTFILES_DIR/_setup/mac/setup.sh"
            ok "macOS 偏好设置已应用"
        fi
        ;;

    Linux*)
        info "🐧 Linux 环境，开始配置..."

        # 按组安装软件
        install_bootstrap_groups() {
            local platform="$1"
            if bash "$DOTFILES_DIR/_install/install" "--$platform"; then
                ok "$platform 默认组安装完毕"
            else
                warn "$platform 默认组部分软件安装失败，可稍后运行 bash _install/install --$platform 重试"
                if confirm "是否继续执行后续配置？ [Y/n]: " 1; then
                    warn "继续执行后续配置"
                else
                    error "已按用户选择停止 bootstrap"
                fi
            fi
        }

        if command -v apt &>/dev/null; then
            info "正在更新 apt 软件包索引..."
            if ! sudo apt update; then
                warn "apt update 失败，可能是网络问题，继续尝试安装已缓存的软件包..."
            fi

            # 确保脚本硬依赖已安装（zsh + stow）
            if ! command -v zsh &>/dev/null; then
                info "正在安装 zsh..."
                sudo apt install -y zsh
            fi
            if ! command -v stow &>/dev/null; then
                info "正在安装 stow..."
                sudo apt install -y stow
            fi
            if ! command -v make &>/dev/null; then
                info "正在安装 make..."
                sudo apt install -y make
            fi

            install_bootstrap_groups apt

            # 确保 en_US.UTF-8 locale 存在，避免 stow/perl 等工具报 locale 警告。
            if command -v locale-gen &>/dev/null \
               && ! locale -a 2>/dev/null | grep -qiE 'en_US\.utf-?8'; then
                info "正在生成 en_US.UTF-8 locale..."
                sudo locale-gen en_US.UTF-8 \
                    || warn "生成失败，可稍后手动执行: sudo locale-gen en_US.UTF-8"
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
            if ! command -v make &>/dev/null; then
                info "正在安装 make..."
                sudo pacman -S --noconfirm make
            fi

            install_bootstrap_groups pacman
        else
            warn "未识别的 Linux 包管理器，请手动安装 zsh 及所需软件"
        fi

        # Debian 系平台先准备工具管理器，再按 npm/uv/Cargo 渠道安装 CLI。
        if [[ -f "$DOTFILES_DIR/_install/install-by-curl.sh" ]]; then
            bash "$DOTFILES_DIR/_install/install-by-curl.sh"
        fi

        if [[ -f "$DOTFILES_DIR/_install/install-by-npm.sh" ]]; then
            bash "$DOTFILES_DIR/_install/install-by-npm.sh"
        fi

        if [[ -f "$DOTFILES_DIR/_install/install-by-uv.sh" ]]; then
            bash "$DOTFILES_DIR/_install/install-by-uv.sh"
        fi

        if [[ -f "$DOTFILES_DIR/_install/install-by-cargo.sh" ]]; then
            bash "$DOTFILES_DIR/_install/install-by-cargo.sh"
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
    if confirm "是否立即为您生成一个 ed25519 密钥？ [y/N]: " 0; then
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
# 私钥与核心配置 (600)
find "$HOME/.ssh" -type f \( -name "id_*" -o -name "*.pem" \) ! -name "*.pub" -exec chmod 600 {} +
for f in config authorized_keys known_hosts known_hosts.old; do
    [[ -f "$HOME/.ssh/$f" ]] && chmod 600 "$HOME/.ssh/$f"
done
# 公钥标准权限 (644)
find "$HOME/.ssh" -type f -name "*.pub" -exec chmod 644 {} +

ok "SSH 环境配置完成"

# ── 4. Git 身份与基础配置 ─────────────────────────────────────────
info "正在配置 Git 环境..."

# Git LFS 由 git 模块（.gitconfig 的 [filter "lfs"]）全局接管，这里无需额外配置

## 1. Git 本地用户信息 (~/.gitconfig.local)
if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    echo ""
    warn "未发现 ~/.gitconfig.local （用于存储 Git 用户名和邮箱）"
    if confirm "是否立即创建？ [y/N]: " 0; then
        git_name="$(ask_value "请输入 Git 用户名 (默认: for13to1): " "for13to1")"
        git_email="$(ask_value "请输入 Git 邮箱 (默认: for13to1@outlook.com): " "for13to1@outlook.com")"

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

## 2. Git 钩子（pre-push 自动运行 make test）
git -C "$DOTFILES_DIR" config core.hooksPath "$DOTFILES_DIR/_scripts/hooks"
info "已启用 Git 钩子: core.hooksPath=$DOTFILES_DIR/_scripts/hooks"

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
    ZSH_PATH="$(command -v zsh)"
    if ! grep -Fxq "$ZSH_PATH" /etc/shells; then
        warn "Zsh 路径 ($ZSH_PATH) 不在 /etc/shells 中，正在添加..."
        echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
    fi
    chsh -s "$ZSH_PATH" || warn "切换默认 Shell 失败，您可以稍后手动执行: chsh -s $ZSH_PATH"
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

    cat <<'TEMPLATE_EOF' > "$HOME/.zshrc.local"
# ~/.zshrc.local — 本地配置，不纳入版本控制，可按需修改
TEMPLATE_EOF

    if [[ "$OS" == "Darwin"* ]]; then
        cat <<'TEMPLATE_EOF' >> "$HOME/.zshrc.local"

# ==========================================================
# Homebrew 镜像源切换 (函数定义见 ~/.zsh.d/brew_mirror.sh)
# ==========================================================
TEMPLATE_EOF
        if [[ -n "${SELECTED_MIRROR:-}" ]]; then
            echo "brew_mirror -q $SELECTED_MIRROR" >> "$HOME/.zshrc.local"
        else
            echo "# brew_mirror -q ustc  # 取消注释以启用 USTC 镜像源" >> "$HOME/.zshrc.local"
        fi
    fi

    cat <<'TEMPLATE_EOF' >> "$HOME/.zshrc.local"

# ==========================================================
# API Keys
# ==========================================================
# export OPENAI_API_KEY="sk-..."
# export OPENAI_BASE_URL="https://api.openai.com/v1"

# export ANTHROPIC_API_KEY="sk-ant-..."
# export ANTHROPIC_BASE_URL="https://api.anthropic.com"

# export GEMINI_API_KEY="your-api-key"
# export GEMINI_BASE_URL="https://generativelanguage.googleapis.com"
TEMPLATE_EOF
    ok "$HOME/.zshrc.local 示例模板已生成"
fi

# ── 6. 配置文件挂载 (Stow) ──────────────────────────────────────────
info "正在使用 Stow 挂载配置文件..."

## 1. 确定模块列表（单一真值源 SSOT，见 _scripts/modules.conf）
# 模块清单以每行一个模块的形式输出，逐行读入数组。
STOW_MODULES=()
if [[ -f "$DOTFILES_DIR/_scripts/modules.conf" && -f "$DOTFILES_DIR/_scripts/list-modules.sh" ]]; then
    # macOS 自带 bash 3.2 无 mapfile，改用 while read
    while IFS= read -r _module; do
        STOW_MODULES+=("$_module")
    done < <(bash "$DOTFILES_DIR/_scripts/list-modules.sh" "$DOTFILES_DIR/_scripts/modules.conf")
    unset _module
fi

if (( ${#STOW_MODULES[@]} == 0 )); then
    warn "modules.conf 中未发现有效的模块列表，正在尝试默认列表..."
    STOW_MODULES=(agents zsh git vim nvim tmux ripgrep)
else
    info "从 _scripts/modules.conf 加载模块: ${STOW_MODULES[*]}"
fi

## 2. 执行 Stow 挂载
# 统一入口负责 preflight、冲突备份、共享目录创建、stow -R 和挂载后校验。
# 挂载失败仅提示，不阻断后续配置。
if bash "$DOTFILES_DIR/_scripts/stow-sync.sh" \
    "$DOTFILES_DIR" "$HOME" "${STOW_MODULES[@]}"; then
    ok "Stow 配置挂载完成"
else
    warn "Stow 配置挂载有失败项（详情见上方报错），可稍后运行 make sync 修复"
fi

# ── 7. tmux 插件同步 (tpm) ──────────────────────────────────────
echo ""
info "正在同步 tmux 插件 (tpm)..."
if bash "$DOTFILES_DIR/_scripts/tmux-plugins.sh"; then
    ok "tmux 插件就绪"
else
    warn "tmux 插件同步过程中有报错，可稍后运行 bash _scripts/tmux-plugins.sh 重试"
fi

# ── 8. 编辑器插件同步 ──────────────────────────────────────
echo ""
info "📋 请选择要同步的编辑器插件："
echo "   1) Neovim (lazy.nvim) - [默认]"
echo "   2) Vim (vim-plug)"
echo "   3) 两者都要"
echo "   4) 跳过"
if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
    editor_choice="4"
else
    editor_choice="$(ask_value "请输入数字 [1-4]: " "1")"
fi

## 1. Neovim 插件 (lazy.nvim)
if [[ "$editor_choice" == "1" || "$editor_choice" == "3" ]]; then
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
        if vim -Nu "$HOME/.vimrc" -n -es \
            '+if !exists(":PlugInstall") | cquit 2 | endif' '+qa!'; then
            info "正在安装/更新 Vim 插件..."
            if vim -Nu "$HOME/.vimrc" -n -es '+PlugUpdate --sync' '+qa!'; then
                ok "Vim 插件就绪"
            else
                warn "Vim 插件同步失败，请检查上方输出后重试"
            fi
        else
            warn "vim-plug 未能加载，请检查 ~/.vimrc 与 runtimepath"
        fi
    fi
fi

# ── 9. 自定义脚本部署 ──────────────────────────────────────────────
info "正在部署自定义脚本..."

# proj-setup: 项目初始化工具
if [[ -f "$DOTFILES_DIR/proj-setup/bin/proj-setup.sh" ]]; then
    mkdir -p "$HOME/.local/bin"
    ln -sf "$DOTFILES_DIR/proj-setup/bin/proj-setup.sh" "$HOME/.local/bin/proj-setup"
    ok "proj-setup 已部署到 ~/.local/bin/proj-setup"
else
    warn "proj-setup.sh 未找到，跳过部署"
fi

# ── 10. 完成 ────────────────────────────────────────────────────────
echo ""
ok "🎉 全部搞定！请重启终端，或执行 source ~/.zshrc 使配置生效。"
echo ""

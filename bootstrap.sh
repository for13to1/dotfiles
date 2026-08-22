#!/usr/bin/env bash
#
# bootstrap.sh — 开发环境部署入口
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

# ── 3-5. 主机基础配置 ────────────────────────────────────────────
bash "$DOTFILES_DIR/_bootstrap/ssh.sh"
bash "$DOTFILES_DIR/_bootstrap/git.sh" "$DOTFILES_DIR"
bash "$DOTFILES_DIR/_bootstrap/shell.sh" "$OS" "${SELECTED_MIRROR:-}"

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

# ── 8. 编辑器插件同步 ────────────────────────────────────────────
echo ""
bash "$DOTFILES_DIR/_bootstrap/editors.sh"

# ── 9. 自定义脚本部署 ──────────────────────────────────────────────
bash "$DOTFILES_DIR/_bootstrap/tools.sh" "$DOTFILES_DIR"

# ── 10. 完成 ────────────────────────────────────────────────────────
echo ""
ok "🎉 全部搞定！请重启终端，或执行 source ~/.zshrc 使配置生效。"
echo ""

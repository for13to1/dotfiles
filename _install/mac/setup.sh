#!/usr/bin/env bash
#
# install/mac/setup.sh — macOS 系统偏好设置
# 按需取消注释你想要的配置项
#

echo "正在应用 macOS 系统偏好设置..."

# ── Dock ─────────────────────────────────────────────────────────
# Dock 自动隐藏
# defaults write com.apple.dock autohide -bool true

# 缩短 Dock 自动隐藏的延迟时间
# defaults write com.apple.dock autohide-delay -float 0
# defaults write com.apple.dock autohide-time-modifier -float 0.3

# ── Finder ───────────────────────────────────────────────────────
# 显示所有文件扩展名
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# 在状态栏显示完整路径
defaults write com.apple.finder ShowPathbar -bool true

# 默认使用列表视图（icnv=图标, clmv=分栏, glyv=画廊, Nlsv=列表）
# defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# ── 键盘 ─────────────────────────────────────────────────────────
# 关闭长按弹出重音字符菜单（Vim 用户福音）
# defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# 加快按键重复速度
# defaults write NSGlobalDomain KeyRepeat -int 2
# defaults write NSGlobalDomain InitialKeyRepeat -int 15

# ── 截图 ─────────────────────────────────────────────────────────
# 截图保存到 ~/Pictures/Screenshots
# mkdir -p "$HOME/Pictures/Screenshots"
# defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"

# ── 重启相关服务使设置生效 ───────────────────────────────────────
killall Finder 2>/dev/null || true
# killall Dock 2>/dev/null || true

echo "macOS 偏好设置已应用。"

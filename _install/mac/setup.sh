#!/usr/bin/env bash
#
# install/mac/setup.sh — macOS 系统偏好设置
# 按需取消注释你想要的配置项
#

echo "正在应用 macOS 系统偏好设置..."

# ── 辅助函数 ─────────────────────────────────────────────────────
# 用法: set_default <domain> <key> <type> <value> [description]
# 先读取当前值，再写入新值，并显示变更
set_default() {
    local domain="$1" key="$2" type="$3" value="$4" desc="${5:-$key}"
    local old
    old=$(defaults read "$domain" "$key" 2>/dev/null) || old="(未设置)"
    defaults write "$domain" "$key" "$type" "$value" 2>/dev/null || return 1
    if [[ "$old" == "$value" ]]; then
        echo "  ✓ $desc: $old (无变化)"
    else
        echo "  ✓ $desc: $old → $value"
    fi
}

# ── Dock ─────────────────────────────────────────────────────────
# Dock 自动隐藏
# set_default com.apple.dock autohide -bool true "自动隐藏 Dock"

# 缩短 Dock 自动隐藏的延迟时间
# set_default com.apple.dock autohide-delay -float 0 "隐藏延迟"
# set_default com.apple.dock autohide-time-modifier -float 0.3 "隐藏动画时长"

# ── Finder ───────────────────────────────────────────────────────
set_default NSGlobalDomain AppleShowAllExtensions -bool true "显示所有文件扩展名"
set_default com.apple.finder ShowPathbar -bool true "显示路径栏"
set_default com.apple.finder FinderSpawnTab -bool true "在标签页中打开文件夹"

# 默认使用列表视图（icnv=图标, clmv=分栏, glyv=画廊, Nlsv=列表）
set_default com.apple.finder FXPreferredViewStyle -string "Nlsv" "默认列表视图"

# ── Safari ───────────────────────────────────────────────────────
# ⚠️ macOS Sonoma+ 将 Safari 偏好设置移入沙箱容器
SAFARI_PLIST="$HOME/Library/Containers/com.apple.Safari/Data/Library/Preferences/com.apple.Safari"

# 关闭"下载后自动打开安全文件"
set_default "$SAFARI_PLIST" AutoOpenSafeDownloads -bool false "关闭自动打开安全下载" \
  || set_default com.apple.Safari AutoOpenSafeDownloads -bool false "关闭自动打开安全下载" || true

# 显示状态栏（鼠标悬停链接时可在底部看到链接地址）
set_default "$SAFARI_PLIST" ShowOverlayStatusBar -bool true "显示状态栏" \
  || set_default com.apple.Safari ShowOverlayStatusBar -bool true "显示状态栏" || true

# 在地址栏显示完整 URL
set_default "$SAFARI_PLIST" ShowFullURLInSmartSearchField -bool true "显示完整网址" \
  || set_default com.apple.Safari ShowFullURLInSmartSearchField -bool true "显示完整网址" || true

# ── 键盘 ─────────────────────────────────────────────────────────
# 关闭长按弹出重音字符菜单（Vim 用户福音）
# set_default NSGlobalDomain ApplePressAndHoldEnabled -bool false "关闭长按重音菜单"

# 加快按键重复速度
# set_default NSGlobalDomain KeyRepeat -int 2 "按键重复速率"
# set_default NSGlobalDomain InitialKeyRepeat -int 15 "按键重复初始延迟"

# ── 截图 ─────────────────────────────────────────────────────────
# 截图保存到 ~/Pictures/Screenshots
# mkdir -p "$HOME/Pictures/Screenshots"
# set_default com.apple.screencapture location -string "$HOME/Pictures/Screenshots" "截图保存路径"

# ── 完全磁盘访问权限 (Full Disk Access) ──────────────────────────
# 无法通过脚本自动授权，只能检测并引导用户手动设置
if ! cat ~/Library/Mail/V*/MailData/Signatures/*.plist &>/dev/null 2>&1 \
  && ! ls ~/Library/Safari/Bookmarks.plist &>/dev/null 2>&1; then
  echo ""
  echo "⚠️  当前终端没有「完全磁盘访问权限」"
  echo "   这会导致 brew uninstall --zap 无法完整清理应用残留"
  echo "   同时终端也无法访问邮件、Safari 等受保护的用户数据目录"
  echo ""
  echo "   请在弹出的系统设置中，将你的终端添加到列表并开启开关："

  # 检测当前终端应用
  TERM_APP=""
  if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
    TERM_APP="iTerm2"
  elif [[ "$TERM_PROGRAM" == "Apple_Terminal" ]]; then
    TERM_APP="Terminal"
  elif [[ -n "$TERM_PROGRAM" ]]; then
    TERM_APP="$TERM_PROGRAM"
  fi
  [[ -n "$TERM_APP" ]] && echo "   → 你当前使用的是: $TERM_APP"

  echo ""
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
  read -rp "   设置完成后按 Enter 继续..."
fi

# ── 重启相关服务使设置生效 ───────────────────────────────────────
killall Finder 2>/dev/null || true
# killall Dock 2>/dev/null || true

echo "macOS 偏好设置已应用。"

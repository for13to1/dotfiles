#!/usr/bin/env bash
#
# _setup/mac/setup.sh — macOS 系统偏好设置
#

set -euo pipefail

# ── 彩色输出 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; exit 1; }

echo "正在应用 macOS 系统偏好设置..."

# ── 辅助函数 ─────────────────────────────────────────────────────

_normalize_bool() {
    local val="$1"
    if [[ "$val" == "1" || "$val" == "true" ]]; then echo "true";
    elif [[ "$val" == "0" || "$val" == "false" ]]; then echo "false";
    else echo "$val"; fi
}

_get_pretty_domain() {
    local domain="$1"
    [[ "$domain" == "NSGlobalDomain" ]] && { echo "Global"; return; }
    local name="${domain##*.}"
    echo "$(tr '[:lower:]' '[:upper:]' <<< "${name:0:1}")${name:1}"
}

set_default() {
    local target="$1" key="$2" type="$3" value="$4" desc="${5:-$key}"
    local pretty_domain
    pretty_domain=$(_get_pretty_domain "$target")
    
    local old_raw
    old_raw=$(defaults read "$target" "$key" 2>/dev/null) || old_raw="(未设置)"
    
    local old_norm="$old_raw"
    [[ "$type" == "-bool" ]] && old_norm=$(_normalize_bool "$old_raw")
    
    local msg="[$pretty_domain] $desc"
    if [[ "$old_norm" == "$value" ]]; then
        echo "  ✓ $msg: $old_norm (无变化)"
    else
        if defaults write "$target" "$key" "$type" "$value" 2>/dev/null; then
            echo "  ✓ $msg: $old_norm → $value"
        else
            echo "  ✗ $msg: 写入失败"
            return 1
        fi
    fi
}

# ── 核心项目 ──────────────────────────────────────────────────────

# 1. Global
set_default NSGlobalDomain AppleShowAllExtensions -bool true "显示所有文件扩展名"

# 2. Finder
set_default com.apple.finder ShowPathbar -bool true "显示路径栏"
set_default com.apple.finder FinderSpawnTab -bool true "在标签页中打开文件夹"
set_default com.apple.finder FXPreferredViewStyle -string "Nlsv" "默认列表视图"

# ── 重载生效 ──────────────────────────────────────────────────────
echo ""
read -rp "是否立即重启 Finder 以使设置生效？ [y/N]: " restart_apps
if [[ "$restart_apps" =~ ^[Yy]$ ]]; then
    info "正在重启 Finder..."
    # killall 是 macOS 推荐的重载方式，比 pkill -9 更安全、更体面
    killall Finder 2>/dev/null || true
    ok "Finder 已重载"
else
    info "设置已写入。Finder 将在下次系统重启或手动重启后生效。"
fi

ok "macOS 偏好设置调整完毕。"

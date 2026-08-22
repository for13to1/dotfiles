#!/usr/bin/env bash
#
# _setup/mac/setup.sh — apply macOS system preferences
#

set -euo pipefail

# ── Shared infrastructure (colored output etc.) ─────────────────
SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../_scripts/common.sh"

echo "Applying macOS system preferences..."

# ── Helpers ─────────────────────────────────────────────────

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
    local target="$1" key="$2" type="$3" value="$4"
    local desc="${5:-$key}"
    local pretty_domain
    pretty_domain=$(_get_pretty_domain "$target")

    local old_raw
    old_raw=$(defaults read "$target" "$key" 2>/dev/null) || old_raw="(not set)"

    local old_norm="$old_raw"
    [[ "$type" == "-bool" ]] && old_norm=$(_normalize_bool "$old_raw")

    local msg="[$pretty_domain] $desc"
    if [[ "$old_norm" == "$value" ]]; then
        echo "  ✓ $msg: $old_norm (unchanged)"
    else
        if defaults write "$target" "$key" "$type" "$value" 2>/dev/null; then
            echo "  ✓ $msg: $old_norm → $value"
        else
            echo "  ✗ $msg: write failed"
            return 1
        fi
    fi
}

# ── Core settings ─────────────────────────────────────────────

# 1. Global
set_default NSGlobalDomain AppleShowAllExtensions -bool true "Show all filename extensions"

# 2. Finder
set_default com.apple.finder ShowPathbar -bool true "Show the path bar"
set_default com.apple.finder FinderSpawnTab -bool true "Open folders in tabs"
set_default com.apple.finder FXPreferredViewStyle -string "Nlsv" "Default list view"

# ── Reload ─────────────────────────────────────────────────────
echo ""
if confirm "Restart Finder now to apply the settings? [y/N]: " 0; then
    info "Restarting Finder..."
    # killall is the recommended macOS reload; safer and cleaner than pkill -9.
    killall Finder 2>/dev/null || true
    ok "Finder reloaded"
else
    info "Settings written. Finder will apply them on the next system restart or a manual restart."
fi

ok "macOS preferences applied."

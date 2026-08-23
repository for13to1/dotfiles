#!/usr/bin/env bash
# _bootstrap/pkg-mac.sh — macOS Homebrew and package manager setup
# Usage: pkg-mac.sh [dotfiles_dir] [mirror_override]

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

# Progress/interactive output goes to stderr; stdout emits the selected mirror name for callers.
info()      { msg 'info'  "$*" >&2; }
warn()      { msg 'warn'  "$*" >&2; }
ok()        { msg 'ok'    "$*" >&2; }
error_msg() { msg 'error' "$*" >&2; }

main() {
    local repo_dir="${1:-$DOTFILES_DIR}"
    local mirror_override="${2:-}"
    local resolved_dir=""

    resolved_dir="$(dotfiles_dir "$repo_dir")" || error "Cannot access dotfiles dir: $repo_dir"
    DOTFILES_DIR="$resolved_dir"

    info "🍎 macOS environment, starting setup..."

    # Detect Xcode tooling: prefer a full Xcode.app, otherwise install the slim CLT.
    local xcode_app_path="${XCODE_APP_DIR:-/Applications/Xcode.app}"
    if [[ -d "$xcode_app_path" ]]; then
        if ! xcodebuild -version &>/dev/null; then
            info "Xcode.app detected but xcode-select does not point to it; switching..."
            sudo xcode-select -s "$xcode_app_path/Contents/Developer" >&2
        fi
        ok "Xcode.app ready"
    elif ! xcode-select -p &>/dev/null; then
        info "Xcode.app not found; installing Command Line Tools..."
        xcode-select --install >&2
        echo "Click \"Install\" in the dialog, then rerun bootstrap.sh." >&2
        exit 10
    else
        ok "Xcode Command Line Tools ready"
    fi

    if [[ -f "$DOTFILES_DIR/zsh/.zsh.d/brew_mirror.sh" ]]; then
        # shellcheck disable=SC1091
        source "$DOTFILES_DIR/zsh/.zsh.d/brew_mirror.sh"
    else
        error "brew_mirror.sh not found"
    fi

    local selected_mirror=""
    if [[ -n "$mirror_override" ]]; then
        selected_mirror="$mirror_override"
    elif [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
        selected_mirror="tuna"
    else
        echo "" >&2
        info "🌍 Homebrew mirror selection:"
        echo "   1) Tsinghua (TUNA) - [default]" >&2
        echo "   2) USTC" >&2
        echo "   3) Aliyun" >&2
        echo "   4) Skip (use official sources)" >&2
        local mirror_choice
        mirror_choice="$(ask_value "Enter a number [1-4]: " "1")"
        case "$mirror_choice" in
            1) selected_mirror="tuna" ;;
            2) selected_mirror="ustc" ;;
            3) selected_mirror="ali"  ;;
            *) selected_mirror=""     ;;
        esac
    fi

    if [[ -n "$selected_mirror" ]]; then
        brew_mirror -q "$selected_mirror" >&2
        ok "Temporarily set the $selected_mirror mirror to speed up installation"
    elif command -v brew &>/dev/null; then
        brew_mirror -q reset >&2
        ok "Reset to the official Homebrew sources"
    else
        info "Using the official Homebrew sources by default"
    fi

    # Install Homebrew if missing.
    if ! command -v brew &>/dev/null; then
        info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" >&2
        if [[ "$(uname -m)" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi
    ok "Homebrew ready"

    # Ensure hard script dependencies are installed.
    if ! command -v stow &>/dev/null; then
        info "Installing stow..."
        brew install stow >&2
    fi

    # Install the default group.
    info "Updating Homebrew and installing the default group..."
    brew update >&2 || warn "Homebrew index update did not fully complete; continuing with the install..."
    if bash "$DOTFILES_DIR/_install/install" --brew >&2; then
        ok "Default group installed"
    else
        warn "Some packages in the default group failed; run 'bash _install/install --brew' later to retry"
    fi
    hint_optional_groups brew "$DOTFILES_DIR"

    # Apply macOS system preferences.
    if [[ -f "$DOTFILES_DIR/_setup/mac/setup.sh" ]]; then
        info "Applying macOS system preferences..."
        bash "$DOTFILES_DIR/_setup/mac/setup.sh" >&2
        ok "macOS preferences applied"
    fi

    # Emit ONLY the selected mirror name on stdout for callers (e.g. bootstrap.sh / shell.sh)
    printf '%s\n' "${selected_mirror:-}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

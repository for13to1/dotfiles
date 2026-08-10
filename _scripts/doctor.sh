#!/usr/bin/env bash
#
# doctor.sh - diagnose local dotfiles environment health
# Usage: bash _scripts/doctor.sh <dotfiles-dir> <home-dir>
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

DOTFILES_DIR="${1:-}"
TARGET_DIR="${2:-}"

if [[ -z "$DOTFILES_DIR" || -z "$TARGET_DIR" ]]; then
    echo "Usage: $0 <dotfiles-dir> <home-dir>" >&2
    exit 2
fi

DOTFILES_DIR="$(cd -P -- "$DOTFILES_DIR" 2>/dev/null && pwd -P)" || {
    echo "Cannot access dotfiles directory: $DOTFILES_DIR" >&2
    exit 1
}
TARGET_DIR="$(cd -P -- "$TARGET_DIR" 2>/dev/null && pwd -P)" || {
    echo "Cannot access target directory: $TARGET_DIR" >&2
    exit 1
}

failed=0
warnings=0

doctor_ok() {
    ok "$*"
}

doctor_warn() {
    warn "$*"
    warnings=$((warnings + 1))
}

doctor_fail() {
    echo -e "${RED}❌ $*${NC}"
    failed=$((failed + 1))
}

check_required_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        doctor_ok "required command: $cmd"
    else
        doctor_fail "required command missing: $cmd"
    fi
}

check_optional_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        doctor_ok "optional command: $cmd"
    else
        doctor_warn "optional command missing: $cmd"
    fi
}

check_local_file() {
    local path="$1"
    local label="$2"
    if [[ -f "$path" ]]; then
        doctor_ok "$label exists: $path"
    else
        doctor_warn "$label missing: $path"
    fi
}

check_modules_config() {
    local conf="$DOTFILES_DIR/_scripts/modules.conf"
    local modules=()
    local module

    if [[ ! -r "$conf" ]]; then
        doctor_fail "modules config unreadable: $conf"
        return
    fi

    while IFS= read -r module; do
        modules+=("$module")
    done < <(bash "$DOTFILES_DIR/_scripts/list-modules.sh" "$conf")

    if (( ${#modules[@]} == 0 )); then
        doctor_fail "modules config has no modules: $conf"
        return
    fi

    doctor_ok "modules config parsed: ${#modules[@]} module(s)"
    for module in "${modules[@]}"; do
        if [[ -d "$DOTFILES_DIR/$module" ]]; then
            doctor_ok "stow module exists: $module"
        else
            doctor_fail "stow module missing: $module"
        fi
    done
}

check_link_state() {
    local conf="$DOTFILES_DIR/_scripts/modules.conf"
    local modules=()
    local module

    [[ -r "$conf" ]] || return
    while IFS= read -r module; do
        modules+=("$module")
    done < <(bash "$DOTFILES_DIR/_scripts/list-modules.sh" "$conf")

    (( ${#modules[@]} > 0 )) || return

    if bash "$DOTFILES_DIR/_scripts/check-links.sh" verify "$DOTFILES_DIR" "$TARGET_DIR" "${modules[@]}" >/dev/null 2>&1; then
        doctor_ok "stow links verify cleanly"
    else
        doctor_warn "stow links are not fully synced; run make sync when ready"
    fi
}

info "Dotfiles doctor"
info "dotfiles: $DOTFILES_DIR"
info "target: $TARGET_DIR"

echo ""
info "Required tools"
check_required_command git
check_required_command stow
check_required_command zsh
check_required_command make

echo ""
info "Optional tools"
check_optional_command nvim
check_optional_command vim
check_optional_command tmux
check_optional_command rg
check_optional_command fnm

echo ""
info "Local private config"
check_local_file "$TARGET_DIR/.zshrc.local" "zsh local config"
check_local_file "$TARGET_DIR/.gitconfig.local" "git local config"

echo ""
info "Stow modules"
check_modules_config
check_link_state

echo ""
if (( failed > 0 )); then
    doctor_fail "doctor found $failed blocking issue(s) and $warnings warning(s)"
    exit 1
fi

if (( warnings > 0 )); then
    doctor_warn "doctor completed with $warnings warning(s)"
    exit 0
fi

doctor_ok "doctor completed cleanly"

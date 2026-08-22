#!/usr/bin/env bash
#
# doctor.sh - diagnose local dotfiles environment health
# Usage: bash _scripts/doctor.sh <dotfiles-dir> <home-dir>
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

DOTFILES_DIR="${1:-$DOTFILES_DIR}"
TARGET_DIR="${2:-}"

if [[ -z "$DOTFILES_DIR" || -z "$TARGET_DIR" ]]; then
    echo "Usage: $0 <dotfiles-dir> <home-dir>" >&2
    exit 2
fi

DOTFILES_DIR="$(dotfiles_dir "$DOTFILES_DIR")" || {
    echo "Cannot access dotfiles directory: $DOTFILES_DIR" >&2
    exit 1
}
TARGET_DIR="$(cd -P -- "$TARGET_DIR" 2>/dev/null && pwd -P)" || {
    echo "Cannot access target directory: $TARGET_DIR" >&2
    exit 1
}

failed=0
warnings=0

doctor_warn() {
    warn "$*"
    warnings=$((warnings + 1))
}

doctor_fail() {
    error_msg "$*"
    failed=$((failed + 1))
}

MODULES=()
load_modules() {
    local conf="$DOTFILES_DIR/_scripts/modules.conf"
    local module
    MODULES=()
    [[ -r "$conf" ]] || return 1
    while IFS= read -r module; do
        MODULES+=("$module")
    done < <(bash "$DOTFILES_DIR/_scripts/list-modules.sh" "$conf")
}

check_required_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "required command: $cmd"
    else
        doctor_fail "required command missing: $cmd"
    fi
}

check_optional_command() {
    local cmd="$1"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "optional command: $cmd"
    else
        doctor_warn "optional command missing: $cmd"
    fi
}

check_local_file() {
    local path="$1"
    local label="$2"
    if [[ -f "$path" ]]; then
        ok "$label exists: $path"
    else
        doctor_warn "$label missing: $path"
    fi
}

check_modules_config() {
    local conf="$DOTFILES_DIR/_scripts/modules.conf"

    if [[ ! -r "$conf" ]]; then
        doctor_fail "modules config unreadable: $conf"
        return
    fi

    if (( ${#MODULES[@]} == 0 )); then
        doctor_fail "modules config has no modules: $conf"
        return
    fi

    ok "modules config parsed: ${#MODULES[@]} module(s)"
    for module in "${MODULES[@]}"; do
        if [[ -d "$DOTFILES_DIR/$module" ]]; then
            ok "stow module exists: $module"
        else
            doctor_fail "stow module missing: $module"
        fi
    done
}

check_link_state() {
    (( ${#MODULES[@]} > 0 )) || return

    if bash "$DOTFILES_DIR/_scripts/check-links.sh" verify "$DOTFILES_DIR" "$TARGET_DIR" "${MODULES[@]}" >/dev/null 2>&1; then
        ok "stow links verify cleanly"
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
check_optional_command fd
check_optional_command bat
check_optional_command fnm

echo ""
info "Editor toolchain"
check_optional_command biome
check_optional_command ruff
check_optional_command stylua
check_optional_command shfmt
check_optional_command clang-format
check_optional_command clangd
check_optional_command rustfmt

echo ""
info "Local private config"
check_local_file "$TARGET_DIR/.zshrc.local" "zsh local config"
check_local_file "$TARGET_DIR/.gitconfig.local" "git local config"

echo ""
info "Stow modules"
load_modules || true
check_modules_config
check_link_state

echo ""
if (( failed > 0 )); then
    error_msg "doctor found $failed blocking issue(s) and $warnings warning(s)"
    exit 1
fi

if (( warnings > 0 )); then
    warn "doctor completed with $warnings warning(s)"
    exit 0
fi

ok "doctor completed cleanly"

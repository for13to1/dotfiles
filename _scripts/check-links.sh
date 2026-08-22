#!/usr/bin/env bash
#
# check-links.sh — Stow link checker
#
# Usage:
#   check-links.sh preflight <dotfiles-dir> <target-dir> <module>...
#       Pre-mount check: ensure target parents are not folded into symlinks, so stow
#       does not fold at the wrong level.
#   check-links.sh verify <dotfiles-dir> <target-dir> <module>...
#       Post-mount check: ensure every module's symlink points into the dotfiles repo.
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

CMD="${1:-}"
if [[ -z "$CMD" ]]; then
    echo "Usage: $0 <preflight|verify> <dotfiles-dir> <target-dir> <module>..." >&2
    exit 2
fi
shift

if (( $# < 3 )); then
    echo "Usage: $0 $CMD <dotfiles-dir> <target-dir> <module>..." >&2
    exit 2
fi

DOTFILES_DIR="${1:-$DOTFILES_DIR}"
TARGET_DIR="$2"
shift 2

# Canonicalize the source dir (dotfiles_dir) to avoid misdetection on symlinked
# paths like /tmp or /var.
DOTFILES_DIR="$(dotfiles_dir "$DOTFILES_DIR")" || {
    echo "Cannot access dotfiles dir: $DOTFILES_DIR" >&2
    exit 1
}

# ── preflight: pre-mount check ────────────────────────────────────
preflight_check_tree() {
    local module="$1"
    local directory="$2"
    local entry relative target parent

    while IFS= read -r -d '' entry; do
        relative="${entry#"$module"/}"
        target="$TARGET_DIR/$relative"
        parent="$(dirname "$target")"

        if [[ -L "$parent" ]]; then
            error_msg "$parent is a symlink; handle it manually before running stow" >&2
            return 1
        fi

        if [[ -L "$target" ]]; then
            if [[ "$(resolved_link_target "$target")" != "$(physical_path "$entry")" ]]; then
                error_msg "$target is a symlink; handle it manually before running stow" >&2
                return 1
            fi
        elif [[ -d "$entry" && ! -L "$entry" && -d "$target" ]]; then
            preflight_check_tree "$module" "$entry"
        fi
    done < <(stow_find "$directory" -mindepth 1 -maxdepth 1 \
        \( -type f -o -type l -o -type d \))
}

preflight() {
    cd "$DOTFILES_DIR"
    for module in "$@"; do
        if [[ ! -d "$module" ]]; then
            warn "Module dir does not exist: $module" >&2
            return 1
        fi
        preflight_check_tree "$module" "$module"
    done
}

# ── verify: post-mount check ──────────────────────────────────────
verify_entry() {
    local mod="$1"
    local entry="$2"
    local rel="${entry#"$mod"/}"
    local target="$TARGET_DIR/$rel"
    local src
    src="$(physical_path "$DOTFILES_DIR/$entry")"

    if [[ -L "$target" ]]; then
        local resolved
        resolved="$(resolved_link_target "$target")"
        if [[ "$resolved" == "$src" ]]; then
            return 0
        fi
        error_msg "$rel → symlink points to the wrong target" >&2
        return 1
    fi

    if [[ ! -e "$target" ]]; then
        error_msg "$rel → symlink missing" >&2
        return 1
    fi

    if [[ -d "$entry" && -d "$target" ]]; then
        local sub
        while IFS= read -r -d '' sub; do
            verify_entry "$mod" "$sub" || return 1
        done < <(stow_find "$entry" -mindepth 1 -maxdepth 1)
        return 0
    fi

    error_msg "$rel → exists but is not a correct symlink" >&2
    return 1
}

verify() {
    cd "$DOTFILES_DIR"
    local failed=0
    info "Checking symlink status..."

    for mod in "$@"; do
        if [[ ! -d "$mod" ]]; then
            warn "Module dir does not exist: $mod" >&2
            failed=1
            continue
        fi

        local errors=0
        local entry
        while IFS= read -r -d '' entry; do
            verify_entry "$mod" "$entry" || errors=$((errors + 1))
        done < <(stow_find "$mod" -mindepth 1 -maxdepth 1)

        if (( errors == 0 )); then
            ok "$mod"
        else
            failed=1
        fi
    done

    if (( failed == 0 )); then
        ok "All checks passed!"
    else
        error_msg "Issues found; run 'make sync' to fix." >&2
        exit 1
    fi
}

case "$CMD" in
    preflight) preflight "$@" ;;
    verify)    verify "$@" ;;
    *)
        error_msg "Unknown subcommand: $CMD (choices: preflight | verify)" >&2
        exit 2
        ;;
esac

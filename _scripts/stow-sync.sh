#!/usr/bin/env bash
#
# stow-sync.sh — single Stow sync entry point
# Usage: stow-sync.sh <dotfiles-dir> <target-dir> <module>...
# Runs preflight, conflict backup, shared dir creation, stow -R, and post-mount verify.
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

if (( $# < 2 )); then
    echo "Usage: $0 <dotfiles-dir> <target-dir> <module>..." >&2
    exit 2
fi

DOTFILES_DIR="${1:-$DOTFILES_DIR}"
TARGET_DIR="$2"
shift 2

DOTFILES_DIR="$(dotfiles_dir "$DOTFILES_DIR")" || {
    echo "Cannot access dotfiles dir: $DOTFILES_DIR" >&2
    exit 1
}
TARGET_DIR="$(cd -P -- "$TARGET_DIR" 2>/dev/null && pwd -P)" || {
    echo "Cannot access target dir: $TARGET_DIR" >&2
    exit 1
}

if (( $# == 0 )); then
    warn "No modules to mount; skipping Stow"
    exit 0
fi

cd "$DOTFILES_DIR"
info "Syncing Stow modules: $* ..."

bash "$SCRIPT_DIR/check-links.sh" preflight "$DOTFILES_DIR" "$TARGET_DIR" "$@" \
    || warn "Preflight reported issues; continuing with backup and mount"

# These are system-shared directories that must not be backed up; after backup, stow
# would fold the whole directory.
SHARED_PARENT_DIRS=(".config")

backup_explicit_conflicts() {
    local mod="$1"
    local rel_path="$2"
    local full_target="$TARGET_DIR${rel_path:+/$rel_path}"

    for shared in "${SHARED_PARENT_DIRS[@]}"; do
        if [[ "$rel_path" == "$shared" ]]; then
            return 0
        fi
    done

    if [[ -e "$full_target" && ! -L "$full_target" ]]; then
        local p link_target
        p="$(dirname "$full_target")"
        while [[ "$p" != "$TARGET_DIR" ]]; do
            if [[ -L "$p" ]]; then
                link_target="$(resolved_link_target "$p")"
                if [[ "$link_target" == "$DOTFILES_DIR" || "$link_target" == "$DOTFILES_DIR/"* ]]; then
                    return 0
                fi
                break
            fi
            p="$(dirname "$p")"
        done

        local timestamp
        timestamp="$(date +%Y%m%d_%H%M%S)"
        warn "Found conflicting file/dir $full_target (not a symlink); backing up to $full_target.bak.$timestamp"
        mv "$full_target" "$full_target.bak.$timestamp"
    fi
}

backup_module_conflicts() {
    local mod="$1"
    local path rel

    [[ -d "$mod" ]] || return 0

    while IFS= read -r -d '' path; do
        rel="${path#"$mod"/}"
        # Back up directory conflicts as whole directories.
        backup_explicit_conflicts "$mod" "$rel"
    done < <(stow_find "$mod" -mindepth 1 -type d)

    while IFS= read -r -d '' path; do
        rel="${path#"$mod"/}"
        # Back up file conflicts by file path.
        local parent
        parent="$TARGET_DIR/$(dirname "$rel")"
        [[ -e "$parent" || -L "$parent" ]] || continue
        backup_explicit_conflicts "$mod" "$rel"
    done < <(stow_find "$mod" -mindepth 1 \( -type f -o -type l \))
}

for mod in "$@"; do
    backup_module_conflicts "$mod"
done

for shared in "${SHARED_PARENT_DIRS[@]}"; do
    mkdir -p "$TARGET_DIR/$shared"
done

stow_args=()
for ignore in "${STOW_IGNORE_NAMES[@]}"; do
    stow_args+=( "--ignore=$ignore" )
done
stow_args+=( -t "$TARGET_DIR" )

# Mount module by module: one failure does not affect the rest; failures are tallied.
FAILED=0
for mod in "$@"; do
    stow "${stow_args[@]}" -R "$mod" || { error_msg "Mount failed: $mod"; FAILED=1; }
done

if (( FAILED == 0 )); then
    bash "$SCRIPT_DIR/check-links.sh" verify "$DOTFILES_DIR" "$TARGET_DIR" "$@" \
        || FAILED=1
fi

if (( FAILED )); then
    error_msg "Stow sync had failures; run 'make sync' to fix"
    exit 1
fi
ok "Stow sync complete"

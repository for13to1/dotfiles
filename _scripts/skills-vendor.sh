#!/usr/bin/env bash
#
# _scripts/skills-vendor.sh — Multi-vendor pluggable AI skills manager
# Usage:
#   skills-vendor.sh attach [vendor]   # Initialize submodule(s) and symlink skills into agents/
#   skills-vendor.sh detach [vendor]   # Remove external skill symlinks from agents/
#   skills-vendor.sh update [vendor]   # Update submodule(s) to latest upstream commit
#   skills-vendor.sh list              # List bundled skills, attached vendor skills, and available vendors
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

DOTFILES_DIR="$(dotfiles_dir)" || error "Cannot access dotfiles dir"

VENDOR_ROOT="$DOTFILES_DIR/_vendor"
SKILLS_ROOT="$DOTFILES_DIR/agents/.agents/skills"

cmd_attach() {
    local target_vendor="${1:-}"
    local search_path="$VENDOR_ROOT"

    if [[ ! -d "$VENDOR_ROOT" ]]; then
        warn "No _vendor directory found at $VENDOR_ROOT"
        return 0
    fi

    if [[ -n "$target_vendor" ]]; then
        search_path="$VENDOR_ROOT/$target_vendor"
        if [[ ! -d "$search_path" ]]; then
            error "Vendor '$target_vendor' not found under $VENDOR_ROOT"
        fi
        info "Initializing submodule for vendor: $target_vendor..."
        git -C "$DOTFILES_DIR" submodule update --init --recursive "${search_path#"$DOTFILES_DIR"/}"
    else
        info "Initializing all vendor submodules under _vendor/..."
        git -C "$DOTFILES_DIR" submodule update --init --recursive _vendor
    fi

    info "Discovering and linking skills from $search_path..."
    mkdir -p "$SKILLS_ROOT"

    local attached_count=0
    while IFS= read -r -d '' skill_file; do
        local skill_dir skill_name vendor_name rel_from_vendor target_link rel_target
        skill_dir="$(dirname "$skill_file")"
        skill_name="$(basename "$skill_dir")"

        rel_from_vendor="${skill_dir#"$VENDOR_ROOT"/}"
        vendor_name="${rel_from_vendor%%/*}"

        target_link="$SKILLS_ROOT/$skill_name"

        # 1. Protect bundled non-symlink skills from being overwritten
        if [[ -d "$target_link" && ! -L "$target_link" ]]; then
            warn "Skipping '$skill_name' from $vendor_name (collides with bundled skill)"
            continue
        fi

        # 2. Collision resolution across multiple vendors
        if [[ -L "$target_link" ]]; then
            local existing_target
            existing_target="$(readlink "$target_link")"
            if [[ "$existing_target" != *"_vendor/$vendor_name/"* ]]; then
                warn "Collision: '$skill_name' already linked from another vendor; prefixing as '$vendor_name-$skill_name'"
                target_link="$SKILLS_ROOT/$vendor_name-$skill_name"
            fi
        fi

        # 3. Create relative symlink
        rel_target="../../../${skill_dir#"$DOTFILES_DIR"/}"
        ln -sf "$rel_target" "$target_link"
        ok "Attached: $(basename "$target_link") (vendor: $vendor_name)"
        attached_count=$((attached_count + 1))
    done < <(find "$search_path" -type f -name "SKILL.md" -not -path '*/.git/*' -print0)

    if (( attached_count == 0 )); then
        warn "No SKILL.md files found in $search_path"
    else
        info "Syncing Stow agents module..."
        bash "$SCRIPT_DIR/stow-sync.sh" "$DOTFILES_DIR" "$HOME" agents
        ok "Attached $attached_count external skill(s) successfully!"
    fi
}

cmd_detach() {
    local target_vendor="${1:-}"
    local detached_count=0

    info "Detaching external skill symlinks..."

    if [[ ! -d "$SKILLS_ROOT" ]]; then
        warn "Skills root not found: $SKILLS_ROOT"
        return 0
    fi

    while IFS= read -r -d '' link; do
        local link_target
        link_target="$(readlink "$link")"
        if [[ "$link_target" == *"_vendor/"* ]]; then
            if [[ -z "$target_vendor" || "$link_target" == *"_vendor/$target_vendor/"* || "$link_target" == *"_vendor/$target_vendor" ]]; then
                rm -f "$link"
                ok "Detached: $(basename "$link")"
                detached_count=$((detached_count + 1))
            fi
        fi
    done < <(find "$SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type l -print0)

    if (( detached_count > 0 )); then
        info "Syncing Stow agents module..."
        bash "$SCRIPT_DIR/stow-sync.sh" "$DOTFILES_DIR" "$HOME" agents
        ok "Detached $detached_count external skill(s) successfully!"
    else
        info "No active external skill symlinks found to detach"
    fi
}

cmd_update() {
    local target_vendor="${1:-}"

    if [[ -n "$target_vendor" ]]; then
        info "Updating submodule for vendor: $target_vendor..."
        git -C "$DOTFILES_DIR" submodule update --remote --recursive "_vendor/$target_vendor"
    else
        info "Updating all vendor submodules under _vendor/..."
        git -C "$DOTFILES_DIR" submodule update --remote --recursive _vendor
    fi

    # Re-attach to reflect any newly added/removed skills upstream
    cmd_attach "$target_vendor"
}

cmd_list() {
    echo ""
    info "🌟 Bundled Skills (In-repo):"
    if [[ -d "$SKILLS_ROOT" ]]; then
        find "$SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type d ! -type l | sort | while read -r dir; do
            echo "  • $(basename "$dir")"
        done
    fi

    echo ""
    info "🔌 Active Attached External Skills:"
    local active_count=0
    if [[ -d "$SKILLS_ROOT" ]]; then
        while IFS= read -r -d '' link; do
            local target
            target="$(readlink "$link")"
            if [[ "$target" == *"_vendor"* ]]; then
                echo "  • $(basename "$link") → $target"
                active_count=$((active_count + 1))
            fi
        done < <(find "$SKILLS_ROOT" -mindepth 1 -maxdepth 1 -type l -print0 | sort -z)
    fi
    if (( active_count == 0 )); then
        echo "  (none active — run 'make skills-attach' to attach)"
    fi

    echo ""
    info "📦 Registered Vendors in _vendor/:"
    if [[ -d "$VENDOR_ROOT" ]]; then
        find "$VENDOR_ROOT" -mindepth 1 -maxdepth 1 -type d | sort | while read -r v; do
            local vname
            vname="$(basename "$v")"
            if [[ -f "$v/SKILL.md" ]] || [[ -n "$(find "$v" -maxdepth 3 -name "SKILL.md" -print -quit 2>/dev/null)" ]]; then
                echo "  ✓ $vname (initialized)"
            else
                echo "  ○ $vname (uninitialized / empty — will init on attach)"
            fi
        done
    else
        echo "  (none registered)"
    fi
    echo ""
}

main() {
    local cmd="${1:-list}"
    local vendor="${2:-}"

    case "$cmd" in
        attach) cmd_attach "$vendor" ;;
        detach) cmd_detach "$vendor" ;;
        update) cmd_update "$vendor" ;;
        list|ls) cmd_list ;;
        *)
            error "Unknown command: $cmd (choices: attach | detach | update | list)"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

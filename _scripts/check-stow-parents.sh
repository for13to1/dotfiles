#!/usr/bin/env bash

set -euo pipefail

if (( $# < 3 )); then
    echo "用法: $0 <dotfiles-dir> <target-dir> <module>..." >&2
    exit 2
fi

DOTFILES_DIR="$1"
TARGET_DIR="$2"
shift 2

check_tree() {
    local module="$1"
    local directory="$2"
    local entry relative target parent source_resolved target_resolved

    while IFS= read -r -d '' entry; do
        relative="${entry#"$module"/}"
        target="$TARGET_DIR/$relative"
        parent="$(dirname "$target")"

        if [[ -L "$parent" ]]; then
            echo "❌ $parent 是软链接，请手动处理后再运行 stow" >&2
            return 1
        fi

        if [[ -d "$entry" && ! -L "$entry" ]]; then
            if [[ -L "$target" ]]; then
                source_resolved="$(cd "$entry" 2>/dev/null && pwd -P)"
                target_resolved="$(cd "$target" 2>/dev/null && pwd -P || true)"
                if [[ "$source_resolved" != "$target_resolved" ]]; then
                    echo "❌ $target 是软链接，请手动处理后再运行 stow" >&2
                    return 1
                fi
            elif [[ -d "$target" ]]; then
                check_tree "$module" "$entry"
            fi
        fi
    done < <(find "$directory" -mindepth 1 -maxdepth 1 \
        ! -name ".stow-local-ignore" ! -name ".DS_Store" ! -name ".git" \
        \( -type f -o -type l -o -type d \) -print0)
}

cd "$DOTFILES_DIR"

for module in "$@"; do
    if [[ -d "$module" ]]; then
        check_tree "$module" "$module"
    fi
done

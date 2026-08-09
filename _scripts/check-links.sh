#!/usr/bin/env bash
#
# check-links.sh — Stow 链接检查工具
# 合并原 check-stow-parents.sh（挂载前检查）与 Makefile check 目标（挂载后校验）。
#
# 用法:
#   check-links.sh preflight <dotfiles-dir> <target-dir> <module>...
#       挂载前检查：确认目标父目录未被折叠为软链接，避免 stow 折叠到错误层级。
#   check-links.sh verify <dotfiles-dir> <target-dir> <module>...
#       挂载后校验：确认每个模块的软链接都正确指向 dotfiles 仓库。
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

CMD="${1:-}"
if [[ -z "$CMD" ]]; then
    echo "用法: $0 <preflight|verify> <dotfiles-dir> <target-dir> <module>..." >&2
    exit 2
fi
shift

if (( $# < 3 )); then
    echo "用法: $0 $CMD <dotfiles-dir> <target-dir> <module>..." >&2
    exit 2
fi

DOTFILES_DIR="$1"
TARGET_DIR="$2"
shift 2

# 统一规范化源目录，避免 macOS /tmp、/var 等 symlink 路径导致误判。
DOTFILES_DIR="$(cd -P -- "$DOTFILES_DIR" 2>/dev/null && pwd -P)" || {
    echo "无法访问 dotfiles 目录: $DOTFILES_DIR" >&2
    exit 1
}

# ── preflight：挂载前检查 ──────────────────────────────────────────
preflight_check_tree() {
    local module="$1"
    local directory="$2"
    local entry relative target parent

    while IFS= read -r -d '' entry; do
        relative="${entry#"$module"/}"
        target="$TARGET_DIR/$relative"
        parent="$(dirname "$target")"

        if [[ -L "$parent" ]]; then
            echo "❌ $parent 是软链接，请手动处理后再运行 stow" >&2
            return 1
        fi

        if [[ -L "$target" ]]; then
            if [[ "$(resolved_link_target "$target")" != "$(physical_path "$entry")" ]]; then
                echo "❌ $target 是软链接，请手动处理后再运行 stow" >&2
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
            echo "  ⚠️  模块目录不存在: $module" >&2
            return 1
        fi
        preflight_check_tree "$module" "$module"
    done
}

# ── verify：挂载后校验 ────────────────────────────────────────────
verify_entry() {
    local mod="$1"
    local entry="$2"
    local rel="${entry#"$mod"/}"
    [[ -z "$rel" ]] && rel="$(basename "$entry")"
    local target="$TARGET_DIR/$rel"
    local src
    src="$(physical_path "$DOTFILES_DIR/$entry")"

    if [[ -L "$target" ]]; then
        local resolved
        resolved="$(resolved_link_target "$target")"
        if [[ "$resolved" == "$src" ]]; then
            return 0
        fi
        echo "  ❌ $rel → 软链接指向错误" >&2
        return 1
    fi

    if [[ ! -e "$target" ]]; then
        echo "  ❌ $rel → 软链接缺失" >&2
        return 1
    fi

    if [[ -d "$entry" && -d "$target" ]]; then
        local sub
        while IFS= read -r -d '' sub; do
            verify_entry "$mod" "$sub" || return 1
        done < <(stow_find "$entry" -mindepth 1 -maxdepth 1)
        return 0
    fi

    echo "  ❌ $rel → 存在但不是正确软链接" >&2
    return 1
}

verify() {
    cd "$DOTFILES_DIR"
    local failed=0
    echo "正在检查软链接状态..."

    for mod in "$@"; do
        if [[ ! -d "$mod" ]]; then
            echo "  ⚠️  模块目录不存在: $mod" >&2
            failed=1
            continue
        fi

        local errors=0
        local entry
        while IFS= read -r -d '' entry; do
            verify_entry "$mod" "$entry" || errors=$((errors + 1))
        done < <(stow_find "$mod" -mindepth 1 -maxdepth 1)

        if (( errors == 0 )); then
            echo "  ✅ $mod"
        else
            failed=1
        fi
    done

    if (( failed == 0 )); then
        echo "全部检查通过！"
    else
        echo "存在异常，请运行 make sync 修复。" >&2
        exit 1
    fi
}

case "$CMD" in
    preflight) preflight "$@" ;;
    verify)    verify "$@" ;;
    *)
        echo "未知子命令: $CMD（可选: preflight | verify）" >&2
        exit 2
        ;;
esac

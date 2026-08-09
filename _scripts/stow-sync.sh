#!/usr/bin/env bash
#
# stow-sync.sh — 统一的 Stow 同步入口
# 用法: stow-sync.sh <dotfiles-dir> <target-dir> <module>...
# 执行 preflight、冲突备份、共享目录创建、stow -R 和挂载后校验。
#

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

if (( $# < 2 )); then
    echo "用法: $0 <dotfiles-dir> <target-dir> <module>..." >&2
    exit 2
fi

DOTFILES_DIR="$1"
TARGET_DIR="$2"
shift 2

DOTFILES_DIR="$(cd -P -- "$DOTFILES_DIR" 2>/dev/null && pwd -P)" || {
    echo "无法访问 dotfiles 目录: $DOTFILES_DIR" >&2
    exit 1
}
TARGET_DIR="$(cd -P -- "$TARGET_DIR" 2>/dev/null && pwd -P)" || {
    echo "无法访问目标目录: $TARGET_DIR" >&2
    exit 1
}

if (( $# == 0 )); then
    warn "没有需要挂载的模块，跳过 Stow"
    exit 0
fi

cd "$DOTFILES_DIR"
info "正在使用 Stow 同步模块: $* ..."

bash "$SCRIPT_DIR/check-links.sh" preflight "$DOTFILES_DIR" "$TARGET_DIR" "$@"

# 这些是系统共享目录，不能被备份；备份后 stow 会对整个目录进行折叠。
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
        warn "发现冲突文件/目录 $full_target （非软链接），备份为 $full_target.bak.$timestamp"
        mv "$full_target" "$full_target.bak.$timestamp"
    fi
}

backup_module_conflicts() {
    local mod="$1"
    local path

    [[ -d "$mod" ]] || return 0

    while IFS= read -r -d '' path; do
        backup_explicit_conflicts "$mod" "${path#"$mod"/}"
    done < <(stow_find "$mod" -mindepth 1 \( -type f -o -type l \))

    while IFS= read -r -d '' path; do
        backup_explicit_conflicts "$mod" "${path#"$mod"/}"
    done < <(stow_find "$mod" -mindepth 1 -type d)
}

for mod in "$@"; do
    backup_module_conflicts "$mod"
done

for shared in "${SHARED_PARENT_DIRS[@]}"; do
    mkdir -p "$TARGET_DIR/$shared"
done

stow_args=(stow)
for ignore in "${STOW_IGNORE_NAMES[@]}"; do
    stow_args+=( "--ignore=$ignore" )
done
stow_args+=( -t "$TARGET_DIR" -R "$@" )
"${stow_args[@]}"
bash "$SCRIPT_DIR/check-links.sh" verify "$DOTFILES_DIR" "$TARGET_DIR" "$@"

ok "Stow 同步完成"

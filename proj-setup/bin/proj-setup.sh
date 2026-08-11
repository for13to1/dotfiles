#!/usr/bin/env bash
#
# proj-setup — 快速初始化项目目录，复制预设配置模板
#
# 用法: proj-setup [--vcs=VCS] [--lang=LANG] [目录名]
#
# 参数:
#   --vcs=VCS    指定版本控制模板目录名（默认: git；可选: git, none）
#   --lang=LANG  指定语言模板目录名（如 cpp, python, rust），可选
#   [目录名]     目标目录，默认为当前目录
#
# 示例:
#   proj-setup                         # 当前目录，基础配置 + Git
#   proj-setup myproject               # 创建 myproject，基础配置 + Git
#   proj-setup --vcs=none              # 当前目录，仅基础配置
#   proj-setup --vcs=git --lang=cpp    # 当前目录，Git + C++ 模板
#   proj-setup myproject --lang=python # 创建 myproject，Git + Python 模板
#

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
DOTFILES_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "$DOTFILES_DIR/_scripts/common.sh"
TEMPLATES_DIR="${DOTFILES_DIR}/proj-setup/templates"
BASE_TEMPLATES_DIR="${TEMPLATES_DIR}/base"
VCS_TEMPLATES_DIR="${TEMPLATES_DIR}/vcs"
LANGUAGE_TEMPLATES_DIR="${TEMPLATES_DIR}/language"

# ── 列出模板目录下的可用子模板名（逗号分隔）──────────────
list_template_names() {
    local dir="$1"
    find "$dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
        | sort | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}

# ── 用法说明 ──────────────────────────────────────────────────────
usage() {
    cat <<EOF
用法: proj-setup [--vcs=VCS] [--lang=LANG] [目录名]

参数:
  --vcs=VCS    指定版本控制模板目录名（默认: git；可选: git, none）
  --lang=LANG  指定语言模板目录名（如 cpp, python, rust），可选
  [目录名]     目标目录，默认为当前目录

示例:
  proj-setup                         # 当前目录，基础配置 + Git
  proj-setup myproject               # 创建 myproject，基础配置 + Git
  proj-setup --vcs=none              # 当前目录，仅基础配置
  proj-setup --vcs=git --lang=cpp    # 当前目录，Git + C++ 模板
  proj-setup myproject --lang=python # 创建 myproject，Git + Python 模板
EOF
    exit 0
}

# ── 复制模板文件 ──────────────────────────────────────────────────
copy_templates() {
    local src_dir="$1"
    local dst_dir="$2"
    local copied_list="${3:-}"

    if [[ ! -d "$src_dir" ]]; then
        return 0
    fi

    # 检查目录是否为空
    local first
    first="$(find "$src_dir" -mindepth 1 -print -quit 2>/dev/null || true)"
    [[ -n "$first" ]] || return 0

    find "${src_dir}" -type f -print0 | while IFS= read -r -d '' src_file; do
        local rel_path
        rel_path="${src_file#"$src_dir"/}"
        local dst_file="${dst_dir}/${rel_path}"

        if [[ -e "$dst_file" ]]; then
            warn "跳过已存在: $rel_path"
        else
            mkdir -p "$(dirname "$dst_file")"
            cp "$src_file" "$dst_file"
            if [[ -n "$copied_list" ]]; then
                printf '%s\0' "$dst_file" >> "$copied_list"
            fi
            ok "已复制: $rel_path"
        fi
    done
}

project_name_from_dir() {
    local target_dir="$1"
    local project_name

    project_name=$(basename "$target_dir" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]_]+/-/g; s/[^a-z0-9.-]//g; s/^[.-]+//; s/[.-]+$//')
    [[ -n "$project_name" ]] || error "无法从目录名生成有效的项目名: $target_dir"
    printf '%s\n' "$project_name"
}

# 替换模板文件中的 __PROJECT_NAME__ 占位符（所有语言通用）
customize_project_name() {
    local file="$1"
    local project_name="$2"
    local escaped_project_name=""
    local tmp_file=""

    [[ -f "$file" ]] || return 0
    grep -q '__PROJECT_NAME__' "$file" || return 0

    escaped_project_name=$(printf '%s\n' "$project_name" | sed 's/[\/&]/\\&/g')
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/proj-setup.XXXXXX") || error "无法创建临时文件"
    if ! sed "s/__PROJECT_NAME__/${escaped_project_name}/g" "$file" > "$tmp_file"; then
        rm -f "$tmp_file"
        error "项目名替换失败: $file"
    fi
    if ! cat "$tmp_file" > "$file"; then
        rm -f "$tmp_file"
        error "写回模板文件失败: $file"
    fi
    rm -f "$tmp_file"
    ok "已设置项目名: ${project_name}"
}

# ── 主逻辑 ────────────────────────────────────────────────────────
main() {
    local vcs="git"
    local lang=""
    local target_dir=""
    local available_vcs=""
    local available_langs=""
    local project_name=""
    local copied_files=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vcs=*)
                vcs="${1#*=}"
                [[ -n "$vcs" ]] || error "参数 --vcs 需要值（如 --vcs=git 或 --vcs=none）"
                ;;
            --lang=*)
                lang="${1#*=}"
                [[ -n "$lang" ]] || error "参数 --lang 需要值（如 --lang=cpp）"
                ;;
            --help|-h)
                usage
                ;;
            -*)
                error "未知参数: $1"
                ;;
            *)
                if [[ -n "$target_dir" ]]; then
                    error "位置参数过多: $1"
                fi
                target_dir="$1"
                ;;
        esac
        shift
    done

    # 验证版本控制参数
    if [[ "$vcs" != "none" ]]; then
        if [[ ! -d "${VCS_TEMPLATES_DIR}/${vcs}" ]]; then
            available_vcs="$(list_template_names "$VCS_TEMPLATES_DIR")"
            if [[ -n "$available_vcs" ]]; then
                available_vcs="${available_vcs}, none"
            else
                available_vcs="none"
            fi
            error "不支持的版本控制: $vcs (可选: ${available_vcs})"
        fi
    fi

    # 验证语言参数
    if [[ -n "$lang" ]]; then
        if [[ ! -d "${LANGUAGE_TEMPLATES_DIR}/${lang}" ]]; then
            available_langs="$(list_template_names "$LANGUAGE_TEMPLATES_DIR")"
            [[ -n "$available_langs" ]] || available_langs="无"
            error "不支持的语言: $lang (可选: ${available_langs})"
        fi
    fi

    # 确定目标目录
    if [[ -z "$target_dir" ]]; then
        target_dir="$(pwd)"
    fi

    # 创建目标目录（如果不存在）
    if [[ ! -d "$target_dir" ]]; then
        info "创建目录: $target_dir"
        mkdir -p "$target_dir"
    fi

    # 转换为绝对路径
    target_dir="$(cd "$target_dir" && pwd)"
    project_name="$(project_name_from_dir "$target_dir")"
    copied_files="$(mktemp "${TMPDIR:-/tmp}/proj-setup-copied.XXXXXX")"
    trap '[[ -n "${copied_files:-}" ]] && rm -f "$copied_files"' EXIT

    info "初始化项目: $target_dir"
    info "版本控制: $vcs"
    [[ -n "$lang" ]] && info "语言模板: $lang"

    # 1. 复制基础模板
    echo ""
    info "复制基础配置..."
    copy_templates "${BASE_TEMPLATES_DIR}" "$target_dir" "$copied_files"

    # 2. 复制版本控制模板
    if [[ "$vcs" != "none" ]]; then
        echo ""
        info "复制 ${vcs} 配置..."
        copy_templates "${VCS_TEMPLATES_DIR}/${vcs}" "$target_dir" "$copied_files"
    fi

    # 3. 复制语言模板（如果指定）
    if [[ -n "$lang" ]]; then
        echo ""
        info "复制 ${lang} 模板..."
        copy_templates "${LANGUAGE_TEMPLATES_DIR}/${lang}" "$target_dir" "$copied_files"
    fi

    # 4. 替换模板中的项目名占位符（__PROJECT_NAME__，所有语言通用）
    while IFS= read -r -d '' file; do
        customize_project_name "$file" "$project_name"
    done < "$copied_files"

    # 5. 初始化版本控制（如果尚未初始化）
    if [[ "$vcs" == "git" ]]; then
        echo ""
        if [[ -d "${target_dir}/.git" ]]; then
            warn "Git 仓库已存在，跳过初始化"
        else
            info "初始化 Git 仓库..."
            (cd "$target_dir" && git init -q)
            ok "Git 仓库已初始化"
        fi
    fi

    echo ""
    ok "项目初始化完成！"
}

main "$@"

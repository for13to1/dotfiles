#!/usr/bin/env bash
#
# proj-init — 快速初始化项目目录，复制预设配置模板并初始化 git
#
# 用法: proj-init [--lang=LANG] [目录名]
#
# 参数:
#   --lang=LANG  指定语言模板目录名（如 cpp, python, rust），可选
#   [目录名]     目标目录，默认为当前目录
#
# 示例:
#   proj-init                    # 当前目录，仅 common 模板
#   proj-init myproject          # 创建 myproject 目录
#   proj-init --lang=cpp         # 当前目录，C++ 模板
#   proj-init myproject --lang=python  # 创建 myproject，Python 模板
#

set -euo pipefail

# ── 配置 ──────────────────────────────────────────────────────────
DOTFILES_DIR="${HOME}/dotfiles"
TEMPLATES_DIR="${DOTFILES_DIR}/proj-init/templates"

# ── 颜色输出 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── 用法说明 ──────────────────────────────────────────────────────
usage() {
    cat <<EOF
用法: proj-init [--lang=LANG] [目录名]

参数:
  --lang=LANG  指定语言模板目录名（如 cpp, python, rust），可选
  [目录名]     目标目录，默认为当前目录

示例:
  proj-init                    # 当前目录，仅 common 模板
  proj-init myproject          # 创建 myproject 目录
  proj-init --lang=cpp         # 当前目录，C++ 模板
  proj-init myproject --lang=python  # 创建 myproject，Python 模板
EOF
    exit 0
}

# ── 复制模板文件 ──────────────────────────────────────────────────
copy_templates() {
    local src_dir="$1"
    local dst_dir="$2"

    if [[ ! -d "$src_dir" ]]; then
        return 0
    fi

    # 检查目录是否有文件
    local has_files=false
    if [ -n "$(ls -A "$src_dir" 2>/dev/null)" ]; then
        has_files=true
    fi
    [[ "$has_files" == "false" ]] && return 0

    find "${src_dir}" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' src_file; do
        local filename
        filename=$(basename "$src_file")
        local dst_file="${dst_dir}/${filename}"

        if [[ -e "$dst_file" ]]; then
            warn "跳过已存在: $filename"
        else
            cp "$src_file" "$dst_file"
            ok "已复制: $filename"
        fi
    done
}

project_name_from_dir() {
    local target_dir="$1"
    local project_name

    project_name=$(basename "$target_dir" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]_]\+/-/g; s/[^a-z0-9.-]//g; s/^[.-]\+//; s/[.-]\+$//')
    [[ -n "$project_name" ]] || error "无法从目录名生成有效的项目名: $target_dir"
    printf '%s\n' "$project_name"
}

customize_python_template() {
    local target_dir="$1"
    local pyproject_file="${target_dir}/pyproject.toml"
    local project_name=""
    local tmp_file=""

    [[ -f "$pyproject_file" ]] || return 0

    project_name=$(project_name_from_dir "$target_dir")
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/proj-init-pyproject.XXXXXX")
    sed "s/__PROJECT_NAME__/${project_name}/g" "$pyproject_file" > "$tmp_file"
    mv "$tmp_file" "$pyproject_file"
    ok "已设置 Python 项目名: ${project_name}"
}

# ── 主逻辑 ────────────────────────────────────────────────────────
main() {
    local lang=""
    local target_dir=""
    local available_langs=""

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --lang=*)
                lang="${1#*=}"
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

    # 验证语言参数
    if [[ -n "$lang" ]]; then
        if [[ ! -d "${TEMPLATES_DIR}/${lang}" ]]; then
            available_langs=$(
                find "${TEMPLATES_DIR}" -mindepth 1 -maxdepth 1 -type d ! -name common -printf '%f\n' | sort | tr '\n' ',' | sed 's/,$//; s/,/, /g'
            )
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

    info "初始化项目: $target_dir"
    [[ -n "$lang" ]] && info "语言模板: $lang"

    # 1. 复制 common 模板
    echo ""
    info "复制通用模板..."
    copy_templates "${TEMPLATES_DIR}/common" "$target_dir"

    # 2. 复制语言模板（如果指定）
    if [[ -n "$lang" ]]; then
        echo ""
        info "复制 ${lang} 模板..."
        copy_templates "${TEMPLATES_DIR}/${lang}" "$target_dir"

        if [[ "$lang" == "python" ]]; then
            customize_python_template "$target_dir"
        fi
    fi

    # 3. 初始化 git（如果尚未初始化）
    echo ""
    if [[ -d "${target_dir}/.git" ]]; then
        warn "Git 仓库已存在，跳过初始化"
    else
        info "初始化 Git 仓库..."
        (cd "$target_dir" && git init -q)
        ok "Git 仓库已初始化"
    fi

    echo ""
    ok "项目初始化完成！"
}

main "$@"

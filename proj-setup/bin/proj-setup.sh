#!/usr/bin/env bash
#
# proj-setup — quickly initialize a project directory by copying preset templates
#
# Usage: proj-setup [--vcs=VCS] [--lang=LANG] [directory]
#
# Args:
#   --vcs=VCS    VCS template dir name (default: git; choices: git, none)
#   --lang=LANG  language template dir name (e.g. cpp, python, rust), optional
#   [directory]  target dir, defaults to the current directory
#
# Examples:
#   proj-setup                         # current dir, base config + Git
#   proj-setup myproject               # create myproject, base config + Git
#   proj-setup --vcs=none              # current dir, base config only
#   proj-setup --vcs=git --lang=cpp    # current dir, Git + C++ template
#   proj-setup myproject --lang=python # create myproject, Git + Python template
#

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────
# Resolve the real script location: it may be invoked through a symlink
# (e.g. ~/.local/bin/proj-setup), and the relative paths below depend on it.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"

# Minimal colored-output helpers.
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; exit 1; }

TEMPLATES_DIR="${SCRIPT_DIR}/../templates"
BASE_TEMPLATES_DIR="${TEMPLATES_DIR}/base"
VCS_TEMPLATES_DIR="${TEMPLATES_DIR}/vcs"
LANGUAGE_TEMPLATES_DIR="${TEMPLATES_DIR}/language"

# ── List available sub-template names under a template dir (comma-separated) ──
list_template_names() {
    local dir="$1"
    find "$dir" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
        | sort | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}

# ── Usage ────────────────────────────────────────────────────────
usage() {
    cat <<EOF
Usage: proj-setup [--vcs=VCS] [--lang=LANG] [directory]

Args:
  --vcs=VCS    VCS template dir name (default: git; choices: git, none)
  --lang=LANG  language template dir name (e.g. cpp, python, rust), optional
  [directory]  target dir, defaults to the current directory

Examples:
  proj-setup                         # current dir, base config + Git
  proj-setup myproject               # create myproject, base config + Git
  proj-setup --vcs=none              # current dir, base config only
  proj-setup --vcs=git --lang=cpp    # current dir, Git + C++ template
  proj-setup myproject --lang=python # create myproject, Git + Python template
EOF
    exit 0
}

# ── Copy template files ─────────────────────────────────────────
copy_templates() {
    local src_dir="$1"
    local dst_dir="$2"
    local copied_list="${3:-}"

    if [[ ! -d "$src_dir" ]]; then
        return 0
    fi

    # Check whether the directory is empty.
    local first
    first="$(find "$src_dir" -mindepth 1 -print -quit 2>/dev/null || true)"
    [[ -n "$first" ]] || return 0

    find "${src_dir}" -type f -print0 | while IFS= read -r -d '' src_file; do
        local rel_path
        rel_path="${src_file#"$src_dir"/}"
        local dst_file="${dst_dir}/${rel_path}"

        if [[ -e "$dst_file" ]]; then
            warn "Skipping existing: $rel_path"
        else
            mkdir -p "$(dirname "$dst_file")"
            cp "$src_file" "$dst_file"
            if [[ -n "$copied_list" ]]; then
                printf '%s\0' "$dst_file" >> "$copied_list"
            fi
            ok "Copied: $rel_path"
        fi
    done
}

project_name_from_dir() {
    local target_dir="$1"
    local project_name

    project_name=$(basename "$target_dir" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:space:]_]+/-/g; s/[^a-z0-9.-]//g; s/^[.-]+//; s/[.-]+$//')
    [[ -n "$project_name" ]] || error "Cannot derive a valid project name from the dir: $target_dir"
    printf '%s\n' "$project_name"
}

# Replace the __PROJECT_NAME__ placeholder in template files (all languages).
customize_project_name() {
    local file="$1"
    local project_name="$2"
    local escaped_project_name=""
    local tmp_file=""

    [[ -f "$file" ]] || return 0
    grep -q '__PROJECT_NAME__' "$file" || return 0

    escaped_project_name=$(printf '%s\n' "$project_name" | sed 's/[\/&]/\\&/g')
    tmp_file=$(mktemp "${TMPDIR:-/tmp}/proj-setup.XXXXXX") || error "Cannot create a temp file"
    if ! sed "s/__PROJECT_NAME__/${escaped_project_name}/g" "$file" > "$tmp_file"; then
        rm -f "$tmp_file"
        error "Project-name substitution failed: $file"
    fi
    if ! cat "$tmp_file" > "$file"; then
        rm -f "$tmp_file"
        error "Failed to write the template file back: $file"
    fi
    rm -f "$tmp_file"
    ok "Project name set: ${project_name}"
}

# ── Main ─────────────────────────────────────────────────────────
main() {
    local vcs="git"
    local lang=""
    local target_dir=""
    local available_vcs=""
    local available_langs=""
    local project_name=""
    local copied_files=""

    # Parse arguments.
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vcs=*)
                vcs="${1#*=}"
                [[ -n "$vcs" ]] || error "--vcs requires a value (e.g. --vcs=git or --vcs=none)"
                ;;
            --lang=*)
                lang="${1#*=}"
                [[ -n "$lang" ]] || error "--lang requires a value (e.g. --lang=cpp)"
                ;;
            --help|-h)
                usage
                ;;
            -*)
                error "Unknown argument: $1"
                ;;
            *)
                if [[ -n "$target_dir" ]]; then
                    error "Too many positional arguments: $1"
                fi
                target_dir="$1"
                ;;
        esac
        shift
    done

    # Validate the VCS argument.
    if [[ "$vcs" != "none" ]]; then
        if [[ ! -d "${VCS_TEMPLATES_DIR}/${vcs}" ]]; then
            available_vcs="$(list_template_names "$VCS_TEMPLATES_DIR")"
            if [[ -n "$available_vcs" ]]; then
                available_vcs="${available_vcs}, none"
            else
                available_vcs="none"
            fi
            error "Unsupported VCS: $vcs (choices: ${available_vcs})"
        fi
    fi

    # Validate the language argument.
    if [[ -n "$lang" ]]; then
        if [[ ! -d "${LANGUAGE_TEMPLATES_DIR}/${lang}" ]]; then
            available_langs="$(list_template_names "$LANGUAGE_TEMPLATES_DIR")"
            [[ -n "$available_langs" ]] || available_langs="none"
            error "Unsupported language: $lang (choices: ${available_langs})"
        fi
    fi

    # Determine the target directory.
    if [[ -z "$target_dir" ]]; then
        target_dir="$(pwd)"
    fi

    # Create the target directory if missing.
    if [[ ! -d "$target_dir" ]]; then
        info "Creating directory: $target_dir"
        mkdir -p "$target_dir"
    fi

    # Convert to an absolute path.
    target_dir="$(cd "$target_dir" && pwd)"
    project_name="$(project_name_from_dir "$target_dir")"
    copied_files="$(mktemp "${TMPDIR:-/tmp}/proj-setup-copied.XXXXXX")"
    trap '[[ -n "${copied_files:-}" ]] && rm -f "$copied_files"' EXIT

    info "Initializing project: $target_dir"
    info "Version control: $vcs"
    [[ -n "$lang" ]] && info "Language template: $lang"

    # 1. Copy base templates.
    echo ""
    info "Copying base config..."
    copy_templates "${BASE_TEMPLATES_DIR}" "$target_dir" "$copied_files"

    # 2. Copy VCS templates.
    if [[ "$vcs" != "none" ]]; then
        echo ""
        info "Copying ${vcs} config..."
        copy_templates "${VCS_TEMPLATES_DIR}/${vcs}" "$target_dir" "$copied_files"
    fi

    # 3. Copy language templates (if specified).
    if [[ -n "$lang" ]]; then
        echo ""
        info "Copying ${lang} template..."
        copy_templates "${LANGUAGE_TEMPLATES_DIR}/${lang}" "$target_dir" "$copied_files"
    fi

    # 4. Replace the project-name placeholder (__PROJECT_NAME__) in templates.
    while IFS= read -r -d '' file; do
        customize_project_name "$file" "$project_name"
    done < "$copied_files"

    # 5. Initialize version control (if not already done).
    if [[ "$vcs" == "git" ]]; then
        echo ""
        if [[ -d "${target_dir}/.git" ]]; then
            warn "Git repo already exists; skipping init"
        else
            info "Initializing the Git repo..."
            (cd "$target_dir" && git init -q)
            ok "Git repo initialized"
        fi
    fi

    echo ""
    ok "Project initialization complete!"
}

main "$@"

#!/usr/bin/env bash
# _scripts/common.sh — shared shell infrastructure sourced by other scripts

# Guard against being executed directly.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "common.sh is a shared library; source it instead" >&2
    exit 1
fi

# ── Resolve the repository root ────────────────────────────────────
# common.sh always lives at <repo-root>/_scripts/, so derive the root from it.
DOTFILES_DIR="${DOTFILES_DIR:-$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"

# dotfiles_dir [override]: resolve and print the repo root (-P canonicalized,
# cd happens in a subshell so the caller's cwd is untouched).
# No arg uses $DOTFILES_DIR; prints nothing and returns non-zero when inaccessible.
dotfiles_dir() {
    local base="${1:-$DOTFILES_DIR}"
    ( cd -P -- "$base" 2>/dev/null && pwd -P )
}

# ── Colored output ─────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

# msg <level> <text>: unified printer; level is info|ok|warn|error.
msg() {
    local level="$1"
    shift
    case "$level" in
        info)  echo -e "${BLUE}ℹ️  $*${NC}" ;;
        ok)    echo -e "${GREEN}✅ $*${NC}" ;;
        warn)  echo -e "${YELLOW}⚠️  $*${NC}" ;;
        error) echo -e "${RED}❌ $*${NC}" ;;
        *)     echo -e "$*" ;;
    esac
}

info()      { msg 'info'  "$*"; }
ok()        { msg 'ok'    "$*"; }
warn()      { msg 'warn'  "$*"; }
# error_msg only prints; error prints and then exits the script.
error_msg() { msg 'error' "$*"; }
error()     { error_msg "$*"; exit 1; }

# ── Distro detection ─────────────────────────────────────────────
# Returns 0 on Debian-like platforms.
is_debian_like() {
    [[ -r /etc/os-release ]] || return 1
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "${ID:-}" == "ubuntu" || "${ID:-}" == "debian" || "${ID_LIKE:-}" == *"debian"* ]]
}

# ── Installed check ───────────────────────────────────────────────
# A command counts as installed if it is on PATH or executable at any known path.
is_installed() {
    local cmd="$1"; shift
    command -v "$cmd" &>/dev/null && return 0
    local p
    for p in "$@"; do
        [[ -x "$p" ]] && return 0
    done
    return 1
}

# ── Stow paths and ignore rules ─────────────────────────────────
# These directories/files never participate in Stow checks, backup, or mounting.
STOW_IGNORE_NAMES=(
    "__pycache__"
    ".pytest_cache"
    ".ruff_cache"
    ".mypy_cache"
    ".venv"
    ".stow-local-ignore"
    ".DS_Store"
    ".git"
    ".gitignore"
    "history.json"
)

# GNU Stow '--ignore' matches the END of a package-relative path as a Perl regex
# (e.g. --ignore=.git also matches `.config/git`, whose tail is `/git`). Those directory
# names are therefore anchored here (^|/)\.git so a real `.git` dir is skipped without
# also dropping legitimate config paths that merely end in `git` (such as the
# `git` Stow package's own `.config/git/ignore`). STOW_IGNORE_NAMES above stays exact for
# `find -name` (glob) in stow_find(); this list carries the regex forms for stow.
# shellcheck disable=SC2034  # consumed by _scripts/stow-sync.sh (sourced)
STOW_IGNORE_REGEXES=(
    "__pycache__"
    ".pytest_cache"
    ".ruff_cache"
    ".mypy_cache"
    ".venv"
    ".stow-local-ignore"
    ".DS_Store"
    '(^|/)\.git'
    ".gitignore"
    "history.json"
)

# find wrapper whose final command is:
#   find ROOT [-mindepth N -maxdepth M] -name IGN -prune -o … -o '(' user-preds ')' -print0
# Relies on -a binding tighter than -o: when an ignore matches, -prune is true and
# short-circuits, so later branches are skipped. Therefore user predicates MUST live in
# the trailing fallback branch of the -o chain, otherwise -prune and -type filters
# cannot coexist.
# -mindepth/-maxdepth are global options (they apply to every test) and must follow ROOT
# before any other test; mixing them into predicates triggers GNU find's
# "global option … after the argument …" warning.
stow_find() {
    local root="$1"
    shift
    local -a args=(find "$root")
    local -a preds=()
    local arg prev=""
    for arg in "$@"; do
        if [[ "$arg" == -mindepth || "$arg" == -maxdepth ]]; then
            prev="$arg"
        elif [[ -n "$prev" ]]; then
            args+=( "$prev" "$arg" )
            prev=""
        else
            preds+=( "$arg" )
        fi
    done
    [[ -z "$prev" ]] || preds+=( "$prev" )
    local name
    for name in "${STOW_IGNORE_NAMES[@]}"; do
        args+=( -name "$name" -prune -o )
    done
    if (( ${#preds[@]} )); then
        args+=( '(' "${preds[@]}" ')' -print0 )
    else
        args+=( -print0 )
    fi
    "${args[@]}"
}

physical_path() {
    local path="$1"
    printf '%s' "$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path")"
}

resolved_link_target() {
    local target="$1" link
    link="$(readlink "$target")"
    [[ "$link" == /* ]] || link="$(dirname "$target")/$link"
    physical_path "$link"
}

# ── Non-interactive input ──────────────────────────────────────────
# When DOTFILES_NON_INTERACTIVE=1, return the default without reading stdin.
ask_value() {
    local prompt="$1" default="$2" reply
    if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
        printf '%s\n' "$default"
        return 0
    fi
    read -rp "$prompt" reply || true
    printf '%s\n' "${reply:-$default}"
}

# default: 1 = yes (Enter/non-interactive returns 0), 0 = no (returns 1)
confirm() {
    local prompt="$1" default="$2" reply
    local default_ret=$((1 - default))
    if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
        return "$default_ret"
    fi
    read -rp "$prompt" reply || return "$default_ret"
    [[ -z "$reply" ]] && return "$default_ret"
    [[ "$reply" =~ ^[Yy](es)?$ ]]
}

# ── .group merge & dedupe ───────────────────────────────────────
# .group reader: skip comment lines starting with # and blank lines
# (apt/pacman are bare package names; brew lines are brew/cask lines).
group_list_lines() {
    grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -v '^[[:space:]]*$' || true
}

# Order-preserving dedupe (stdin → stdout): dedupe whole lines, keep first occurrence.
dedupe_lines() {
    awk '!seen[$0]++'
}

# Brewfile dedupe (stdin → stdout): dedupe by "brew/cask + package name", keeping
# the first full line (including restart_service etc.); non-brew/cask lines pass through.
# Uses only basic awk features, compatible with macOS's bundled BSD awk.
dedupe_brewfile() {
    awk '
        /^[[:space:]]*(brew|cask)[[:space:]]+"[^"]+"/ {
            name = $2
            sub(/,.*/, "", name)
            key = $1 " " name
            if (seen[key]++) next
        }
        { print }
    '
}

# ── Optional-group hint ──────────────────────────────────────────
# Lists all optional groups (everything except default.group) for a platform.
hint_optional_groups() {
    local platform="$1" dotfiles_dir="${2:-$DOTFILES_DIR}"
    local groups=() _f _t
    for _f in "$dotfiles_dir/_install/$platform"/*.group; do
        [[ -f "$_f" ]] || continue
        _t="$(basename "$_f")"
        [[ "$_t" == "default.group" ]] && continue
        groups+=("${_t%.group}")
    done
    if (( ${#groups[@]} > 0 )); then
        info "💡 Optional groups: bash _install/install --$platform ${groups[*]}"
    fi
}

# Usage: install_with_prompt <check_cmd> <prompt> <install_fn> <success_msg> [known_paths...]
# Skips when already installed. Declining is a successful skip; accepting an
# installer that then fails returns non-zero.
install_with_prompt() {
    local check_cmd="$1" prompt="$2" install_fn="$3" success_msg="$4"
    shift 4

    is_installed "$check_cmd" "$@" && return 0

    warn "$prompt"
    confirm "Install now? [y/N]: " 0 || return 0

    if ! "$install_fn"; then
        warn "Installation incomplete; retry manually later"
        return 1
    fi

    ok "$success_msg"
}

# ── Ecosystem installers ──────────────────────────────────────────
# Platform-independent tool layer: npm (Node CLIs: pi/codex/opencode/codegraph/
# biome/stylua/wrangler) and uv (Python CLIs: ruff/yt-dlp). No system package
# manager provides them, so they are identical on every platform and run
# once here as bootstrap step 3.
# Each script is self-contained: idempotent via is_installed, and it skips
# cleanly when a prerequisite (fnm/uv) is missing.
# The curl channel (runtimes fnm/rustup/uv via official installers) is NOT
# part of this layer: brew/pacman provide them via default groups, only apt
# lacks them, so pkg-linux runs that single script directly.
# DOTFILES_SKIP_ECOSYSTEM_TOOLS=1 skips everything (tests: no network).
install_ecosystem_tools() {
    if [[ -n "${DOTFILES_SKIP_ECOSYSTEM_TOOLS:-}" ]]; then
        return 0
    fi

    local rc=0
    local installer
    for installer in install-by-npm.sh install-by-uv.sh; do
        if [[ -f "$DOTFILES_DIR/_install/$installer" ]] \
           && ! bash "$DOTFILES_DIR/_install/$installer"; then
            warn "$installer failed; run it manually to retry"
            rc=1
        fi
    done
    return "$rc"
}

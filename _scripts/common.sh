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
# With CLI_MACHINE_OUTPUT=1, messages go to stderr (stdout stays data-only).
msg() {
    local level="$1" fd=1
    shift
    [[ -n "${CLI_MACHINE_OUTPUT:-}" ]] && fd=2
    case "$level" in
        info)  echo -e "${BLUE}ℹ️  $*${NC}" >&$fd ;;
        ok)    echo -e "${GREEN}✅ $*${NC}" >&$fd ;;
        warn)  echo -e "${YELLOW}⚠️  $*${NC}" >&$fd ;;
        error) echo -e "${RED}❌ $*${NC}" >&$fd ;;
        *)     echo -e "$*" >&$fd ;;
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

# ── Stale-file cleanup ────────────────────────────────────────────
# A dangling symlink or non-executable placeholder at a CLI's install path
# makes is_installed report it as missing while the path still BLOCKS a fresh
# install (npm errors EEXIST). Clear such stale markers first; only
# non-executable non-directories are removed, so real binaries stay safe.
clean_stale_installs() {
    local p
    for p in "$@"; do
        [[ (-e "$p" || -L "$p") && ! -d "$p" && ! -x "$p" ]] || continue
        rm -f -- "$p"
        warn "removed stale install entry: $p"
    done
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

# is_pre_approved <bin>
# Returns 0 when <bin> is pre-approved via DOTFILES_ACCEPT_TOOLS
# (space-separated bin names). Shared by install/update/uninstall so the
# authorization rule lives in exactly one place.
is_pre_approved() {
    local bin="$1"
    case " ${DOTFILES_ACCEPT_TOOLS:-${DOTFILES_ACCEPT_INSTALLS:-}} " in
        *" $bin "*) return 0 ;;
    esac
    return 1
}

# approve_install <bin_name> <confirm_prompt>
# Returns 0 when an install is approved: either the bin is pre-approved via
# DOTFILES_ACCEPT_TOOLS (space-separated bin names) or the user confirms.
# Non-interactive mode falls through to confirm's default.
approve_install() {
    local bin_name="$1" prompt="$2"
    is_pre_approved "$bin_name" && return 0
    confirm "$prompt" 0
}

# ── CLI registry ─────────────────────────────────────────────────
# One declarative row per managed CLI: channel + bin + pkg + flag + policy.
# Declarations live in _scripts/cli-registry.sh; here are the table, its
# validation, and the lifecycle frames (install/status/update/uninstall).
#
# Scope: "one package source → one bin → $CLI_BIN_DIR". Runtimes (curl) and
# multi-bin crates (cargo) stay outside.
CLI_BIN_DIR="$HOME/.local/bin"

ECO_CLI_CHANNELS=()
ECO_CLI_BINS=()
ECO_CLI_PKGS=()
ECO_CLI_FLAGS=()
ECO_CLI_POLICIES=()

# eco_cli <channel> <bin> <pkg> <flag|""> --always|--prompt
#   channel — owning channel (npm|uv|go); each channel filters to its own rows
#   bin     — detection/prompt/DOTFILES_ACCEPT_TOOLS key, never the pkg name
#   pkg     — install target (npm / pip / go module path)
#   flag    — channel-specific flag passed before pkg ("" if none), no spaces
#   policy  — always: install when missing; prompt: confirm first
# Within a channel, --always rows must precede --prompt rows.
eco_cli() {
    (($# == 5)) || { warn "eco_cli: expected <channel> <bin> <pkg> <flag> --always|--prompt"; return 1; }
    local channel="$1" bin="$2" pkg="$3" flag="$4" policy="$5"
    [[ -n "$channel" && -n "$bin" && -n "$pkg" ]] \
        || { warn "eco_cli: channel, bin and pkg must be non-empty"; return 1; }
    case "$channel" in
        npm|uv|go) ;;
        *) warn "eco_cli $bin: channel must be npm, uv or go"; return 1 ;;
    esac
    case "$policy" in
        --always|--prompt) ;;
        *) warn "eco_cli $bin: policy must be --always or --prompt"; return 1 ;;
    esac
    [[ "$flag" != *" "* ]] || { warn "eco_cli $bin: flag must not contain spaces"; return 1; }
    [[ "$bin" != *" "* && "$pkg" != *" "* ]] \
        || { warn "eco_cli $bin: bin and pkg must not contain spaces"; return 1; }
    case " ${ECO_CLI_BINS[*]:-} " in
        *" $bin "*) warn "eco_cli: duplicate bin '$bin'"; return 1 ;;
    esac
    case " ${ECO_CLI_PKGS[*]:-} " in
        *" $pkg "*) warn "eco_cli: duplicate pkg '$pkg'"; return 1 ;;
    esac
    ECO_CLI_CHANNELS+=("$channel")
    ECO_CLI_BINS+=("$bin")
    ECO_CLI_PKGS+=("$pkg")
    ECO_CLI_FLAGS+=("$flag")
    ECO_CLI_POLICIES+=("${policy#--}")
}

validate_cli_registry() {
    ((${#ECO_CLI_BINS[@]})) || { warn "CLI registry is empty"; return 1; }
    local n=${#ECO_CLI_BINS[@]}
    (( ${#ECO_CLI_CHANNELS[@]} == n && ${#ECO_CLI_PKGS[@]} == n \
       && ${#ECO_CLI_FLAGS[@]} == n && ${#ECO_CLI_POLICIES[@]} == n )) \
        || { warn "CLI registry arrays are misaligned"; return 1; }
    local i j bin
    for i in "${!ECO_CLI_BINS[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        [[ "${ECO_CLI_FLAGS[i]}" != *" "* ]] \
            || { warn "registry entry '$bin': flag must not contain spaces"; return 1; }
        case "${ECO_CLI_POLICIES[i]}" in
            prompt) ;;
            always)
                # --always must precede --prompt within the same channel.
                for (( j = 0; j < i; j++ )); do
                    if [[ "${ECO_CLI_CHANNELS[j]}" == "${ECO_CLI_CHANNELS[i]}" \
                          && "${ECO_CLI_POLICIES[j]}" == "prompt" ]]; then
                        warn "registry entry '$bin': --always must precede all --prompt entries in its channel"
                        return 1
                    fi
                done
                ;;
            *) warn "registry entry '$bin' has invalid policy '${ECO_CLI_POLICIES[i]}'"; return 1 ;;
        esac
    done
}

# cli_registry_filter_channel <channel> — drops rows whose channel is not <channel>.
cli_registry_filter_channel() {
    local want="$1" i
    local -a c=() b=() p=() f=() pl=()
    for i in "${!ECO_CLI_BINS[@]}"; do
        [[ "${ECO_CLI_CHANNELS[i]}" == "$want" ]] || continue
        c+=("${ECO_CLI_CHANNELS[i]}")
        b+=("${ECO_CLI_BINS[i]}")
        p+=("${ECO_CLI_PKGS[i]}")
        f+=("${ECO_CLI_FLAGS[i]}")
        pl+=("${ECO_CLI_POLICIES[i]}")
    done
    ECO_CLI_CHANNELS=("${c[@]}")
    ECO_CLI_BINS=("${b[@]}")
    ECO_CLI_PKGS=("${p[@]}")
    ECO_CLI_FLAGS=("${f[@]}")
    ECO_CLI_POLICIES=("${pl[@]}")
}

# channel_detect <channel> — install detection mode for a channel.
# npm keys only on the canonical prefix; uv/go also accept PATH installs.
channel_detect() {
    case "$1" in
        npm) printf 'canonical' ;;
        uv|go) printf 'path' ;;
    esac
}

# cli_registry_candidates
# Fills CLI_REGISTRY_IDX with indices of rows installed in $CLI_BIN_DIR. This
# prefix is the mutation scope: install may honor foreign PATH installs via
# detect=path, but update/uninstall never touch files outside it.
cli_registry_candidates() {
    local i bin
    CLI_REGISTRY_IDX=()
    for i in "${!ECO_CLI_BINS[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        [[ -x "$CLI_BIN_DIR/$bin" ]] || continue
        CLI_REGISTRY_IDX+=("$i")
    done
}

# cli_registry_scope_named <channel> <verb> [bin…]
# Narrows CLI_REGISTRY_IDX to the named bins (no-op when [bin…] is empty).
# Returns 1 with a nothing-to-do message when none is an installed candidate
# (typo or foreign install), so the caller skips the query.
cli_registry_scope_named() {
    local channel="$1" verb="$2"
    shift 2
    (( $# > 0 )) || return 0
    local -a keep_idx=()
    local i b
    # Inner break dedups repeated bin args.
    for i in "${CLI_REGISTRY_IDX[@]}"; do
        for b in "$@"; do
            if [[ "$b" == "${ECO_CLI_BINS[i]}" ]]; then
                keep_idx+=("$i")
                break
            fi
        done
    done
    if (( ${#keep_idx[@]} == 0 )); then
        info "no installed $channel CLIs among the named bins; nothing to $verb"
        return 1
    fi
    CLI_REGISTRY_IDX=("${keep_idx[@]}")
}

# install_cli_registry <install_fn> [channel] [detect] [bin…]
# Installs missing rows via <install_fn> <bin> <pkg> <flag>. [bin…] narrows to
# named rows. detect: "canonical" keys only on $CLI_BIN_DIR/<bin>; "path" also
# respects an existing install anywhere on PATH.
install_cli_registry() {
    local installer="$1" channel="${2:-$1}" detect="${3:-canonical}"
    local -a named=("${@:4}")
    case "$detect" in
        canonical|path) ;;
        *) warn "install_cli_registry: detect must be 'canonical' or 'path', got '$detect'"; return 1 ;;
    esac
    local i b bin pkg flag path want
    for i in "${!ECO_CLI_BINS[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        # Install only the requested bins.
        if (( ${#named[@]} > 0 )); then
            want=0
            for b in "${named[@]}"; do
                if [[ "$b" == "$bin" ]]; then
                    want=1
                    break
                fi
            done
            (( want )) || continue
        fi
        pkg="${ECO_CLI_PKGS[i]}"
        flag="${ECO_CLI_FLAGS[i]}"
        path="$CLI_BIN_DIR/$bin"

        if [[ "$detect" == "path" ]]; then
            # is_installed already falls through to -x $path.
            is_installed "$bin" "$path" && continue
        else
            [[ -x "$path" ]] && continue
        fi

        clean_stale_installs "$path"

        case "${ECO_CLI_POLICIES[i]}" in
            always)
                info "$bin not found; installing it via $channel..."
                if ! "$installer" "$bin" "$pkg" "$flag"; then
                    warn "Installation incomplete; retry manually later"
                    return 1
                fi
                ok "$bin installed"
                ;;
            prompt)
                warn "$bin not found; install it via $channel?"
                approve_install "$bin" "Install now? [y/N]: " || continue
                if ! "$installer" "$bin" "$pkg" "$flag"; then
                    warn "Installation incomplete; retry manually later"
                    return 1
                fi
                ok "$bin installed"
                ;;
        esac
    done
}

# update_cli_registry <outdated_fn> <update_fn> <channel> [bin…]
# Upgrades installed-and-outdated rows. [bin…] narrows the candidates; a named
# bin with no installed candidate short-circuits before the query. Authorization
# mirrors install (DOTFILES_ACCEPT_TOOLS pre-approves, the rest share one batch
# confirm). A failed query fails the run; a failed row warns and continues.
update_cli_registry() {
    local outdated_fn="$1" updater="$2" channel="$3"
    shift 3
    local -a to_update_idx=()
    local j pkg cur latest line

    cli_registry_candidates

    if (( ${#CLI_REGISTRY_IDX[@]} == 0 )); then
        info "no installed $channel CLIs from the registry; nothing to update"
        return 0
    fi

    # Scope before querying so a foreign or mistyped name skips the round-trip.
    cli_registry_scope_named "$channel" update "$@" || return 0

    query_outdated "$outdated_fn" "$channel" || return 1

    if (( ${#OUTDATED_LINES[@]} > 0 )); then
        for line in "${OUTDATED_LINES[@]}"; do
            read -r pkg cur latest <<<"$line"
            for j in "${CLI_REGISTRY_IDX[@]}"; do
                [[ "${ECO_CLI_PKGS[j]}" == "$pkg" ]] || continue
                to_update_idx+=("$j")
                info "update available: ${ECO_CLI_BINS[j]} ($pkg) $cur → $latest"
                break
            done
        done
    fi

    if (( ${#to_update_idx[@]} == 0 )); then
        # Named scope: don't claim all installed are up to date.
        if (( $# > 0 )); then
            ok "all named $channel CLIs are up to date"
        else
            ok "all installed $channel CLIs are up to date"
        fi
        return 0
    fi

    execute_updates "$updater" "$channel" "${to_update_idx[@]}"
}

# execute_updates <update_fn> <channel> <idx…>
# Authorization + execution tail shared by the public and known-outdated paths.
execute_updates() {
    local updater="$1" channel="$2"
    shift 2
    local -a final_idx=() pending_idx=()
    local j pkg flag declined=0 failed=0

    for j in "$@"; do
        if is_pre_approved "${ECO_CLI_BINS[j]}"; then
            final_idx+=("$j")
        else
            pending_idx+=("$j")
        fi
    done
    if (( ${#pending_idx[@]} > 0 )); then
        if confirm "Update ${#pending_idx[@]} via $channel? [y/N]: " 0; then
            for j in "${pending_idx[@]}"; do
                final_idx+=("$j")
            done
        else
            declined=1
        fi
    fi

    if (( ${#final_idx[@]} == 0 )); then
        warn "no $channel CLIs approved for update; skipping"
        return 0
    fi
    if (( declined )); then
        info "skipped ${#pending_idx[@]} unapproved $channel CLIs"
    fi

    for j in "${final_idx[@]}"; do
        pkg="${ECO_CLI_PKGS[j]}"
        flag="${ECO_CLI_FLAGS[j]}"
        info "updating ${ECO_CLI_BINS[j]} ($pkg) via $channel..."
        if ! "$updater" "${ECO_CLI_BINS[j]}" "$pkg" "$flag"; then
            warn "${ECO_CLI_BINS[j]} update failed; retry manually later"
            failed=1
            continue
        fi
        ok "${ECO_CLI_BINS[j]} updated"
    done
    return "$failed"
}

# update_known_cli_registry <update_fn> <channel> [bin…]
# Internal path for the unified entrypoint: the caller has already collected
# and authorized the outdated set, so the query is skipped and the named
# installed rows are updated directly.
update_known_cli_registry() {
    local updater="$1" channel="$2"
    shift 2

    cli_registry_candidates
    if (( ${#CLI_REGISTRY_IDX[@]} == 0 )); then
        info "no installed $channel CLIs from the registry; nothing to update"
        return 0
    fi
    cli_registry_scope_named "$channel" update "$@" || return 0

    execute_updates "$updater" "$channel" "${CLI_REGISTRY_IDX[@]}"
}

# uninstall_cli_registry <uninstall_fn> <channel> [bin…]
# Removes installed rows; candidates, authorization and scope match update.
# --always rows have no special case: uninstalling one just means the next
# install run reinstalls it. A failed row warns and continues.
uninstall_cli_registry() {
    local uninstall_fn="$1" channel="$2"
    shift 2
    local -a final_idx=() pending_idx=()
    local j pkg flag declined=0 failed=0

    cli_registry_candidates

    if (( ${#CLI_REGISTRY_IDX[@]} == 0 )); then
        info "no installed $channel CLIs from the registry; nothing to uninstall"
        return 0
    fi

    cli_registry_scope_named "$channel" uninstall "$@" || return 0

    for j in "${CLI_REGISTRY_IDX[@]}"; do
        if is_pre_approved "${ECO_CLI_BINS[j]}"; then
            final_idx+=("$j")
        else
            pending_idx+=("$j")
        fi
    done
    if (( ${#pending_idx[@]} > 0 )); then
        if confirm "Uninstall ${#pending_idx[@]} via $channel? [y/N]: " 0; then
            for j in "${pending_idx[@]}"; do
                final_idx+=("$j")
            done
        else
            declined=1
        fi
    fi

    if (( ${#final_idx[@]} == 0 )); then
        warn "no $channel CLIs approved for uninstall; skipping"
        return 0
    fi
    if (( declined )); then
        info "skipped ${#pending_idx[@]} unapproved $channel CLIs"
    fi

    for j in "${final_idx[@]}"; do
        pkg="${ECO_CLI_PKGS[j]}"
        flag="${ECO_CLI_FLAGS[j]}"
        info "uninstalling ${ECO_CLI_BINS[j]} ($pkg) via $channel..."
        if ! "$uninstall_fn" "${ECO_CLI_BINS[j]}" "$pkg" "$flag"; then
            warn "${ECO_CLI_BINS[j]} uninstall failed; retry manually later"
            failed=1
            continue
        fi
        ok "${ECO_CLI_BINS[j]} uninstalled"
    done
    return "$failed"
}

# query_outdated <outdated_fn> <channel>
# Runs the channel's one batch query into global OUTDATED_LINES
# ("pkg current latest" rows). A failed query warns (stderr) and returns 1.
query_outdated() {
    local outdated_fn="$1" channel="$2" raw line rc=0
    OUTDATED_LINES=()
    raw="$("$outdated_fn")" || rc=$?
    if (( rc != 0 )); then
        warn "outdated query via $channel failed" >&2
        return 1
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] && OUTDATED_LINES+=("$line")
    done <<<"$raw"
    return 0
}

# status_cli_registry <outdated_fn> <channel> <detect> [bin…]
# Read-only: prints every registered row's state (missing / on PATH / up to
# date / update available) and a summary. Never mutates or prompts.
status_cli_registry() {
    local outdated_fn="$1" channel="$2" detect="$3"
    shift 3
    local -a show_idx=()
    local i b bin pkg want
    for i in "${!ECO_CLI_BINS[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        if (( $# > 0 )); then
            want=0
            for b in "$@"; do
                if [[ "$b" == "$bin" ]]; then
                    want=1
                    break
                fi
            done
            (( want )) || continue
        fi
        show_idx+=("$i")
    done
    if (( ${#show_idx[@]} == 0 )); then
        info "no $channel CLIs among the named bins; nothing to show"
        return 0
    fi

    # Query only if at least one candidate is installed.
    local need_query=0
    OUTDATED_LINES=()
    for i in "${show_idx[@]}"; do
        if [[ -x "$CLI_BIN_DIR/${ECO_CLI_BINS[i]}" ]]; then
            need_query=1
            break
        fi
    done
    if (( need_query )); then
        query_outdated "$outdated_fn" "$channel" || return 1
    fi

    local installed=0 outdated=0 missing=0 foreign=0
    local cur latest line _p _c _l
    for i in "${show_idx[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        pkg="${ECO_CLI_PKGS[i]}"
        if [[ -x "$CLI_BIN_DIR/$bin" ]]; then
            installed=$(( installed + 1 ))
            cur=""; latest=""
            if (( ${#OUTDATED_LINES[@]} > 0 )); then
                for line in "${OUTDATED_LINES[@]}"; do
                    read -r _p _c _l <<<"$line"
                    if [[ "$_p" == "$pkg" ]]; then
                        cur="$_c"; latest="$_l"
                        break
                    fi
                done
            fi
            if [[ -n "$latest" ]]; then
                outdated=$(( outdated + 1 ))
                info "update available: $bin ($pkg) $cur → $latest"
            else
                ok "$bin ($pkg) up to date"
            fi
        elif [[ "$detect" == "path" ]] && is_installed "$bin"; then
            foreign=$(( foreign + 1 ))
            warn "$bin ($pkg) present on PATH — not managed here"
        else
            missing=$(( missing + 1 ))
            info "$bin ($pkg) missing"
        fi
    done

    info "summary: $installed installed, $outdated outdated, $missing missing, $foreign on PATH"
}

# outdated_cli_registry <outdated_fn> <channel> [bin…]
# Read-only, machine-readable listing: "bin pkg cur latest" per outdated row,
# for the unified entrypoint. No prompt, no mutation.
outdated_cli_registry() {
    local outdated_fn="$1" channel="$2"
    shift 2
    local i pkg cur latest line _p _c _l

    cli_registry_candidates
    if (( ${#CLI_REGISTRY_IDX[@]} == 0 )); then
        return 0
    fi
    # Machine output: silence the nothing-to-do message — stdout is data-only
    # even when the caller forgot CLI_MACHINE_OUTPUT.
    cli_registry_scope_named "$channel" outdated "$@" >/dev/null 2>&1 || return 0

    query_outdated "$outdated_fn" "$channel" || return 1

    for i in "${CLI_REGISTRY_IDX[@]}"; do
        pkg="${ECO_CLI_PKGS[i]}"
        cur=""; latest=""
        if (( ${#OUTDATED_LINES[@]} > 0 )); then
            for line in "${OUTDATED_LINES[@]}"; do
                read -r _p _c _l <<<"$line"
                if [[ "$_p" == "$pkg" ]]; then
                    cur="$_c"; latest="$_l"
                    break
                fi
            done
        fi
        [[ -n "$latest" ]] || continue
        printf '%s %s %s %s\n' "${ECO_CLI_BINS[i]}" "$pkg" "$cur" "$latest"
    done
}

# run_cli_channel <ensure_fn> <install_fn> <outdated_fn> <update_fn> <uninstall_fn> <channel> <detect> [args…]
# Validates the registry, ensures the runtime, then dispatches:
#   (no args)          install missing rows
#   --install [bin…]   install missing, narrowed
#   --status [bin…]    list every row + state
#   --update [bin…]    upgrade installed rows
#   --uninstall [bin…] remove installed rows
#   -h|--help          usage
# detect applies to install only; mutations act on the canonical prefix.
run_cli_channel() {
    local ensure="$1" installer="$2" outdated="$3" updater="$4" uninstaller="$5"
    local channel="$6" detect="$7"
    local arg verb="${8:-}"

    # Reject unknown verbs and option-like bins before any runtime work.
    case "$verb" in
        ""|-h|--help) ;;
        --install|--status|--outdated|--update|--update-known|--uninstall)
            for arg in "${@:9}"; do
                [[ "$arg" != -* ]] || { warn "unknown option '$arg' for $verb"; return 1; }
            done
            ;;
        *)
            warn "unknown option '$verb' (supported: --install, --status, --outdated, --update, --uninstall, -h|--help)"
            return 1
            ;;
    esac

    if [[ "$verb" == "-h" || "$verb" == "--help" ]]; then
        echo "usage: $0 [--status [bin…] | --update [bin…] | --uninstall [bin…] | --install [bin…] | -h|--help]"
        echo "       with no arguments, missing CLIs are installed"
        return 0
    fi

    # --outdated is the machine verb: force messages to stderr so stdout
    # stays parseable even when the caller forgot CLI_MACHINE_OUTPUT.
    [[ "$verb" == "--outdated" ]] && CLI_MACHINE_OUTPUT=1

    validate_cli_registry
    if ! "$ensure"; then
        return 0
    fi
    shift 7

    case "${1:-}" in
        "")
            install_cli_registry "$installer" "$channel" "$detect"
            ;;
        --install)
            shift
            install_cli_registry "$installer" "$channel" "$detect" "$@"
            ;;
        --status)
            shift
            status_cli_registry "$outdated" "$channel" "$detect" "$@"
            ;;
        --outdated)
            shift
            outdated_cli_registry "$outdated" "$channel" "$@"
            ;;
        --update)
            shift
            update_cli_registry "$outdated" "$updater" "$channel" "$@"
            ;;
        --update-known)
            shift
            update_known_cli_registry "$updater" "$channel" "$@"
            ;;
        --uninstall)
            shift
            uninstall_cli_registry "$uninstaller" "$channel" "$@"
            ;;
    esac
}

# ── Ecosystem installers ──────────────────────────────────────────
# Platform-independent tool layer (bootstrap step 3): npm/uv/go channels install
# into ~/.local and manage the full lifecycle. Each script is idempotent and
# skips cleanly when its runtime is missing.
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
    for installer in install-by-npm.sh install-by-uv.sh install-by-go.sh; do
        if [[ -f "$DOTFILES_DIR/_install/$installer" ]] \
           && ! bash "$DOTFILES_DIR/_install/$installer"; then
            warn "$installer failed; run it manually to retry"
            rc=1
        fi
    done
    return "$rc"
}

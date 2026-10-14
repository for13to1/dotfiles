#!/usr/bin/env bash
# _install/eco.sh — unified lifecycle entrypoint for ecosystem CLIs.
#
# Thin proxy over the npm/uv/go/cargo channels: it does syntax checking,
# bin→pkg resolution, confirmation, and rendering — then dispatches dumb
# one-shot commands to the owning channel.
#
#   eco <node|py|go|rust> list
#   eco <node|py|go|rust> install [pkg…]
#   eco <node|py|go|rust> update   [pkg…]
#   eco <node|py|go|rust> uninstall <pkg…>

set -euo pipefail

# Resolve the real script location: it may be invoked through a symlink
# (e.g. ~/.local/bin/eco), and the relative paths below depend on it.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
done
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-lifecycle.sh"
eco_conf_load

# ── channel routing ─────────────────────────────────────────────
# User-facing vocabulary (node/py/go/rust) maps to internal scripts
# (npm/uv/go/cargo). The internal name is used in messages.
channel_script() {
    case "$1" in
        node) printf '%s/install-by-npm.sh' "$SCRIPT_DIR" ;;
        py)   printf '%s/install-by-uv.sh' "$SCRIPT_DIR" ;;
        go)   printf '%s/install-by-go.sh' "$SCRIPT_DIR" ;;
        rust) printf '%s/install-by-cargo.sh' "$SCRIPT_DIR" ;;
    esac
}

channel_name() {
    case "$1" in
        node) printf 'npm' ;;
        py)   printf 'uv' ;;
        go)   printf 'go' ;;
        rust) printf 'cargo' ;;
    esac
}

usage() {
    echo "usage: eco <node|py|go|rust> <list|install|update|uninstall> [pkg…]"
    echo ""
    echo "  list                  list installed CLIs with current and latest versions"
    echo "  install [pkg…]        install missing CLIs; without pkg, manifest mode"
    echo "  update [pkg…]         upgrade installed CLIs; without pkg, query outdated"
    echo "  uninstall <pkg…>      remove installed CLIs (package names required)"
    echo ""
    echo "Packages are bin names from eco.conf, or raw package names for unmanaged tools."
}

# ── argument resolution ─────────────────────────────────────────
# conf_row_for <channel> <key> — find the conf row whose bin or pkg matches
# <key> within <channel>. Sets CONF_BIN / CONF_PKG / CONF_FLAG on success;
# returns 1 when no row matches (caller falls back to raw-pkg handling).
conf_row_for() {
    local ch="$1" key="$2" i
    CONF_BIN="" CONF_PKG="" CONF_FLAG=""
    for i in "${!ECO_CONF_BINS[@]}"; do
        [[ "${ECO_CONF_CHANNELS[i]}" == "$ch" ]] || continue
        if [[ "${ECO_CONF_BINS[i]}" == "$key" || "${ECO_CONF_PKGS[i]}" == "$key" ]]; then
            CONF_BIN="${ECO_CONF_BINS[i]}"
            CONF_PKG="${ECO_CONF_PKGS[i]}"
            CONF_FLAG="${ECO_CONF_FLAGS[i]}"
            return 0
        fi
    done
    return 1
}

# resolve_args <verb> <channel> [arg…]
# Fills TARGET_BINS / TARGET_PKGS / TARGET_FLAGS. An arg matching a conf bin
# (or pkg) yields that row's pkg+flag; otherwise the arg is a raw pkg (flag
# empty). go uninstall is the exception: a raw pkg's bin is the module path's
# last segment (the binary name Go installs).
resolve_args() {
    local verb="$1" ch="$2"
    shift 2
    TARGET_BINS=()
    TARGET_PKGS=()
    TARGET_FLAGS=()
    local arg
    for arg in "$@"; do
        if conf_row_for "$ch" "$arg"; then
            TARGET_BINS+=("$CONF_BIN")
            TARGET_PKGS+=("$CONF_PKG")
            TARGET_FLAGS+=("$CONF_FLAG")
        else
            if [[ "$verb" == "uninstall" && "$ch" == "go" ]]; then
                TARGET_BINS+=("${arg##*/}")
            else
                TARGET_BINS+=("$arg")
            fi
            TARGET_PKGS+=("$arg")
            TARGET_FLAGS+=("")
        fi
    done
}

# ── batch confirm + dispatch ────────────────────────────────────
# batch_confirm_and_run <verb> <channel>
# Pre-approved bins (DOTFILES_ACCEPT_TOOLS) join the approved set directly;
# the rest share one batch confirm (default N). Non-interactive mode declines
# unless every target is pre-approved. A declined run exits 0 with a message.
# Approved targets execute one-by-one via the channel's dumb one-shot verb;
# a failed row warns and continues, the aggregate exit code reports any failure.
batch_confirm_and_run() {
    local verb="$1" ch="$2"
    local internal script
    internal="$(channel_name "$ch")"
    script="$(channel_script "$ch")"

    local -a auth_bins=() auth_pkgs=() auth_flags=()
    local -a pend_bins=() pend_pkgs=() pend_flags=()
    local i
    for i in "${!TARGET_BINS[@]}"; do
        if is_pre_approved "${TARGET_BINS[i]}"; then
            auth_bins+=("${TARGET_BINS[i]}")
            auth_pkgs+=("${TARGET_PKGS[i]}")
            auth_flags+=("${TARGET_FLAGS[i]}")
        else
            pend_bins+=("${TARGET_BINS[i]}")
            pend_pkgs+=("${TARGET_PKGS[i]}")
            pend_flags+=("${TARGET_FLAGS[i]}")
        fi
    done

    local pend_count=${#pend_bins[@]}
    if (( pend_count > 0 )); then
        local prompt_verb
        case "$verb" in
            install)   prompt_verb="Install" ;;
            update)    prompt_verb="Update" ;;
            uninstall) prompt_verb="Uninstall" ;;
        esac
        if confirm "$prompt_verb $pend_count via $internal? [y/N]: " 0; then
            for i in "${!pend_bins[@]}"; do
                auth_bins+=("${pend_bins[i]}")
                auth_pkgs+=("${pend_pkgs[i]}")
                auth_flags+=("${pend_flags[i]}")
            done
        else
            info "skipped $pend_count unapproved $internal CLIs"
        fi
    fi

    if (( ${#auth_bins[@]} == 0 )); then
        warn "no $internal CLIs approved for $verb; skipping"
        return 0
    fi

    local verb_one doing done_w
    case "$verb" in
        install)   verb_one="--install-one";   doing="installing";   done_w="installed" ;;
        update)    verb_one="--update-one";    doing="updating";     done_w="updated" ;;
        uninstall) verb_one="--uninstall-one"; doing="uninstalling"; done_w="uninstalled" ;;
    esac

    local rc=0
    for i in "${!auth_bins[@]}"; do
        info "$doing ${auth_bins[i]} (${auth_pkgs[i]}) via $internal..."
        if ! bash "$script" "$verb_one" "${auth_bins[i]}" "${auth_pkgs[i]}" "${auth_flags[i]}"; then
            warn "${auth_bins[i]} $verb failed; retry manually later"
            rc=1
            continue
        fi
        ok "${auth_bins[i]} $done_w"
    done
    return "$rc"
}

# ── per-verb flows ──────────────────────────────────────────────
# list: read-only table of installed CLIs with current and latest versions.
# Always exits 0 (a failed listing is a warning, not an error).
do_list() {
    local ch="$1" script internal
    script="$(channel_script "$ch")"
    internal="$(channel_name "$ch")"
    local rows
    rows="$(bash "$script" --list 2>/dev/null)" || true
    if [[ -z "$rows" ]]; then
        info "no $internal CLIs found"
        return 0
    fi
    printf '%-24s %-14s %s\n' "package" "version" "latest"
    local line pkg cur latest display
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        read -r pkg cur latest <<<"$line"
        if conf_row_for "$ch" "$pkg"; then
            display="$CONF_BIN"
        else
            display="$pkg"
        fi
        printf '%-24s %-14s %s\n' "$display" "$cur" "$latest"
    done <<<"$rows"
}

# install (no pkgs): manifest mode — per-item confirm inside the channel.
do_install_manifest() {
    local ch="$1" script internal
    script="$(channel_script "$ch")"
    internal="$(channel_name "$ch")"
    bash "$script" --install-manifest
}

# update (no pkgs): query outdated, render, batch confirm, dispatch.
do_update_full() {
    local ch="$1" script internal
    script="$(channel_script "$ch")"
    internal="$(channel_name "$ch")"

    local outdated_out rc=0
    outdated_out="$(bash "$script" --outdated)" || rc=$?
    if (( rc != 0 )); then
        warn "outdated query via $internal failed"
        return 1
    fi

    local -a outdated=()
    local line
    while IFS= read -r line; do
        [[ -n "$line" ]] && outdated+=("$line")
    done <<<"$outdated_out"

    if (( ${#outdated[@]} == 0 )); then
        ok "all installed $internal CLIs are up to date"
        return 0
    fi

    TARGET_BINS=()
    TARGET_PKGS=()
    TARGET_FLAGS=()
    local pkg cur latest display
    for line in "${outdated[@]}"; do
        read -r pkg cur latest <<<"$line"
        if conf_row_for "$ch" "$pkg"; then
            TARGET_BINS+=("$CONF_BIN")
            TARGET_PKGS+=("$CONF_PKG")
            TARGET_FLAGS+=("$CONF_FLAG")
            display="$CONF_BIN"
        else
            TARGET_BINS+=("$pkg")
            TARGET_PKGS+=("$pkg")
            TARGET_FLAGS+=("")
            display="$pkg"
        fi
        info "update available: $display ($pkg) $cur → $latest"
    done

    batch_confirm_and_run update "$ch"
}

# ── main ────────────────────────────────────────────────────────
main() {
    # Handle --help/-h before channel validation so `eco --help` works.
    case "${1:-}" in
        -h|--help)
            usage
            return 0
            ;;
    esac

    local ch="${1:-}" verb="${2:-}"

    if [[ -z "$ch" || -z "$verb" ]]; then
        usage >&2
        return 2
    fi

    case "$ch" in
        node|py|go|rust) ;;
        *)
            warn "unknown channel '$ch' (choices: node, py, go, rust)"
            usage >&2
            return 2
            ;;
    esac

    case "$verb" in
        list|install|update|uninstall) ;;
        -h|--help)
            usage
            return 0
            ;;
        *)
            warn "unknown verb '$verb' (choices: list, install, update, uninstall)"
            usage >&2
            return 2
            ;;
    esac

    shift 2 || true

    # Reject option-like args before any work.
    local arg
    for arg in "$@"; do
        [[ "$arg" != -* ]] || { warn "unknown option '$arg'"; return 2; }
    done

    local internal
    internal="$(channel_name "$ch")"

    case "$verb" in
        list)
            (( $# == 0 )) || { warn "list takes no arguments"; return 2; }
            do_list "$ch"
            ;;
        install)
            if (( $# == 0 )); then
                # DOTFILES_SKIP_ECOSYSTEM_TOOLS gates the manifest (bootstrap)
                # path only; an explicit named install is never skipped.
                if [[ -n "${DOTFILES_SKIP_ECOSYSTEM_TOOLS:-}" ]]; then
                    info "DOTFILES_SKIP_ECOSYSTEM_TOOLS is set; skipping $internal ecosystem tool install"
                    return 0
                fi
                do_install_manifest "$ch"
            else
                resolve_args install "$ch" "$@"
                batch_confirm_and_run install "$ch"
            fi
            ;;
        update)
            if (( $# == 0 )); then
                do_update_full "$ch"
            else
                resolve_args update "$ch" "$@"
                batch_confirm_and_run update "$ch"
            fi
            ;;
        uninstall)
            (( $# > 0 )) || { warn "uninstall requires at least one package"; usage >&2; return 2; }
            resolve_args uninstall "$ch" "$@"
            batch_confirm_and_run uninstall "$ch"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

#!/usr/bin/env bash
# _install/manage-tools.sh — unified lifecycle entrypoint for ecosystem CLIs.
#
# Thin by design: it routes named bins to their owning channel, supplies the
# two process shims (query, dispatch), and delegates all collection,
# authorization and wording to the merged views in _scripts/cli-lifecycle.sh.
#
#   manage-tools.sh <status|install|update|uninstall> [bin…]

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-lifecycle.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-registry.sh"

# Routed per-channel bins; ROUTED_NAMED distinguishes "all" from an empty list.
ROUTED_NPM=""; ROUTED_UV=""; ROUTED_GO=""; ROUTED_NAMED=0

usage() {
    echo "usage: $0 <status|install|update|uninstall> [bin…]"
    echo "       bins are routed to their owning channel (npm/uv/go); without"
    echo "       bins, every channel acts on its own registered rows"
}

channel_script() { printf '%s/install-by-%s.sh' "$SCRIPT_DIR" "$1"; }

channel_bins() {
    case "$1" in
        npm) printf '%s' "$ROUTED_NPM" ;;
        uv)  printf '%s' "$ROUTED_UV" ;;
        go)  printf '%s' "$ROUTED_GO" ;;
    esac
}

route_bins() {
    local b i ch found unknown=""
    for b in "$@"; do
        found=0
        for i in "${!ECO_CLI_BINS[@]}"; do
            [[ "${ECO_CLI_BINS[i]}" == "$b" ]] || continue
            found=1
            ch="${ECO_CLI_CHANNELS[i]}"
            case "$ch" in
                npm) ROUTED_NPM+=" $b" ;;
                uv)  ROUTED_UV+=" $b" ;;
                go)  ROUTED_GO+=" $b" ;;
            esac
            break
        done
        (( found )) || unknown+=" $b"
    done
    if [[ -n "$unknown" ]]; then
        warn "unknown bin(s):${unknown} — not in any channel registry"
        return 1
    fi
    ROUTED_NPM="${ROUTED_NPM# }"; ROUTED_UV="${ROUTED_UV# }"; ROUTED_GO="${ROUTED_GO# }"
    return 0
}

# collect_outdated <channel> — prints "pkg cur latest" per outdated row; the
# subprocess behind the engine's STATUS_QUERY_FN / merged update query_fn.
# Machine rows (bin pkg cur latest) carry a redundant leading bin — the
# registry owns that mapping — so it is dropped here and the engine sees one
# row format everywhere. Failure is silent: it means "channel unknown", and
# whoever runs the query owns the warning.
collect_outdated() {
    local line out rc=0 _b pkg cur latest
    out="$(CLI_MACHINE_OUTPUT=1 bash "$(channel_script "$1")" --outdated)" || rc=$?
    (( rc == 0 )) || return 1
    [[ -n "$out" ]] || return 0
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        read -r _b pkg cur latest <<<"$line"
        printf '%s %s %s\n' "$pkg" "$cur" "$latest"
    done <<<"$out"
}

# dispatch_to_channel <verb> <channel> [bin…] — executes the already-authorized
# bins in that channel's own runtime-gated process. The approved set travels on
# the dedicated IPC var, so the user's DOTFILES_ACCEPT_TOOLS is never
# overwritten; the channel then skips its own confirm (is_pre_approved).
dispatch_to_channel() {
    local verb="$1" ch="$2"
    shift 2
    local channel_verb="--$verb"
    [[ "$verb" == "update" ]] && channel_verb="--update-known"
    DOTFILES_APPROVED_TOOLS="$*" bash "$(channel_script "$ch")" "$channel_verb" "$@"
}

do_install() {
    local rc=0 ch bins
    for ch in npm uv go; do
        bins="$(channel_bins "$ch")"
        if (( ROUTED_NAMED == 0 )); then
            bash "$(channel_script "$ch")" || rc=1
        elif [[ -n "$bins" ]]; then
            # shellcheck disable=SC2086
            bash "$(channel_script "$ch")" --install $bins || rc=1
        fi
    done
    return "$rc"
}

main() {
    local verb="${1:-}"
    shift || true

    case "$verb" in
        -h|--help|"") usage; return 0 ;;
        status|install|update|uninstall) ;;
        *) warn "unknown verb '$verb' (choices: status, install, update, uninstall)"; usage >&2; return 1 ;;
    esac

    validate_cli_registry

    if (( $# > 0 )); then
        ROUTED_NAMED=1
        route_bins "$@" || return 1
    fi

    case "$verb" in
        status)
            # Consumed by status_cli_registry in the sourced engine.
            # shellcheck disable=SC2034
            STATUS_CHANNELS=(npm uv go)
            # shellcheck disable=SC2034
            STATUS_QUERY_FN=collect_outdated
            # shellcheck disable=SC2034
            STATUS_PREFIX=1
            # shellcheck disable=SC2034
            STATUS_LABEL="CLI"
            status_cli_registry "$@"
            ;;
        install)   do_install ;;
        update)    update_cli_registry_merged collect_outdated dispatch_to_channel "$@" ;;
        uninstall) uninstall_cli_registry_merged dispatch_to_channel "$@" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

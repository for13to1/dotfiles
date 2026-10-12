#!/usr/bin/env bash
# _install/manage-tools.sh — unified lifecycle entrypoint for ecosystem CLIs.
#
# Routes bins to their owning channel, then delegates to the per-channel script.
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

# Mutation state shared between the collect phase and authorize_and_execute.
MUT_TOTAL=0; MUT_PEND=0; MUT_NPM=""; MUT_UV=""; MUT_GO=""; MUT_PEND_BINS=""
# Channels whose outdated query failed during collection: their state is
# unknown, so an all-clear message would be a lie.
MUT_UNKNOWN=""

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

channel_of() {
    local b="$1" i
    for i in "${!ECO_CLI_BINS[@]}"; do
        if [[ "${ECO_CLI_BINS[i]}" == "$b" ]]; then
            printf '%s\n' "${ECO_CLI_CHANNELS[i]}"
            return 0
        fi
    done
    return 1
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

# collect_outdated <channel> — prints "bin pkg cur latest" per outdated row.
collect_outdated() {
    local ch="$1" script bins out rc=0
    script="$(channel_script "$ch")"
    bins="$(channel_bins "$ch")"
    if (( ROUTED_NAMED == 0 )); then
        out="$(CLI_MACHINE_OUTPUT=1 bash "$script" --outdated)" || rc=$?
    elif [[ -n "$bins" ]]; then
        # shellcheck disable=SC2086
        out="$(CLI_MACHINE_OUTPUT=1 bash "$script" --outdated $bins)" || rc=$?
    else
        return 0
    fi
    (( rc == 0 )) || return 1
    [[ -n "$out" ]] && printf '%s\n' "$out"
    return 0
}

do_status() {
    local ch i bin pkg line
    local -a outdated=()
    local out="" rc=0 failed=" "
    for ch in npm uv go; do
        # A named scope only cares about the channels that hold its bins;
        # don't query (or judge) unrelated channels.
        if (( ROUTED_NAMED )) && [[ -z "$(channel_bins "$ch")" ]]; then
            continue
        fi
        if ! out="$(collect_outdated "$ch")"; then
            # A channel we cannot query (missing runtime, offline) leaves its
            # rows in an unknown state: never render them as "up to date".
            warn "[$ch] state unknown: outdated query failed (runtime missing or offline)"
            failed+="$ch "
            rc=1
            continue
        fi
        while IFS= read -r line; do
            [[ -n "$line" ]] && outdated+=("$ch|$line")
        done <<<"$out"
    done

    local installed=0 outdated_n=0 missing=0 foreign=0 unknown=0
    local cur latest _ch _rest _b _p _c _l
    for i in "${!ECO_CLI_BINS[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        ch="${ECO_CLI_CHANNELS[i]}"
        pkg="${ECO_CLI_PKGS[i]}"
        if (( ROUTED_NAMED )); then
            case " $(channel_bins "$ch") " in
                *" $bin "*) ;;
                *) continue ;;
            esac
        fi
        if [[ -x "$CLI_BIN_DIR/$bin" ]]; then
            installed=$(( installed + 1 ))
            if [[ "$failed" == *" $ch "* ]]; then
                unknown=$(( unknown + 1 ))
                info "[$ch] $bin ($pkg) state unknown"
                continue
            fi
            cur=""; latest=""
            # collect_outdated rows are "bin pkg cur latest"; the channel is
            # carried as the prefix before the first '|'. The count guard is
            # required: bash < 4.4 treats an empty-array expansion under
            # `set -u` as an unbound variable (macOS system bash is 3.2).
            if (( ${#outdated[@]} > 0 )); then
                for line in "${outdated[@]}"; do
                _ch="${line%%|*}"; _rest="${line#*|}"
                read -r _b _p _c _l <<<"$_rest"
                if [[ "$_ch" == "$ch" && "$_p" == "$pkg" ]]; then
                    cur="$_c"; latest="$_l"
                    break
                fi
            done
            fi
            if [[ -n "$latest" ]]; then
                outdated_n=$(( outdated_n + 1 ))
                info "[$ch] $bin ($pkg) $cur → $latest"
            else
                ok "[$ch] $bin ($pkg) up to date"
            fi
        elif [[ "$(channel_detect "$ch")" == "path" ]] && is_installed "$bin"; then
            foreign=$(( foreign + 1 ))
            warn "[$ch] $bin ($pkg) present on PATH — not managed here"
        else
            missing=$(( missing + 1 ))
            info "[$ch] $bin ($pkg) missing"
        fi
    done

    local summary="summary: $installed installed, $outdated_n outdated, $missing missing, $foreign on PATH"
    (( unknown > 0 )) && summary+=", $unknown unknown"
    info "$summary"
    return "$rc"
}

# authorize_and_execute <verb> <prompt-verb>: one batch confirm, then
# delegate approved bins to their channels. Operates on MUT_*.
authorize_and_execute() {
    local verb="$1" prompt_verb="$2" channel_verb="$1"
    local ch bins exec_rc=0
    if [[ "$verb" == "update" ]]; then
        channel_verb="update-known"
    fi

    if (( MUT_TOTAL == 0 )); then
        if [[ -n "$MUT_UNKNOWN" ]]; then
            # Some channel could not be queried; never claim everything is
            # current when part of the picture is missing.
            warn "cannot confirm every CLI is up to date: state unknown for${MUT_UNKNOWN}"
            return 1
        fi
        if [[ "$verb" == "update" ]]; then
            # Under a named scope "all installed … up to date" could be a
            # lie: an unnamed outdated row exists but was filtered out.
            if (( ROUTED_NAMED )); then
                ok "no named CLIs need updating"
            else
                ok "all installed CLIs are up to date"
            fi
        else
            if (( ROUTED_NAMED )); then
                info "no named CLIs to uninstall"
            else
                info "no installed CLIs to uninstall"
            fi
        fi
        return 0
    fi

    if (( MUT_PEND > 0 )); then
        if confirm "$prompt_verb $MUT_PEND more via npm/uv/go? [y/N]: " 0; then
            for bin in $MUT_PEND_BINS; do
                ch="$(channel_of "$bin")" || continue
                case "$ch" in
                    npm) MUT_NPM+=" $bin" ;; uv) MUT_UV+=" $bin" ;; go) MUT_GO+=" $bin" ;;
                esac
            done
        else
            info "skipped $MUT_PEND unapproved CLIs"
        fi
    fi

    MUT_NPM="${MUT_NPM# }"; MUT_UV="${MUT_UV# }"; MUT_GO="${MUT_GO# }"
    for ch in npm uv go; do
        case "$ch" in
            npm) bins="$MUT_NPM" ;; uv) bins="$MUT_UV" ;; go) bins="$MUT_GO" ;;
        esac
        [[ -n "$bins" ]] || continue
        # The merged confirm already ran here, so the channel is told which
        # bins are approved through the dedicated IPC var — the user's
        # DOTFILES_ACCEPT_TOOLS is never overwritten.
        # shellcheck disable=SC2086
        DOTFILES_APPROVED_TOOLS="$bins" bash "$(channel_script "$ch")" --"$channel_verb" $bins \
            || { warn "$ch $verb had failures"; exec_rc=1; }
    done
    return "$exec_rc"
}

do_update() {
    local ch line bin pkg cur latest out collect_rc=0
    MUT_TOTAL=0; MUT_PEND=0; MUT_NPM=""; MUT_UV=""; MUT_GO=""; MUT_PEND_BINS=""
    MUT_UNKNOWN=""

    for ch in npm uv go; do
        # Named scope: only the channels that own the named bins are relevant.
        if (( ROUTED_NAMED )) && [[ -z "$(channel_bins "$ch")" ]]; then
            continue
        fi
        out="$(collect_outdated "$ch")" || { warn "outdated query via $ch failed; skipping $ch"; MUT_UNKNOWN+=" $ch"; collect_rc=1; continue; }
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            read -r bin pkg cur latest <<<"$line"
            MUT_TOTAL=$(( MUT_TOTAL + 1 ))
            info "[$ch] $bin ($pkg) $cur → $latest"
            if is_pre_approved "$bin"; then
                case "$ch" in
                    npm) MUT_NPM+=" $bin" ;; uv) MUT_UV+=" $bin" ;; go) MUT_GO+=" $bin" ;;
                esac
            else
                MUT_PEND=$(( MUT_PEND + 1 ))
                MUT_PEND_BINS+=" $bin"
            fi
        done <<<"$out"
    done

    authorize_and_execute update "Update" || collect_rc=1
    return "$collect_rc"
}
do_uninstall() {
    local ch i bin pkg
    MUT_TOTAL=0; MUT_PEND=0; MUT_NPM=""; MUT_UV=""; MUT_GO=""; MUT_PEND_BINS=""
    MUT_UNKNOWN=""

    for ch in npm uv go; do
        for i in "${!ECO_CLI_BINS[@]}"; do
            [[ "${ECO_CLI_CHANNELS[i]}" == "$ch" ]] || continue
            bin="${ECO_CLI_BINS[i]}"
            [[ -x "$CLI_BIN_DIR/$bin" ]] || continue
            if (( ROUTED_NAMED )); then
                case " $(channel_bins "$ch") " in
                    *" $bin "*) ;;
                    *) continue ;;
                esac
            fi
            pkg="${ECO_CLI_PKGS[i]}"
            MUT_TOTAL=$(( MUT_TOTAL + 1 ))
            info "[$ch] $bin ($pkg)"
            if is_pre_approved "$bin"; then
                case "$ch" in
                    npm) MUT_NPM+=" $bin" ;; uv) MUT_UV+=" $bin" ;; go) MUT_GO+=" $bin" ;;
                esac
            else
                MUT_PEND=$(( MUT_PEND + 1 ))
                MUT_PEND_BINS+=" $bin"
            fi
        done
    done

    authorize_and_execute uninstall "Uninstall"
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
        status)    do_status ;;
        install)   do_install ;;
        update)    do_update ;;
        uninstall) do_uninstall ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

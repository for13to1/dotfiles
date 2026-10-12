#!/usr/bin/env bash
# _scripts/cli-lifecycle.sh — the CLI lifecycle engine (install/status/update/
# uninstall) shared by the npm/uv/go channels and the unified entrypoint.
#
# Sourced (never executed). Layering:
#   _scripts/common.sh        — generic shell infrastructure (output, prompts…)
#   _scripts/cli-registry.sh  — the declarative eco_cli table (one row per CLI)
#   _scripts/cli-lifecycle.sh — this file: table validation + the lifecycle
#   _install/install-by-*.sh  — one channel each: runtime gate + per-action fns
#   _install/manage-tools.sh  — routes named bins across channels, one confirm
#
# Pulls in common.sh itself (msg/confirm/is_installed live there).
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# is_pre_approved <bin>
# Returns 0 when <bin> is pre-approved. Two sources, distinct semantics:
#   DOTFILES_ACCEPT_TOOLS   — user intent: auto-approve this bin everywhere
#                             (space-separated bin names)
#   DOTFILES_APPROVED_TOOLS — manager→channel IPC: the merged confirm already
#                             ran, these bins must not prompt again
# DOTFILES_ACCEPT_INSTALLS is the pre-rename spelling; it still works but warns
# once so the name can be retired.
is_pre_approved() {
    local bin="$1"
    if [[ -z "${DOTFILES_ACCEPT_TOOLS:-}" && -n "${DOTFILES_ACCEPT_INSTALLS:-}" \
          && -z "${_DOTFILES_ACCEPT_INSTALLS_WARNED:-}" ]]; then
        warn "DOTFILES_ACCEPT_INSTALLS is deprecated; use DOTFILES_ACCEPT_TOOLS"
        _DOTFILES_ACCEPT_INSTALLS_WARNED=1
    fi
    case " ${DOTFILES_APPROVED_TOOLS:-} " in
        *" $bin "*) return 0 ;;
    esac
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
# Empty-result guards are required throughout: bash < 4.4 treats an empty
# array expansion under `set -u` as an unbound variable (macOS system bash is
# 3.2, which CI's macos-latest runner uses).
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
    # bash 3.2 + set -u: never expand a possibly-empty array bare.
    if (( ${#c[@]} > 0 )); then
        ECO_CLI_CHANNELS=("${c[@]}")
        ECO_CLI_BINS=("${b[@]}")
        ECO_CLI_PKGS=("${p[@]}")
        ECO_CLI_FLAGS=("${f[@]}")
        ECO_CLI_POLICIES=("${pl[@]}")
    else
        ECO_CLI_CHANNELS=()
        ECO_CLI_BINS=()
        ECO_CLI_PKGS=()
        ECO_CLI_FLAGS=()
        ECO_CLI_POLICIES=()
    fi
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
    # Inner break dedups repeated bin args. Empty-source guard first: bash 3.2
    # + set -u fails on a bare empty-array expansion.
    if (( ${#CLI_REGISTRY_IDX[@]} > 0 )); then
        for i in "${CLI_REGISTRY_IDX[@]}"; do
            for b in "$@"; do
                if [[ "$b" == "${ECO_CLI_BINS[i]}" ]]; then
                    keep_idx+=("$i")
                    break
                fi
            done
        done
    fi
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
    local i b bin pkg flag path want rc=0
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
                    warn "$bin install failed; retry manually later"
                    rc=1
                    continue
                fi
                ok "$bin installed"
                ;;
            prompt)
                warn "$bin not found; install it via $channel?"
                approve_install "$bin" "Install now? [y/N]: " || continue
                if ! "$installer" "$bin" "$pkg" "$flag"; then
                    warn "$bin install failed; retry manually later"
                    rc=1
                    continue
                fi
                ok "$bin installed"
                ;;
        esac
    done
    return "$rc"
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

    authorize_and_run update updating updated "$updater" "$channel" "${to_update_idx[@]}"
}

# authorize_and_run <verb> <doing> <done> <action_fn> <channel> <idx…>
# Authorization + execution tail shared by update and uninstall (engine-side):
# pre-approved bins run directly, the rest share one batch confirm; a failed
# row warns and continues, and the aggregate exit code reports any failure.
# <doing>/<done> carry the message word forms (updating/updated,
# uninstalling/uninstalled) — bash 3.2 has no case-modification expansion.
authorize_and_run() {
    local verb="$1" doing="$2" done_w="$3" action_fn="$4" channel="$5"
    shift 5
    local -a final_idx=() pending_idx=()
    local j pkg flag declined=0 failed=0
    local prompt_verb
    case "$verb" in
        update) prompt_verb="Update" ;;
        *) prompt_verb="Uninstall" ;;
    esac

    for j in "$@"; do
        if is_pre_approved "${ECO_CLI_BINS[j]}"; then
            final_idx+=("$j")
        else
            pending_idx+=("$j")
        fi
    done
    if (( ${#pending_idx[@]} > 0 )); then
        if confirm "$prompt_verb ${#pending_idx[@]} via $channel? [y/N]: " 0; then
            for j in "${pending_idx[@]}"; do
                final_idx+=("$j")
            done
        else
            declined=1
        fi
    fi

    if (( ${#final_idx[@]} == 0 )); then
        warn "no $channel CLIs approved for $verb; skipping"
        return 0
    fi
    if (( declined )); then
        info "skipped ${#pending_idx[@]} unapproved $channel CLIs"
    fi

    for j in "${final_idx[@]}"; do
        pkg="${ECO_CLI_PKGS[j]}"
        flag="${ECO_CLI_FLAGS[j]}"
        info "$doing ${ECO_CLI_BINS[j]} ($pkg) via $channel..."
        if ! "$action_fn" "${ECO_CLI_BINS[j]}" "$pkg" "$flag"; then
            warn "${ECO_CLI_BINS[j]} $verb failed; retry manually later"
            failed=1
            continue
        fi
        ok "${ECO_CLI_BINS[j]} $done_w"
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

    authorize_and_run update updating updated "$updater" "$channel" "${CLI_REGISTRY_IDX[@]}"
}

# uninstall_cli_registry <uninstall_fn> <channel> [bin…]
# Removes installed rows; candidates and scope match update, and the
# authorization tail is shared with it. --always rows have no special case:
# uninstalling one just means the next install run reinstalls it.
uninstall_cli_registry() {
    local uninstall_fn="$1" channel="$2"
    shift 2

    cli_registry_candidates
    if (( ${#CLI_REGISTRY_IDX[@]} == 0 )); then
        info "no installed $channel CLIs from the registry; nothing to uninstall"
        return 0
    fi
    cli_registry_scope_named "$channel" uninstall "$@" || return 0

    authorize_and_run uninstall uninstalling uninstalled \
        "$uninstall_fn" "$channel" "${CLI_REGISTRY_IDX[@]}"
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
# date / update available / state unknown) and a summary. Never mutates or
# prompts. A failed/unavailable outdated query (CLI_STATUS_UNKNOWN=1) marks
# installed rows unknown and still fails the run — never up to date.
status_cli_registry() {
    local outdated_fn="$1" channel="$2" detect="$3"
    shift 3
    local query_ok=1
    [[ -n "${CLI_STATUS_UNKNOWN:-}" ]] && query_ok=0
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

    # Query only if at least one candidate is installed. A failed query must
    # not swallow the listing: the installed/missing facts are still knowable,
    # so the rows render with an unknown version state and the run fails.
    # When the runtime gate already failed (CLI_STATUS_UNKNOWN), query_ok
    # stays 0 and the query is skipped — one warning, not three.
    local need_query=0
    OUTDATED_LINES=()
    for i in "${show_idx[@]}"; do
        if [[ -x "$CLI_BIN_DIR/${ECO_CLI_BINS[i]}" ]]; then
            need_query=1
            break
        fi
    done
    if (( need_query && query_ok )); then
        query_outdated "$outdated_fn" "$channel" || query_ok=0
    fi
    local installed=0 outdated=0 missing=0 foreign=0 unknown=0
    local cur latest line _p _c _l
    for i in "${show_idx[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        pkg="${ECO_CLI_PKGS[i]}"
        if [[ -x "$CLI_BIN_DIR/$bin" ]]; then
            installed=$(( installed + 1 ))
            if (( ! query_ok )); then
                unknown=$(( unknown + 1 ))
                info "$bin ($pkg) state unknown"
                continue
            fi
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

    local summary="summary: $installed installed, $outdated outdated, $missing missing, $foreign on PATH"
    (( unknown > 0 )) && summary+=", $unknown unknown"
    info "$summary"
    (( query_ok ))
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
# --outdated and --update-known are internal machine verbs driven by the
# unified entrypoint (_install/manage-tools.sh); not listed in usage.
    case "$verb" in
        ""|-h|--help) ;;
        --install|--status|--outdated|--update|--update-known|--uninstall)
            for arg in "${@:9}"; do
                [[ "$arg" != -* ]] || { warn "unknown option '$arg' for $verb"; return 1; }
            done
            ;;
        *)
            warn "unknown option '$verb' (supported: --install, --status, --update, --uninstall, -h|--help)"
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
    # shellcheck disable=SC2034  # read by msg() in common.sh
    [[ "$verb" == "--outdated" ]] && CLI_MACHINE_OUTPUT=1

    # --status and --outdated are read-only: the runtime gate must probe, not
    # mutate (no `fnm install`, no `go env -w`). Channels key off this flag.
    # shellcheck disable=SC2034  # read by status_cli_registry (same shell)
    if [[ "$verb" == "--status" || "$verb" == "--outdated" ]]; then
        CLI_READ_ONLY=1
    else
        unset CLI_READ_ONLY
    fi

    validate_cli_registry
    if ! "$ensure"; then
        # A missing runtime leaves the registry's version state unknowable.
        # A read-only view must not pretend it can see it: for --status the
        # dispatch below still lists every row with `state unknown` and the
        # run fails; --outdated has nothing to report. A mutation verb has
        # nothing to act on, so skipping is success.
        if [[ "$verb" == "--outdated" ]]; then
            return 1
        elif [[ "$verb" != "--status" ]]; then
            return 0
        fi
        CLI_STATUS_UNKNOWN=1
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

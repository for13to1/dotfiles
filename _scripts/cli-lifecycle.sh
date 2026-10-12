#!/usr/bin/env bash
# _scripts/cli-lifecycle.sh — the CLI lifecycle engine (install/status/update/
# uninstall) shared by the npm/uv/go channels and the unified entrypoint.
#
# Sourced (never executed). Layering:
#   _scripts/common.sh        — generic shell infrastructure (output, prompts…)
#   _scripts/cli-registry.sh  — the declarative eco_cli table (one row per CLI)
#   _scripts/cli-lifecycle.sh — this file: table validation + the lifecycle
#   _install/install-by-*.sh  — one channel each: runtime gate + per-action fns
#   _install/manage-tools.sh  — entrypoint: routing plus the query/dispatch
#                               shims behind the merged (cross-channel) views
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

# lifecycle_scope_named_idx [bin…]
# Fills SCOPE_IDX with the installed candidates (CLI_REGISTRY_IDX), narrowed
# to [bin…] when given. Silent on an empty result: the merged views own their
# own empty-scope wording, unlike cli_registry_scope_named's per-channel text.
lifecycle_scope_named_idx() {
    SCOPE_IDX=()
    (( ${#CLI_REGISTRY_IDX[@]} > 0 )) || return 0
    if (( $# == 0 )); then
        SCOPE_IDX=("${CLI_REGISTRY_IDX[@]}")
        return 0
    fi
    local i b
    for i in "${CLI_REGISTRY_IDX[@]}"; do
        for b in "$@"; do
            if [[ "$b" == "${ECO_CLI_BINS[i]}" ]]; then
                SCOPE_IDX+=("$i")
                break
            fi
        done
    done
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

# lifecycle_authorize <prompt-template> <idx…>
# The authorization core shared by every verb view: pre-approved bins join the
# approved set directly, the rest share one batch confirm whose prompt is
# printf-formatted from <prompt-template> with the pending count as %d.
# Sets AUTH_IDX (final approved rows), AUTH_PEND and AUTH_DECLINED. Prints
# nothing — message wording differs between the single-channel and merged
# views, so callers assemble it from this state.
lifecycle_authorize() {
    local template="$1" prompt
    shift
    AUTH_IDX=()
    AUTH_PEND=0
    AUTH_DECLINED=0
    local -a pend=()
    local j
    for j in "$@"; do
        if is_pre_approved "${ECO_CLI_BINS[j]}"; then
            AUTH_IDX+=("$j")
        else
            pend+=("$j")
        fi
    done
    AUTH_PEND=${#pend[@]}
    if (( AUTH_PEND > 0 )); then
        # The template is our own format string (it carries %d) — intentional.
        # shellcheck disable=SC2059
        printf -v prompt "$template" "$AUTH_PEND"
        if confirm "$prompt" 0; then
            for j in "${pend[@]}"; do
                AUTH_IDX+=("$j")
            done
        else
            AUTH_DECLINED=1
        fi
    fi
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
    local i pkg flag failed=0
    local prompt_verb
    case "$verb" in
        update) prompt_verb="Update" ;;
        *) prompt_verb="Uninstall" ;;
    esac

    lifecycle_authorize "$prompt_verb %d via $channel? [y/N]: " "$@"

    if (( ${#AUTH_IDX[@]} == 0 )); then
        warn "no $channel CLIs approved for $verb; skipping"
        return 0
    fi
    if (( AUTH_DECLINED )); then
        info "skipped $AUTH_PEND unapproved $channel CLIs"
    fi

    for i in "${AUTH_IDX[@]}"; do
        pkg="${ECO_CLI_PKGS[i]}"
        flag="${ECO_CLI_FLAGS[i]}"
        info "$doing ${ECO_CLI_BINS[i]} ($pkg) via $channel..."
        if ! "$action_fn" "${ECO_CLI_BINS[i]}" "$pkg" "$flag"; then
            warn "${ECO_CLI_BINS[i]} $verb failed; retry manually later"
            failed=1
            continue
        fi
        ok "${ECO_CLI_BINS[i]} $done_w"
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

# ── status view (single implementation, two callers) ─────────────
# Caller-set context, because bash has no closures:
#   STATUS_CHANNELS    channels whose version state is queried; rendering
#                      still follows the registry row order
#   STATUS_QUERY_FN    <channel> → "pkg cur latest" rows; rc != 0 marks the
#                      channel unknown (the query impl owns the warning)
#   STATUS_PREFIX      1 = "[ch] " row prefix (unified view); 0 = bare rows
#   STATUS_LABEL       channel word for the empty-scope message
#   STATUS_OUTDATED_FN in-process outdated fn for status_query_inproc
#   CLI_STATUS_UNKNOWN set only by run_cli_channel's failed runtime gate
#                      (channel --status): skip every query and render all
#                      installed rows unknown (one warning, from the gate
#                      itself). The unified entrypoint never sets it — a
#                      channel subprocess failure travels as the query fn's
#                      rc instead.
STATUS_CHANNELS=(npm uv go)
STATUS_QUERY_FN=""
STATUS_PREFIX=0
STATUS_LABEL="CLI"
STATUS_OUTDATED_FN=""
status_query_inproc() {
    query_outdated "$STATUS_OUTDATED_FN" "$1" || return 1
    if (( ${#OUTDATED_LINES[@]} > 0 )); then
        printf '%s\n' "${OUTDATED_LINES[@]}"
    fi
}

# status_cli_registry [bin…]
# Read-only: prints every in-scope registry row's state (missing / on PATH /
# up to date / update available / state unknown) across STATUS_CHANNELS, with
# one summary and one exit code. Never mutates or prompts. A failed query (or
# CLI_STATUS_UNKNOWN) marks that channel's installed rows unknown and fails
# the run — never up to date. Outdated rows arrive as "pkg cur latest" tagged
# with their channel before '|'; the split is field-safe (bash < 4.4 treats an
# empty-array expansion under `set -u` as unbound — macOS system bash is 3.2).
status_cli_registry() {
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
        info "no $STATUS_LABEL CLIs among the named bins; nothing to show"
        return 0
    fi

    local ch rows line failed="" rc=0 need_query
    local -a tagged=()
    if [[ -n "${CLI_STATUS_UNKNOWN:-}" ]]; then
        rc=1
        for ch in "${STATUS_CHANNELS[@]}"; do
            failed+=" $ch "
        done
    else
        for ch in "${STATUS_CHANNELS[@]}"; do
            # Query only when this channel owns an installed row in scope —
            # a runtime nobody needs must not fail the run.
            need_query=0
            for i in "${show_idx[@]}"; do
                if [[ "${ECO_CLI_CHANNELS[i]}" == "$ch" \
                      && -x "$CLI_BIN_DIR/${ECO_CLI_BINS[i]}" ]]; then
                    need_query=1
                    break
                fi
            done
            (( need_query )) || continue
            # A failed query must not swallow the listing: installed/missing
            # facts are still knowable, so rows render with an unknown version
            # state and the run fails.
            rows="$("$STATUS_QUERY_FN" "$ch")" || { failed+=" $ch "; rc=1; continue; }
            while IFS= read -r line; do
                [[ -n "$line" ]] && tagged+=("$ch|$line")
            done <<<"$rows"
        done
    fi

    local installed=0 outdated=0 missing=0 foreign=0 unknown=0
    local pre cur latest _ch _rest _p _c _l
    for i in "${show_idx[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        pkg="${ECO_CLI_PKGS[i]}"
        ch="${ECO_CLI_CHANNELS[i]}"
        pre=""
        (( STATUS_PREFIX )) && pre="[$ch] "
        if [[ -x "$CLI_BIN_DIR/$bin" ]]; then
            installed=$(( installed + 1 ))
            if [[ "$failed" == *" $ch "* ]]; then
                unknown=$(( unknown + 1 ))
                info "${pre}$bin ($pkg) state unknown"
                continue
            fi
            cur=""; latest=""
            if (( ${#tagged[@]} > 0 )); then
                for line in "${tagged[@]}"; do
                    _ch="${line%%|*}"; _rest="${line#*|}"
                    read -r _p _c _l <<<"$_rest"
                    if [[ "$_ch" == "$ch" && "$_p" == "$pkg" ]]; then
                        cur="$_c"; latest="$_l"
                        break
                    fi
                done
            fi
            if [[ -n "$latest" ]]; then
                outdated=$(( outdated + 1 ))
                info "${pre}update available: $bin ($pkg) $cur → $latest"
            else
                ok "${pre}$bin ($pkg) up to date"
            fi
        elif [[ "$(channel_detect "$ch")" == "path" ]] && is_installed "$bin"; then
            foreign=$(( foreign + 1 ))
            warn "${pre}$bin ($pkg) present on PATH — not managed here"
        else
            missing=$(( missing + 1 ))
            info "${pre}$bin ($pkg) missing"
        fi
    done

    local summary="summary: $installed installed, $outdated outdated, $missing missing, $foreign on PATH"
    (( unknown > 0 )) && summary+=", $unknown unknown"
    info "$summary"
    return "$rc"
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

# ── merged (cross-channel) verbs ─────────────────────────────────
# The unified entrypoint's views: one query pass over the owning channels,
# one merged confirm, then each channel executes in its own runtime-gated
# process through <dispatch_fn> <verb> <channel> [bin…] (the approved bins
# travel on DOTFILES_APPROVED_TOOLS — never DOTFILES_ACCEPT_TOOLS). The
# shims own the I/O; every count, match, prompt and message lives here.

# update_cli_registry_merged <query_fn> <dispatch_fn> [bin…]
# Collects installed-and-outdated rows across npm/uv/go via <query_fn>
# <channel> (silent on failure — the query implementation warns), confirms
# the pending set once for all channels together, then dispatches the
# approved bins per channel. A channel whose query fails is skipped — its
# rows stay unknown, never "up to date" — and fails the run; healthy
# channels proceed. Channels owning no in-scope row are never woken.
update_cli_registry_merged() {
    local query_fn="$1" dispatch_fn="$2"
    shift 2
    local ch i j rows line pkg cur latest bins
    local -a scope_idx=() ch_idx=() row_idx=() rowlist=()
    local total=0 rc=0 named_scope=0
    local failed=""

    (( $# > 0 )) && named_scope=1
    cli_registry_candidates
    lifecycle_scope_named_idx "$@"
    if (( ${#SCOPE_IDX[@]} > 0 )); then
        scope_idx=("${SCOPE_IDX[@]}")
    fi

    for ch in npm uv go; do
        ch_idx=()
        if (( ${#scope_idx[@]} > 0 )); then
            for i in "${scope_idx[@]}"; do
                [[ "${ECO_CLI_CHANNELS[i]}" == "$ch" ]] && ch_idx+=("$i")
            done
        fi
        (( ${#ch_idx[@]} > 0 )) || continue
        rows="$($query_fn "$ch")" || { failed+=" $ch"; rc=1; continue; }
        rowlist=()
        while IFS= read -r line; do
            [[ -n "$line" ]] && rowlist+=("$line")
        done <<<"$rows"
        if (( ${#rowlist[@]} > 0 )); then
            for line in "${rowlist[@]}"; do
                read -r pkg cur latest <<<"$line"
                # Registry-driven match: a row outside the scope (foreign
                # global, not installed here) is never counted or acted on.
                for j in "${ch_idx[@]}"; do
                    [[ "${ECO_CLI_PKGS[j]}" == "$pkg" ]] || continue
                    info "[$ch] update available: ${ECO_CLI_BINS[j]} ($pkg) $cur → $latest"
                    total=$(( total + 1 ))
                    row_idx+=("$j")
                    break
                done
            done
        fi
    done

    if (( total == 0 )); then
        if [[ -n "$failed" ]]; then
            # Some channel could not be queried; never claim everything is
            # current when part of the picture is missing.
            warn "cannot confirm every CLI is up to date: state unknown for${failed}"
            return 1
        fi
        if (( named_scope )); then
            ok "no named CLIs need updating"
        else
            ok "all installed CLIs are up to date"
        fi
        return 0
    fi

    lifecycle_authorize "Update %d more via npm/uv/go? [y/N]: " "${row_idx[@]}"
    if (( AUTH_DECLINED )); then
        info "skipped $AUTH_PEND unapproved CLIs"
    fi
    for ch in npm uv go; do
        bins=""
        if (( ${#AUTH_IDX[@]} > 0 )); then
            for i in "${AUTH_IDX[@]}"; do
                [[ "${ECO_CLI_CHANNELS[i]}" == "$ch" ]] || continue
                bins+=" ${ECO_CLI_BINS[i]}"
            done
        fi
        bins="${bins# }"
        [[ -n "$bins" ]] || continue
        # shellcheck disable=SC2086  # bins are registry names, split on purpose
        $dispatch_fn update "$ch" $bins \
            || { warn "$ch update had failures"; rc=1; }
    done
    return "$rc"
}

# uninstall_cli_registry_merged <dispatch_fn> [bin…]
# Enumerates installed in-scope rows across channels, confirms the pending
# set once, and dispatches per channel. No query is involved, so there is no
# unknown state here — only the merged empty-scope messages and one prompt.
uninstall_cli_registry_merged() {
    local dispatch_fn="$1"
    shift
    local ch i bins
    local -a scope_idx=() row_idx=()
    local total=0 rc=0 named_scope=0

    (( $# > 0 )) && named_scope=1
    cli_registry_candidates
    lifecycle_scope_named_idx "$@"
    if (( ${#SCOPE_IDX[@]} > 0 )); then
        scope_idx=("${SCOPE_IDX[@]}")
    fi

    for ch in npm uv go; do
        if (( ${#scope_idx[@]} > 0 )); then
            for i in "${scope_idx[@]}"; do
                [[ "${ECO_CLI_CHANNELS[i]}" == "$ch" ]] || continue
                info "[$ch] ${ECO_CLI_BINS[i]} (${ECO_CLI_PKGS[i]})"
                total=$(( total + 1 ))
                row_idx+=("$i")
            done
        fi
    done

    if (( total == 0 )); then
        if (( named_scope )); then
            info "no named CLIs to uninstall"
        else
            info "no installed CLIs to uninstall"
        fi
        return 0
    fi

    lifecycle_authorize "Uninstall %d more via npm/uv/go? [y/N]: " "${row_idx[@]}"
    if (( AUTH_DECLINED )); then
        info "skipped $AUTH_PEND unapproved CLIs"
    fi
    for ch in npm uv go; do
        bins=""
        if (( ${#AUTH_IDX[@]} > 0 )); then
            for i in "${AUTH_IDX[@]}"; do
                [[ "${ECO_CLI_CHANNELS[i]}" == "$ch" ]] || continue
                bins+=" ${ECO_CLI_BINS[i]}"
            done
        fi
        bins="${bins# }"
        [[ -n "$bins" ]] || continue
        # shellcheck disable=SC2086  # bins are registry names, split on purpose
        $dispatch_fn uninstall "$ch" $bins \
            || { warn "$ch uninstall had failures"; rc=1; }
    done
    return "$rc"
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
            STATUS_CHANNELS=("$channel")
            STATUS_QUERY_FN=status_query_inproc
            STATUS_PREFIX=0
            STATUS_LABEL="$channel"
            STATUS_OUTDATED_FN="$outdated"
            status_cli_registry "$@"
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

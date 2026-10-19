#!/usr/bin/env bash
# _scripts/cli-lifecycle.sh — the CLI lifecycle engine shared by the
# npm/uv/go/cargo channels and the unified eco entrypoint.
#
# Sourced (never executed). Layering:
#   _scripts/common.sh        — generic shell infrastructure (output, prompts…)
#   _scripts/cli-lifecycle.sh — this file: manifest loading/validation, install
#                               detection, the shared manifest-install loop, and
#                               the channel CLI shape (channel_dispatch)
#   _scripts/eco.conf         — the declarative manifest (one row per CLI)
#   _install/install-by-*.sh  — one channel each: runtime gate + per-action fns
#   _install/eco.sh           — entrypoint: syntax, resolution, confirmation,
#                               rendering, dispatch
#
# Pulls in common.sh itself (msg/confirm/is_installed live there).
# shellcheck shell=bash

# shellcheck source=/dev/null
source "$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# ── Install prefix ──────────────────────────────────────────────
# The single mutation scope: every managed bin lands here. Install may honor
# foreign PATH installs via detect=path, but update/uninstall never touch
# files outside it.
ECO_BIN_DIR="$HOME/.local/bin"

# ── Package names ───────────────────────────────────────────────
# eco stores no versions: a channel's package manager reports them (`list`) or
# resolves them (`install`/`update`). Any `pkg@selector` is therefore refused
# rather than interpreted, because the three managers read that syntax
# differently (npm: dist-tag/range/alias, uv: a local path, cargo:
# `<crate>@<ver>`) and eco has no business guessing which was meant.
#
# A scoped npm name (one leading '@', e.g. @scope/name) is not a selector; any
# further '@' is.
pkg_has_selector() {
    local pkg="$1"
    [[ "${pkg#@}" == *@* ]]
}

# ── Install detection ───────────────────────────────────────────
# npm keys only on the canonical prefix (avoids old fnm per-Node globals
# being mistaken for a current install); uv/go/cargo also accept PATH installs.
channel_detect() {
    case "$1" in
        npm) printf 'canonical' ;;
        uv|go|cargo) printf 'path' ;;
    esac
}

# ── Manifest configuration (eco.conf) ───────────────────────────
# Format per row: <渠道> <默认y|n> <bin> <pkg> [flag]
#   渠道: node | py | go | rust (user-facing vocabulary)
#   默认: y = install pre-selected, n = pre-skipped (confirm can flip)
#   bin : identity key — detection, prompts and messages all use it
#   pkg : install target (npm package / pip package / go module path / crate)
#   flag: channel-specific flag passed before pkg ("" if none), no spaces
#
# ECO_CONF points at the manifest file; the default is eco.conf next to this
# script. Tests override ECO_CONF to point at a fixture.
ECO_CONF="${ECO_CONF:-$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/eco.conf}"

ECO_CONF_CHANNELS=()
ECO_CONF_BINS=()
ECO_CONF_PKGS=()
ECO_CONF_FLAGS=()
ECO_CONF_DEFAULTS=()

# eco_conf_load — parse and validate ECO_CONF into the ECO_CONF_* arrays.
# Loudly fails on: unreadable file, empty manifest, malformed rows, unknown
# channels, bad defaults, empty/duplicate bins or pkgs, bins with slashes,
# flags with spaces.
eco_conf_load() {
    [[ -f "$ECO_CONF" ]] || { warn "eco.conf not found: $ECO_CONF"; return 1; }
    ECO_CONF_CHANNELS=()
    ECO_CONF_BINS=()
    ECO_CONF_PKGS=()
    ECO_CONF_FLAGS=()
    ECO_CONF_DEFAULTS=()
    local line ch def bin pkg flag extra lineno=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        # Trim leading/trailing whitespace; skip comments and blank lines.
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" || "$line" == \#* ]] && continue
        read -r ch def bin pkg flag extra <<<"$line"
        if [[ -n "$extra" ]]; then
            warn "eco.conf:$lineno: too many fields (expected <channel> <default> <bin> <pkg> [flag])"
            return 1
        fi
        flag="${flag:-}"
        if [[ -z "$ch" || -z "$def" || -z "$bin" || -z "$pkg" ]]; then
            warn "eco.conf:$lineno: expected <channel> <default> <bin> <pkg> [flag]"
            return 1
        fi
        ECO_CONF_CHANNELS+=("$ch")
        ECO_CONF_BINS+=("$bin")
        ECO_CONF_PKGS+=("$pkg")
        ECO_CONF_FLAGS+=("$flag")
        ECO_CONF_DEFAULTS+=("$def")
    done < "$ECO_CONF"
    eco_conf_validate
}

# eco_conf_validate — structural checks over the loaded arrays.
eco_conf_validate() {
    ((${#ECO_CONF_BINS[@]})) || { warn "eco.conf is empty"; return 1; }
    local i j ch def bin pkg flag
    for i in "${!ECO_CONF_BINS[@]}"; do
        ch="${ECO_CONF_CHANNELS[i]}"
        def="${ECO_CONF_DEFAULTS[i]}"
        bin="${ECO_CONF_BINS[i]}"
        pkg="${ECO_CONF_PKGS[i]}"
        flag="${ECO_CONF_FLAGS[i]}"
        case "$ch" in
            node|py|go|rust) ;;
            *) warn "eco.conf entry '$bin': channel must be node, py, go or rust, got '$ch'"; return 1 ;;
        esac
        case "$def" in
            y|n) ;;
            *) warn "eco.conf entry '$bin': default must be y or n, got '$def'"; return 1 ;;
        esac
        # A bin becomes a path under ECO_BIN_DIR and an argument to rm, so
        # separators and dot-only names are refused here, at validation.
        [[ -n "$bin" && "$bin" != *" "* && "$bin" != */* && "$bin" != . && "$bin" != .. ]] \
            || { warn "eco.conf entry '$bin': bin must be non-empty, with no spaces, slashes or dots-only names"; return 1; }
        [[ -n "$pkg" && "$pkg" != *" "* ]] \
            || { warn "eco.conf entry '$bin': pkg must be non-empty and contain no spaces"; return 1; }
        [[ "$flag" != *" "* ]] \
            || { warn "eco.conf entry '$bin': flag must not contain spaces"; return 1; }
        for (( j = 0; j < i; j++ )); do
            [[ "${ECO_CONF_BINS[j]}" == "$bin" ]] \
                && { warn "eco.conf: duplicate bin '$bin'"; return 1; }
            [[ "${ECO_CONF_PKGS[j]}" == "$pkg" ]] \
                && { warn "eco.conf: duplicate pkg '$pkg'"; return 1; }
        done
    done
    return 0
}

# eco_conf_filter_channel <channel> — narrows the arrays to one channel's rows.
# Guards on possibly-empty arrays are not cosmetic: bash < 4.4 reads an empty
# expansion under `set -u` as an unbound variable, and CI runs macOS bash 3.2.
#
# An unknown channel is refused instead of being filtered to nothing. An empty
# result is indistinguishable from "this channel has no rows" — rust genuinely
# has none — so a typo would silently disable a whole channel.
eco_conf_filter_channel() {
    local want="$1" i
    case "$want" in
        node|py|go|rust) ;;
        *) warn "eco_conf_filter_channel: unknown channel '$want'"; return 1 ;;
    esac
    local -a c=() b=() p=() f=() d=()
    for i in "${!ECO_CONF_BINS[@]}"; do
        [[ "${ECO_CONF_CHANNELS[i]}" == "$want" ]] || continue
        c+=("${ECO_CONF_CHANNELS[i]}")
        b+=("${ECO_CONF_BINS[i]}")
        p+=("${ECO_CONF_PKGS[i]}")
        f+=("${ECO_CONF_FLAGS[i]}")
        d+=("${ECO_CONF_DEFAULTS[i]}")
    done
    if (( ${#c[@]} > 0 )); then
        ECO_CONF_CHANNELS=("${c[@]}")
        ECO_CONF_BINS=("${b[@]}")
        ECO_CONF_PKGS=("${p[@]}")
        ECO_CONF_FLAGS=("${f[@]}")
        ECO_CONF_DEFAULTS=("${d[@]}")
    else
        ECO_CONF_CHANNELS=()
        ECO_CONF_BINS=()
        ECO_CONF_PKGS=()
        ECO_CONF_FLAGS=()
        ECO_CONF_DEFAULTS=()
    fi
}

# ── Shared per-item manifest install ────────────────────────────
# eco_manifest_install <installer_fn> <channel> <detect>
# Walks this channel's conf rows, asks per missing tool (conf default), then
# installs the approved batch. -y takes every missing row; non-interactive runs
# apply the conf defaults. A dry run does not ask: it plans with the defaults
# (or the -y selection) and executes nothing. A failed row warns and continues;
# the aggregate exit code reports any failure.
eco_manifest_install() {
    local installer="$1" channel="$2" detect="${3:-canonical}"
    case "$detect" in
        canonical|path) ;;
        *) warn "eco_manifest_install: detect must be 'canonical' or 'path', got '$detect'"; return 1 ;;
    esac
    local i bin pkg flag def path reply want what
    local -a sel_bins=() sel_pkgs=() sel_flags=()
    for i in "${!ECO_CONF_BINS[@]}"; do
        bin="${ECO_CONF_BINS[i]}"
        pkg="${ECO_CONF_PKGS[i]}"
        flag="${ECO_CONF_FLAGS[i]}"
        def="${ECO_CONF_DEFAULTS[i]}"
        path="$ECO_BIN_DIR/$bin"
        if [[ "$detect" == "path" ]]; then
            if is_installed "$bin" "$path"; then
                info "$bin already installed; skipping"
                continue
            fi
        else
            if [[ -x "$path" ]]; then
                info "$bin already installed; skipping"
                continue
            fi
        fi
        # A dry run promises no mutation; it must not clear stale entries.
        if [[ -z "${ECO_DRY_RUN:-}" ]]; then
            clean_stale_installs "$path"
        fi
        want=0
        if [[ -n "${ECO_ASSUME_YES:-}" ]]; then
            want=1
        elif [[ -n "${DOTFILES_NON_INTERACTIVE:-}" || -n "${ECO_DRY_RUN:-}" ]]; then
            # A dry run cannot collect answers; it plans with the conf
            # defaults, the same policy as a non-interactive run.
            [[ "$def" == "y" ]] && want=1
        else
            if [[ "$def" == "y" ]]; then
                read -rp "$bin not found; install it via $channel? [Y/n]: " reply || reply=""
                [[ -z "$reply" || "$reply" =~ ^[Yy](es)?$ ]] && want=1
            else
                read -rp "$bin not found; install it via $channel? [y/N]: " reply || reply=""
                [[ "$reply" =~ ^[Yy](es)?$ ]] && want=1
            fi
        fi
        (( want )) || continue
        sel_bins+=("$bin")
        sel_pkgs+=("$pkg")
        sel_flags+=("$flag")
    done
    if (( ${#sel_bins[@]} == 0 )); then
        info "no missing $channel CLIs selected; nothing to install"
        return 0
    fi
    if [[ -n "${ECO_DRY_RUN:-}" ]]; then
        for i in "${!sel_bins[@]}"; do
            what="${sel_bins[i]} (${sel_pkgs[i]})"
            [[ -n "${sel_flags[i]}" ]] && what="$what [${sel_flags[i]}]"
            info "would install $what via $channel"
        done
        if [[ -n "${ECO_ASSUME_YES:-}" ]]; then
            info "dry run: no action taken"
        else
            info "dry run: no action taken (asked nothing; planned with eco.conf defaults)"
        fi
        return 0
    fi
    local rc=0
    for i in "${!sel_bins[@]}"; do
        info "installing ${sel_bins[i]} (${sel_pkgs[i]}) via $channel..."
        if ! "$installer" "${sel_bins[i]}" "${sel_pkgs[i]}" "${sel_flags[i]}"; then
            warn "${sel_bins[i]} install failed; retry manually later"
            rc=1
            continue
        fi
        # Same rule as eco.sh's named install: an exit code says the command
        # ran, not that a binary appeared. Every channel lands its bin in
        # ECO_BIN_DIR, so the filesystem decides.
        if [[ ! -x "$ECO_BIN_DIR/${sel_bins[i]}" ]]; then
            error_msg "${sel_bins[i]} was not installed: no executable at $ECO_BIN_DIR/${sel_bins[i]}"
            info "the package may not ship a '${sel_bins[i]}' command; check the manifest entry"
            rc=1
            continue
        fi
        ok "${sel_bins[i]} installed"
    done
    return "$rc"
}

# ── Channel dispatch (the CLI shape every channel shares) ───────
# The four channel scripts are one program with different per-action
# functions: same verbs, same argument guards, same exit codes. A channel
# supplies function names and keeps only what is its own.
#
# Exit codes, for every channel script:
#   0  success (a missing runtime during --install-manifest is a clean skip)
#   1  failure
#   2  usage error
#   3  runtime unavailable, nothing executed (one-shot verbs only, so a caller
#      can tell "skipped" from "completed")
#
#   channel_dispatch <conf_channel> <ensure> <install-one> <update-one> \
#                    <uninstall-one> <list> <installed> <outdated> <manifest> \
#                    [verb…]
#
# Passed positionally because bash 3.2 has no namerefs.
#
# The manifest is loaded here, after the help guard, rather than at channel
# source time: a broken eco.conf is exactly when the usage text is worth
# reading, so --help must not depend on it. Every other verb does.
CHANNEL_VERBS='--list, --installed, --outdated, --install-manifest, --install-one, --update-one, --uninstall-one'

channel_usage() {
    printf 'usage: %s %s | -h|--help\n' "${0##*/}" "$CHANNEL_VERBS"
}

# shellcheck disable=SC2034  # ECO_READ_ONLY / ECO_MACHINE_OUTPUT feed msg() in common.sh
channel_dispatch() {
    local conf_channel="$1"
    local ensure="$2" act_install="$3" act_update="$4" act_uninstall="$5"
    local act_list="$6" act_installed="$7" act_outdated="$8" act_manifest="$9"
    shift 9
    local verb="${1:-}"

    case "$verb" in
        ""|-h|--help)
            channel_usage
            return 0
            ;;
    esac

    # Every other verb reads the manifest (manifest install walks it; the
    # installed/list snapshot translates pkg→bin through it).
    eco_conf_load || return 1
    eco_conf_filter_channel "$conf_channel" || return 1

    case "$verb" in
        # Read-only verbs probe, they never prepare a runtime: `fnm install`
        # or `go env -w` just to list versions would be a side effect nobody
        # asked for.
        --list)
            ECO_READ_ONLY=1
            ECO_MACHINE_OUTPUT=1
            "$ensure" || return 1
            "$act_list" || return 1
            return 0
            ;;
        --installed)
            ECO_READ_ONLY=1
            ECO_MACHINE_OUTPUT=1
            "$ensure" || return 1
            "$act_installed" || return 1
            return 0
            ;;
        --outdated)
            ECO_READ_ONLY=1
            ECO_MACHINE_OUTPUT=1
            "$ensure" || return 1
            "$act_outdated"
            return $?
            ;;
        --install-manifest)
            # A missing runtime is a clean skip here: bootstrap runs this on
            # every machine, including ones without a given toolchain.
            # A dry run plans from the manifest and the filesystem only.
            if [[ -z "${ECO_DRY_RUN:-}" ]]; then
                "$ensure" || return 0
            fi
            "$act_manifest"
            return $?
            ;;
        --install-one|--update-one|--uninstall-one)
            shift
            (($# >= 2)) || { warn "usage: ${0##*/} $verb <bin> <pkg> [flag]"; return 2; }
            # 3, not 0: an explicit one-shot request must not be reported as
            # completed when the runtime was never there.
            "$ensure" || return 3
            case "$verb" in
                --install-one)   "$act_install"   "$1" "$2" "${3:-}" ;;
                --update-one)    "$act_update"    "$1" "$2" "${3:-}" ;;
                --uninstall-one) "$act_uninstall" "$1" "$2" "${3:-}" ;;
            esac
            return $?
            ;;
        *)
            # 1, not 2: the verb itself is wrong. 2 stays reserved for "right
            # verb, unusable arguments" (the one-shot guard above).
            warn "unknown option '$verb' (supported: $CHANNEL_VERBS, -h|--help)"
            return 1
            ;;
    esac
}

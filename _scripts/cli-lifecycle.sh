#!/usr/bin/env bash
# _scripts/cli-lifecycle.sh — the CLI lifecycle engine shared by the
# npm/uv/go/cargo channels and the unified eco entrypoint.
#
# Sourced (never executed). Layering:
#   _scripts/common.sh        — generic shell infrastructure (output, prompts…)
#   _scripts/cli-lifecycle.sh — this file: conf loading/validation, install
#                               detection, outdated-query plumbing, and the
#                               shared per-item manifest-install loop
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
CLI_BIN_DIR="$HOME/.local/bin"

# ── Pre-approval ────────────────────────────────────────────────
# DOTFILES_ACCEPT_TOOLS — user intent: auto-approve this bin everywhere
#                         (space-separated bin names)
# DOTFILES_ACCEPT_INSTALLS is the pre-rename spelling; it still works but warns
# once so the name can be retired.
is_pre_approved() {
    local bin="$1"
    if [[ -z "${DOTFILES_ACCEPT_TOOLS:-}" && -n "${DOTFILES_ACCEPT_INSTALLS:-}" \
          && -z "${_DOTFILES_ACCEPT_INSTALLS_WARNED:-}" ]]; then
        warn "DOTFILES_ACCEPT_INSTALLS is deprecated; use DOTFILES_ACCEPT_TOOLS"
        _DOTFILES_ACCEPT_INSTALLS_WARNED=1
    fi
    case " ${DOTFILES_ACCEPT_TOOLS:-${DOTFILES_ACCEPT_INSTALLS:-}} " in
        *" $bin "*) return 0 ;;
    esac
    return 1
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

# ── Outdated-query plumbing ─────────────────────────────────────
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

# ── Manifest configuration (eco.conf) ───────────────────────────
# Format per row: <渠道> <默认y|n> <bin> <pkg> [flag]
#   渠道: node | py | go | rust (user-facing vocabulary)
#   默认: y = install pre-selected, n = pre-skipped (confirm can flip)
#   bin : identity key — detection, prompts, DOTFILES_ACCEPT_TOOLS all use it
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
# channels, bad defaults, empty/duplicate bins or pkgs, flags with spaces.
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
        [[ -n "$bin" && "$bin" != *" "* ]] \
            || { warn "eco.conf entry '$bin': bin must be non-empty and contain no spaces"; return 1; }
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
# Empty-result guards are required throughout: bash < 4.4 treats an empty
# array expansion under `set -u` as an unbound variable (macOS system bash is
# 3.2, which CI's macos-latest runner uses).
eco_conf_filter_channel() {
    local want="$1" i
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
# Walks the conf rows (already filtered to this channel), confirms each
# missing tool with a [Y/n]/[y/N] default from ECO_CONF_DEFAULTS, then
# installs every approved row. Answers are collected first, then executed
# (batch). Already-installed rows are shown as skipped. Pre-approved bins
# (DOTFILES_ACCEPT_TOOLS) skip the question. Non-interactive runs apply the
# conf defaults silently. A failed row warns and continues; the aggregate
# exit code reports any failure.
eco_manifest_install() {
    local installer="$1" channel="$2" detect="${3:-canonical}"
    case "$detect" in
        canonical|path) ;;
        *) warn "eco_manifest_install: detect must be 'canonical' or 'path', got '$detect'"; return 1 ;;
    esac
    local i bin pkg flag def path reply want
    local -a sel_bins=() sel_pkgs=() sel_flags=()
    for i in "${!ECO_CONF_BINS[@]}"; do
        bin="${ECO_CONF_BINS[i]}"
        pkg="${ECO_CONF_PKGS[i]}"
        flag="${ECO_CONF_FLAGS[i]}"
        def="${ECO_CONF_DEFAULTS[i]}"
        path="$CLI_BIN_DIR/$bin"
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
        clean_stale_installs "$path"
        want=0
        if is_pre_approved "$bin"; then
            want=1
        elif [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
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
    local rc=0
    for i in "${!sel_bins[@]}"; do
        info "installing ${sel_bins[i]} (${sel_pkgs[i]}) via $channel..."
        if ! "$installer" "${sel_bins[i]}" "${sel_pkgs[i]}" "${sel_flags[i]}"; then
            warn "${sel_bins[i]} install failed; retry manually later"
            rc=1
            continue
        fi
        ok "${sel_bins[i]} installed"
    done
    return "$rc"
}

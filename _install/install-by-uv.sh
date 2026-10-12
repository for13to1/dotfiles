#!/usr/bin/env bash
# _install/install-by-uv.sh — Python CLI lifecycle (install/upgrade/uninstall) via uv tool

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-lifecycle.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-registry.sh"
cli_registry_filter_channel uv

find_uv_bin() {
    if command -v uv &>/dev/null; then
        command -v uv
    elif [[ -x "$HOME/.local/bin/uv" ]]; then
        printf '%s\n' "$HOME/.local/bin/uv"
    fi
}

# Channel runtime gate: a missing uv skips every verb cleanly.
uv_ensure() {
    if [[ -z "$(find_uv_bin || true)" ]]; then
        warn "uv not found; skipping Python CLI lifecycle"
        return 1
    fi
}

# The single uv-channel installer. uv tool install needs no per-tool flags
# today, so the flag slot is reserved for future use.
uv_install_one() {
    local uv_bin
    uv_bin="$(find_uv_bin)" || return 1
    "$uv_bin" tool install "$2"
}

# The single uv-channel upgrader: uv owns its tool environments, so upgrades
# go through its native verb instead of reinstalling. The flag is reserved.
uv_update_one() {
    local uv_bin
    uv_bin="$(find_uv_bin)" || return 1
    "$uv_bin" tool upgrade "$2"
}

# The single uv-channel uninstaller, again via uv's native verb.
uv_uninstall_one() {
    local uv_bin
    uv_bin="$(find_uv_bin)" || return 1
    "$uv_bin" tool uninstall "$2"
}

# One batch query via `uv tool list --outdated` (text form, no --json). The
# parse depends on that form; if uv changes it, we detect the drift instead of
# reporting "up to date". A failed query is captured explicitly. stdout is the
# result channel, so warn goes to stderr.
uv_query_outdated() {
    local uv_bin listed rc=0 parsed
    uv_bin="$(find_uv_bin)" || return 1
    listed="$("$uv_bin" tool list --outdated 2>/dev/null)" || rc=$?
    if (( rc != 0 )); then
        warn "uv tool list --outdated failed (exit $rc); skipping uv tool updates" >&2
        return 1
    fi
    parsed="$(awk '$1 !~ /^-/ && match($0, /\[latest: [^]]+\]/) {
              latest = substr($0, RSTART + 9, RLENGTH - 10)
              cur = $2
              sub(/^v/, "", cur)
              print $1, cur, latest
          }' <<<"$listed")"
    # Shape check: a row's current/latest must both look like versions
    # (digits separated by dots, optional leading v). A field-shifted format
    # change would otherwise feed garbage in as a version and "update" to it.
    local row bad=0
    while IFS= read -r row; do
        [[ -n "$row" ]] || continue
        if [[ ! "$row" =~ ^[^[:space:]]+\ v?[0-9]+([.][0-9]+)+\ v?[0-9]+([.][0-9]+)+$ ]]; then
            bad=1
        fi
    done <<<"$parsed"
    if (( bad )); then
        warn "uv tool list --outdated format not understood; skipping uv tool updates" >&2
        return 1
    fi
    # Drift guard: uv prints nothing only when nothing is outdated. Any
    # non-empty output we cannot parse (marker gone, fields shifted) must fail
    # loudly — never collapse into a false "up to date".
    if [[ -n "$listed" && -z "$parsed" ]]; then
        warn "uv tool list --outdated format not understood; skipping uv tool updates" >&2
        return 1
    fi
    [[ -n "$parsed" ]] && printf '%s\n' "$parsed"
    return 0
}

# ── uv CLI registry ──────────────────────────────────────────────
# Declarations live in _scripts/cli-registry.sh; only uv's rows are kept here.

main() {
    run_cli_channel uv_ensure uv_install_one uv_query_outdated \
        uv_update_one uv_uninstall_one "uv tool" "$(channel_detect uv)" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

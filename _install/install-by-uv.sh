#!/usr/bin/env bash
# _install/install-by-uv.sh — Python CLI lifecycle (install/upgrade/uninstall) via uv tool

# The CLI shape (verbs, argument guards, exit codes) is channel_dispatch in
# _scripts/cli-lifecycle.sh; this file only supplies the uv-specific parts.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-lifecycle.sh"
# eco_conf_load/filter run inside channel_dispatch, after the help
# guard: a broken manifest must not take `--help` away.

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

# The single uv-channel installer. The flag slot is reserved.
# eco does not pin versions, so the package spec is passed through untouched;
# uv resolves it. (A user-supplied `pkg@ver` is refused in eco.sh, because uv
# would read it as a local path.)
uv_install_one() {
    local uv_bin
    uv_bin="$(find_uv_bin)" || return 1
    "$uv_bin" tool install "$2"
}

# The single uv-channel upgrader: uv owns its tool environments, so upgrades
# go through its native verb instead of reinstalling. The flag is reserved.
# An already-pinned tool (installed by hand with `uv tool install pkg==x`) is
# left alone by `uv tool upgrade`; that is uv's business, not eco's.
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

# A version as uv prints it: optional leading v, then a PEP 440 release segment
# with optional pre/post/dev/local parts (0.18.0rc1, 1.2.3.post1, 0.9.0.dev0).
# The shape check exists to reject garbage, not to reject legal versions.
UV_VERSION_RE='^v?[0-9]+([.][0-9]+)+([-.]?((a|b|rc|alpha|beta|pre|preview|post|dev)[.]?[0-9]*))*([+][0-9A-Za-z.-]+)?$'

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
        read -r _name _cur _latest <<<"$row"
        if [[ ! "$_cur" =~ $UV_VERSION_RE || ! "$_latest" =~ $UV_VERSION_RE ]]; then
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

# ── list mode ───────────────────────────────────────────────────
# Read-only: emit "pkg version latest_or_?" rows for the whole tool list.
# `uv tool list` prints a header per tool followed by its executables as
# "- <exe>" lines; those are the on-disk identity and are kept as aliases.
uv_list_installed() {
    local uv_bin listed
    uv_bin="$(find_uv_bin)" || return 1
    listed="$("$uv_bin" tool list 2>/dev/null)" || return 1
    awk '
        $1 !~ /^-/ && $2 ~ /^v[0-9]/ {
            if (name != "") print name, ver, exes
            name = $1
            ver = $2
            sub(/^v/, "", ver)
            exes = ""
            next
        }
        $1 == "-" && name != "" {
            exes = (exes == "" ? $2 : exes " " $2)
        }
        END { if (name != "") print name, ver, exes }
    ' <<<"$listed"
}

# "tool version [executables]" → "bin version tool executables". The key is
# the manifest bin (or the tool name), the package is the tool, and the
# executables are the disk witnesses (python-lsp-server → pylsp).
uv_installed_by_bin() {
    local rows pkg ver exes i bin
    # Read first, then loop: piping into `while` would make the pipeline status
    # the loop's (always 0) and turn a failed listing into "nothing installed".
    rows="$(uv_list_installed)" || return 1
    while read -r pkg ver exes; do
        [[ -n "$pkg" ]] || continue
        bin="$pkg"
        for i in "${!ECO_CONF_PKGS[@]}"; do
            if [[ "${ECO_CONF_PKGS[i]}" == "$pkg" ]]; then
                bin="${ECO_CONF_BINS[i]}"
                break
            fi
        done
        printf '%s %s %s %s\n' "$bin" "$ver" "$pkg" "${exes:-}"
    done <<<"$rows"
}

uv_list_rows() {
    local installed_rows latest_rows="" outdated_out="" outdated_rc=0 query_failed=0
    if ! installed_rows="$(uv_list_installed 2>/dev/null)"; then
        warn "uv tool list failed; cannot list Python CLIs" >&2
        return 1
    fi
    [[ -n "$installed_rows" ]] || return 0
    outdated_out="$(uv_query_outdated 2>/dev/null)" || outdated_rc=$?
    (( outdated_rc == 0 )) || query_failed=1
    if (( ! query_failed )) && [[ -n "$outdated_out" ]]; then
        # outdated rows are "pkg cur latest"; reduce to "pkg latest".
        latest_rows="$(awk '{ print $1, $3 }' <<<"$outdated_out")"
    fi
    if (( query_failed )); then
        awk 'NF >= 2 { print $1, $2, "?" }' <<<"$installed_rows"
    elif [[ -z "$latest_rows" ]]; then
        awk 'NF >= 2 { print $1, $2, $2 }' <<<"$installed_rows"
    else
        awk '
            NR == FNR { latest[$1] = $2; next }
            NF >= 2 { print $1, $2, ($1 in latest ? latest[$1] : $2) }
        ' <(printf '%s\n' "$latest_rows") <(printf '%s\n' "$installed_rows")
    fi
    return 0
}

# ── dispatch ────────────────────────────────────────────────────
main() {
    channel_dispatch py \
        uv_ensure uv_install_one uv_update_one uv_uninstall_one \
        uv_list_rows uv_installed_by_bin uv_query_outdated uv_manifest_install \
        "$@"
}

# install every selected eco.conf row for this channel.
uv_manifest_install() {
    eco_manifest_install uv_install_one "uv tool" "$(channel_detect uv)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

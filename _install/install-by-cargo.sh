#!/usr/bin/env bash
# _install/install-by-cargo.sh — Rust CLI lifecycle (install/upgrade/uninstall) via Cargo

# The CLI shape (verbs, argument guards, exit codes) is channel_dispatch in
# _scripts/cli-lifecycle.sh; this file only supplies the cargo-specific parts.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-lifecycle.sh"
eco_conf_load
eco_conf_filter_channel rust

# cargo installs into a --root prefix; derive it from CLI_BIN_DIR so the two
# paths cannot drift apart (same trick as npm's LOCAL_PREFIX).
CARGO_ROOT="${CLI_BIN_DIR%/*}"

find_cargo_bin() {
    command -v cargo
}

# Channel runtime gate: a missing cargo skips every verb cleanly.
cargo_ensure() {
    if [[ -z "$(find_cargo_bin || true)" ]]; then
        warn "cargo not found; skipping Rust CLI lifecycle"
        return 1
    fi
}

# The single cargo-channel installer. The flag slot is reserved for future use.
cargo_install_one() {
    local cargo_bin
    cargo_bin="$(find_cargo_bin)" || return 1
    if [[ -z "$3" ]]; then
        "$cargo_bin" install --root "$CARGO_ROOT" "$2"
    else
        "$cargo_bin" install --root "$CARGO_ROOT" "$3" "$2"
    fi
}

# The single cargo-channel upgrader: --force reinstalls the latest version.
cargo_update_one() {
    local cargo_bin
    cargo_bin="$(find_cargo_bin)" || return 1
    if [[ -z "$3" ]]; then
        "$cargo_bin" install --force --root "$CARGO_ROOT" "$2"
    else
        "$cargo_bin" install --force --root "$CARGO_ROOT" "$3" "$2"
    fi
}

# The single cargo-channel uninstaller, via cargo's native verb.
cargo_uninstall_one() {
    local cargo_bin
    cargo_bin="$(find_cargo_bin)" || return 1
    "$cargo_bin" uninstall --root "$CARGO_ROOT" "$2"
}

# A crate version as cargo prints it: optional leading v, then a release
# segment with optional pre-release/build parts (14.1.1-rc.1, 1.0.0-beta.2).
# The shape check exists to reject garbage, not to reject legal versions.
CARGO_VERSION_RE='^v?[0-9]+([.][0-9]+)+([-+][0-9A-Za-z.-]+)?$'

# Parse `cargo install --list --root <prefix>` into "crate version" rows.
# Output shape:
#   ripgrep v14.1.0:
#       rg
#   bat v0.24.0:
#       bat
# Non-indented "name vX.Y.Z:" lines are crate headers; indented lines are bins.
cargo_list_installed() {
    local cargo_bin listed rc=0
    cargo_bin="$(find_cargo_bin)" || return 1
    listed="$("$cargo_bin" install --list --root "$CARGO_ROOT" 2>/dev/null)" || rc=$?
    (( rc == 0 )) || return 1
    awk '$1 !~ /^[[:space:]]/ && $2 ~ /^v[0-9]/ {
        name = $1
        ver = $2
        sub(/^v/, "", ver)
        sub(/:$/, "", ver)
        print name, ver
    }' <<<"$listed"
}

# Latest version of a crate via `cargo search --limit 1`. The output shape is
# `name = "X.Y.Z"  # description`; a shape change is caught instead of feeding
# garbage versions into an upgrade.
cargo_search_latest() {
    local cargo_bin crate raw latest
    cargo_bin="$(find_cargo_bin)" || return 1
    crate="$1"
    raw="$("$cargo_bin" search "$crate" --limit 1 2>/dev/null)" || return 1
    # First line: `crate = "X.Y.Z"` — match exactly so a different crate or a
    # deprecation note never leaks through.
    latest="$(awk -v c="$crate" '
        $1 == c && $2 == "=" && $3 ~ /^"[0-9]/ {
            gsub(/"/, "", $3)
            print $3
            exit
        }
    ' <<<"$raw")"
    [[ -n "$latest" ]] || return 1
    [[ "$latest" =~ $CARGO_VERSION_RE ]] || return 1
    printf '%s\n' "$latest"
}

# One batch outdated query: installed crates × latest via cargo search.
# A failed listing fails the query — collapsing it into "no crates" would
# report a broken cargo as "all up to date". A failed search for any crate
# also fails the query (never a silent "up to date").
cargo_query_outdated() {
    local name cur latest line bad=0 listed
    local -a installed=()
    if ! listed="$(cargo_list_installed)"; then
        warn "cargo install --list failed; cannot read Rust CLI state" >&2
        return 1
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] && installed+=("$line")
    done <<<"$listed"
    (( ${#installed[@]} > 0 )) || return 0
    for line in "${installed[@]}"; do
        read -r name cur <<<"$line"
        if ! latest="$(cargo_search_latest "$name")"; then
            bad=1
            continue
        fi
        [[ "$latest" != "$cur" ]] || continue
        printf '%s %s %s\n' "$name" "$cur" "$latest"
    done
    if (( bad )); then
        warn "cargo search failed for at least one crate; skipping cargo updates" >&2
        return 1
    fi
}

# ── --list mode ─────────────────────────────────────────────────
# Read-only: emit "pkg version latest_or_?" rows for the whole prefix.
# A failed latest query degrades to "?" per crate; a failed listing returns 1
# so the caller reports it rather than treating the channel as empty.
cargo_list_rows() {
    local name cur latest line listed
    local -a installed=()
    if ! listed="$(cargo_list_installed)"; then
        warn "cargo install --list failed; cannot list Rust CLIs" >&2
        return 1
    fi
    while IFS= read -r line; do
        [[ -n "$line" ]] && installed+=("$line")
    done <<<"$listed"
    (( ${#installed[@]} > 0 )) || return 0
    for line in "${installed[@]}"; do
        read -r name cur <<<"$line"
        latest="$(cargo_search_latest "$name" 2>/dev/null)" || latest="?"
        printf '%s %s %s\n' "$name" "$cur" "$latest"
    done
}

# ── dispatch ────────────────────────────────────────────────────
main() {
    channel_dispatch \
        cargo_ensure cargo_install_one cargo_update_one cargo_uninstall_one \
        cargo_list_rows cargo_list_installed cargo_query_outdated cargo_manifest_install \
        "$@"
}

# install every selected eco.conf row for this channel.
cargo_manifest_install() {
    eco_manifest_install cargo_install_one rust "$(channel_detect cargo)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

#!/usr/bin/env bash
# _install/install-by-go.sh — Go CLI lifecycle (install/upgrade/uninstall) via `go install`
#
# Toolchain comes from the package manager; this channel pins GOBIN and
# GOMODCACHE in GOENV and installs the Go editor tools (gopls, gofumpt) into
# the shared ~/.local/bin CLI prefix.

# The CLI shape (verbs, argument guards, exit codes) is channel_dispatch in
# _scripts/cli-lifecycle.sh; this file only supplies the go-specific parts.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-lifecycle.sh"
eco_conf_load
eco_conf_filter_channel go

# Go layout declared by this repo: GOBIN is the shared ~/.local/bin prefix
# (CLI_BIN_DIR from common.sh), and GOMODCACHE lives under ~/.cache instead of
# Go's default ~/go/pkg/mod. GOPATH is left alone — GOBIN and GOMODCACHE take
# over its only remaining roles in module mode.
GO_LAYOUT=(
    "GOBIN=$CLI_BIN_DIR"
    "GOMODCACHE=$HOME/.cache/go-mod"
)

find_go_bin() {
    command -v go
}

# Declare the layout in the user-level GOENV (`go env GOENV`). The dotfiles
# are the source of truth, so values are written unconditionally; a value the
# user actually set (persisted in GOENV or exported) is reported when it
# differs, while Go's built-in defaults are never reported. `go env -w` is
# idempotent and a failed write only warns — installs target CLI_BIN_DIR anyway.
ensure_go_layout() {
    local go_bin env_file pair key want cur
    go_bin="$(find_go_bin)" || return 1
    env_file="$("$go_bin" env GOENV 2>/dev/null || true)"

    for pair in "${GO_LAYOUT[@]}"; do
        key="${pair%%=*}"
        want="${pair#*=}"

        # A value already persisted in GOENV is real user config.
        cur=""
        if [[ -n "$env_file" && -f "$env_file" ]]; then
            cur="$(sed -n "s/^$key=//p" "$env_file" | tail -n 1)"
        fi
        if [[ -n "$cur" && "$cur" != "$want" ]]; then
            warn "$key=$cur in $env_file; replacing it with $want"
        fi

        # An exported value wins over GOENV; report it instead.
        if [[ -n "${!key:-}" && "${!key}" != "$want" ]]; then
            warn "$key=${!key} is exported in this shell; go env -w will not override it"
        fi
    done

    "$go_bin" env -w "${GO_LAYOUT[@]}" \
        || warn "go env -w failed; the Go layout may not be persisted"
}

# Channel runtime gate: Go must be present; the layout write belongs to the
# channel contract, so it runs for every mutation verb (idempotent, warn-only
# on write). Read-only verbs must not persist anything.
go_ensure() {
    if [[ -z "$(find_go_bin || true)" ]]; then
        warn "go not found; skipping Go CLI lifecycle"
        return 1
    fi
    [[ -n "${CLI_READ_ONLY:-}" ]] && return 0
    ensure_go_layout
}

# The single go-channel installer. @latest is the channel default: eco does not
# pin versions, so a user-supplied pin is refused before reaching here.
# The flag slot is reserved.
go_install_one() {
    local go_bin
    go_bin="$(find_go_bin)" || return 1
    GOBIN="$CLI_BIN_DIR" "$go_bin" install "$2@latest"
}

# go has no separate upgrade verb: reinstalling at @latest is the upgrade, and
# it writes the same GOBIN binary. One implementation, two entry points.
go_update_one() {
    go_install_one "$@"
}

# The go-channel uninstaller: `go install` only writes GOBIN binaries, so
# removal deletes the binary; the shared GOMODCACHE is left alone.
#
# CLI_BIN_DIR is shared with every other channel, so the file here might be
# npm's, uv's, or a hand-placed script. Only delete a file that carries Go
# module metadata, and name where a foreign install actually lives.
go_uninstall_one() {
    local bin="$1" target="$CLI_BIN_DIR/$1" go_bin meta found
    if [[ ! -x "$target" ]]; then
        found="$(command -v "$bin" 2>/dev/null || true)"
        if [[ -n "$found" ]]; then
            warn "$bin is not in $CLI_BIN_DIR; it is installed at $found (not managed by eco)"
        else
            warn "$bin not found in $CLI_BIN_DIR; nothing was removed"
        fi
        return 1
    fi
    go_bin="$(find_go_bin)" || return 1
    meta="$("$go_bin" version -m "$target" 2>/dev/null)" || meta=""
    if ! grep -qE '^[[:space:]]+mod[[:space:]]' <<<"$meta"; then
        warn "$bin in $CLI_BIN_DIR is not a Go binary; refusing to remove it"
        return 1
    fi
    rm -f "$target"
}

# ── domain-wide prefix scan ─────────────────────────────────────
# Scan every executable in CLI_BIN_DIR for embedded Go module metadata.
# Emits "pkg_path mod_path current" rows. pkg_path is the binary's package
# path (from the `path` line — what `go install` was given); mod_path is the
# owning module (from the first `mod` line — the main module). Non-Go
# binaries have no metadata and are skipped silently.
go_scan_prefix() {
    local go_bin f meta mod_path cur pkg_path
    go_bin="$(find_go_bin)" || return 1
    local -a bins=()
    for f in "$CLI_BIN_DIR"/*; do
        [[ -x "$f" && ! -d "$f" ]] && bins+=("$f")
    done
    (( ${#bins[@]} > 0 )) || return 0
    # One `go version -m` for the whole prefix, not one process per file.
    # Output is a "<path>: go1.x" header per file, then tab-indented fields.
    # A non-Go file makes the command exit non-zero while still printing every
    # readable file, so a non-zero status is no reason to discard the output;
    # only an empty result falls back to one file at a time.
    meta="$("$go_bin" version -m "${bins[@]}" 2>/dev/null)" || true
    if [[ -z "$meta" ]]; then
        for f in "${bins[@]}"; do
            local one
            one="$("$go_bin" version -m "$f" 2>/dev/null)" || continue
            meta+="$one"$'\n'
        done
    fi
    # No metadata for any candidate is normal: the shared prefix is mostly
    # npm/uv output, which carries none. A broken toolchain looks identical
    # from here, so probe it once before calling that "nothing installed".
    if [[ -z "$meta" ]] && ! "$go_bin" version >/dev/null 2>&1; then
        warn "go is not working; cannot read Go CLI state" >&2
        return 1
    fi
    [[ -n "$meta" ]] || return 0

    local cur_file="" path_of_file=""
    while IFS= read -r line; do
        case "$line" in
            /*:*)   # "<path>: go1.x" starts a new file section
                cur_file="${line%:*}"
                path_of_file=""
                ;;
            *$'\t'path$'\t'*)
                path_of_file="$(printf '%s' "$line" | awk '{ print $2; exit }')"
                ;;
            *$'\t'mod$'\t'*)
                mod_path="$(printf '%s' "$line" | awk '{ print $2; exit }')"
                cur="$(printf '%s' "$line" | awk '{ print $3; exit }')"
                [[ -n "$mod_path" && -n "$cur" ]] || continue
                pkg_path="${path_of_file:-$mod_path}"
                printf '%s %s %s %s\n' "$pkg_path" "$mod_path" "$cur" "$cur_file"
                ;;
        esac
    done <<<"$meta"
}

# One batch outdated query over the whole prefix: current versions from the
# binaries' embedded metadata, latest from the module proxy. Rows without
# embedded metadata are skipped; a failed lookup fails the query.
# stdout is the result channel, so warn goes to stderr.
go_query_outdated() {
    local go_bin line pkg_path mod_path cur latest listed row
    local -a targets=() rows=()
    go_bin="$(find_go_bin)" || return 1

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        read -r pkg_path mod_path cur _file <<<"$line"
        case " ${targets[*]:-} " in
            *" $mod_path@latest "*) ;;
            *) targets+=("$mod_path@latest") ;;
        esac
        rows+=("$pkg_path $mod_path $cur")
    done < <(go_scan_prefix)

    (( ${#targets[@]} > 0 )) || return 0
    if ! listed="$("$go_bin" list -m -f '{{.Path}} {{.Version}}' "${targets[@]}" 2>/dev/null)"; then
        warn "go list -m failed; skipping updates" >&2
        return 1
    fi

    for row in "${rows[@]}"; do
        read -r pkg_path mod_path cur <<<"$row"
        latest="$(awk -v p="$mod_path" '$1 == p { print $2; exit }' <<<"$listed")"
        [[ -n "$latest" && "$latest" != "$cur" ]] || continue
        printf '%s %s %s\n' "$pkg_path" "$cur" "$latest"
    done
}

# ── list mode ───────────────────────────────────────────────────
# Read-only: emit "pkg version latest_or_?" rows for every Go binary in the
# prefix. A failed module-proxy query degrades latest to "?"; list is lenient.
# "bin version" for every Go binary in the prefix. The bin name is the file
# name (what the user types), which is the identity everything else uses.
go_installed_by_bin() {
    local rows pkg_path mod_path cur file
    # Read first, then loop: piping into `while` would make the pipeline status
    # the loop's (always 0) and turn a failed scan into "nothing installed".
    rows="$(go_scan_prefix)" || return 1
    while read -r pkg_path mod_path cur file; do
        [[ -n "$file" ]] || continue
        printf '%s %s\n' "$(basename "$file")" "$cur"
    done <<<"$rows"
}

go_list_rows() {
    local go_bin line pkg_path mod_path cur latest listed row query_failed=0
    local -a targets=() rows=()
    go_bin="$(find_go_bin)" || return 1

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        read -r pkg_path mod_path cur _file <<<"$line"
        case " ${targets[*]:-} " in
            *" $mod_path@latest "*) ;;
            *) targets+=("$mod_path@latest") ;;
        esac
        rows+=("$pkg_path $mod_path $cur")
    done < <(go_scan_prefix)

    (( ${#targets[@]} > 0 )) || return 0
    if ! listed="$("$go_bin" list -m -f '{{.Path}} {{.Version}}' "${targets[@]}" 2>/dev/null)"; then
        query_failed=1
    fi

    for row in "${rows[@]}"; do
        read -r pkg_path mod_path cur <<<"$row"
        if (( query_failed )); then
            latest="?"
        else
            latest="$(awk -v p="$mod_path" '$1 == p { print $2; exit }' <<<"$listed")"
            [[ -n "$latest" ]] || latest="?"
        fi
        printf '%s %s %s\n' "$pkg_path" "$cur" "$latest"
    done
    return 0
}

# ── dispatch ────────────────────────────────────────────────────
# Channel-private machine verb. eco asks this before a removal; a plain verb it
# does not know returns 127 so the shared dispatcher can report it.
channel_extra_verb() {
    local verb="${1:-}"
    case "$verb" in
        --is-go-binary)
            # shellcheck disable=SC2034  # read by msg() in common.sh
            CLI_READ_ONLY=1
            # shellcheck disable=SC2034  # read by msg() in common.sh
            CLI_MACHINE_OUTPUT=1
            local target="${2:-}" go_bin meta
            [[ -n "$target" ]] || { warn "usage: ${0##*/} --is-go-binary <path>"; return 2; }
            go_bin="$(find_go_bin)" || return 3
            meta="$("$go_bin" version -m "$target" 2>/dev/null)" || return 1
            grep -qE '^[[:space:]]+mod[[:space:]]' <<<"$meta" || return 1
            return 0
            ;;
    esac
    return 127
}

main() {
    channel_dispatch \
        go_ensure go_install_one go_update_one go_uninstall_one \
        go_list_rows go_installed_by_bin go_query_outdated go_manifest_install \
        "$@"
}

# install every selected eco.conf row for this channel.
go_manifest_install() {
    eco_manifest_install go_install_one "go install" "$(channel_detect go)"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

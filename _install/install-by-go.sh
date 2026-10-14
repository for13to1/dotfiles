#!/usr/bin/env bash
# _install/install-by-go.sh — Go CLI lifecycle (install/upgrade/uninstall) via `go install`
#
# Toolchain comes from the package manager; this channel pins GOBIN and
# GOMODCACHE in GOENV and installs the Go editor tools (gopls, gofumpt) into
# the shared ~/.local/bin CLI prefix.

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

# The single go-channel installer. @latest is the channel default (no per-tool
# version pinning yet); the flag slot is reserved.
go_install_one() {
    local go_bin
    go_bin="$(find_go_bin)" || return 1
    GOBIN="$CLI_BIN_DIR" "$go_bin" install "$2@latest"
}

# The go-channel uninstaller: `go install` only writes GOBIN binaries, so
# removal deletes the binary; the shared GOMODCACHE is left alone.
go_uninstall_one() {
    rm -f "$CLI_BIN_DIR/$1"
}

# ── domain-wide prefix scan ─────────────────────────────────────
# Scan every executable in CLI_BIN_DIR for embedded Go module metadata.
# Emits "pkg_path mod_path current" rows. pkg_path is the binary's package
# path (from the `path` line — what `go install` was given); mod_path is the
# owning module (from the first `mod` line — the main module). Non-Go
# binaries have no metadata and are skipped silently.
go_scan_prefix() {
    local go_bin f meta path_line mod_line mod_path cur pkg_path
    go_bin="$(find_go_bin)" || return 1
    for f in "$CLI_BIN_DIR"/*; do
        [[ -x "$f" && ! -d "$f" ]] || continue
        meta="$("$go_bin" version -m "$f" 2>/dev/null)" || continue
        path_line="$(awk '$1 == "path" { print $2; exit }' <<<"$meta")"
        mod_line="$(awk '$1 == "mod" { print $2, $3; exit }' <<<"$meta")"
        read -r mod_path cur <<<"$mod_line"
        [[ -n "$mod_path" && -n "$cur" ]] || continue
        pkg_path="${path_line:-$mod_path}"
        printf '%s %s %s\n' "$pkg_path" "$mod_path" "$cur"
    done
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
        read -r pkg_path mod_path cur <<<"$line"
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
go_list_rows() {
    local go_bin line pkg_path mod_path cur latest listed row query_failed=0
    local -a targets=() rows=()
    go_bin="$(find_go_bin)" || return 1

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        read -r pkg_path mod_path cur <<<"$line"
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
main() {
    local verb="${1:-}"
    case "$verb" in
        ""|-h|--help)
            echo "usage: $0 --list | --outdated | --install-manifest | --install-one <bin> <pkg> [flag] | --update-one <bin> <pkg> [flag] | --uninstall-one <bin> <pkg> [flag] | -h|--help"
            return 0
            ;;
        --list)
            CLI_READ_ONLY=1
            # shellcheck disable=SC2034  # read by msg() in common.sh
            CLI_MACHINE_OUTPUT=1
            go_ensure || return 0
            go_list_rows || true
            return 0
            ;;
        --outdated)
            CLI_READ_ONLY=1
            # shellcheck disable=SC2034  # read by msg() in common.sh
            CLI_MACHINE_OUTPUT=1
            go_ensure || return 1
            go_query_outdated
            ;;
        --install-manifest)
            go_ensure || return 0
            eco_manifest_install go_install_one "go install" "$(channel_detect go)"
            ;;
        --install-one)
            shift
            (($# >= 2)) || { warn "usage: $0 --install-one <bin> <pkg> [flag]"; return 2; }
            go_ensure || return 0
            go_install_one "$1" "$2" "${3:-}"
            ;;
        --update-one)
            shift
            (($# >= 2)) || { warn "usage: $0 --update-one <bin> <pkg> [flag]"; return 2; }
            go_ensure || return 0
            # go_install_one doubles as the upgrader: @latest reinstall is Go's upgrade.
            go_install_one "$1" "$2" "${3:-}"
            ;;
        --uninstall-one)
            shift
            (($# >= 1)) || { warn "usage: $0 --uninstall-one <bin> <pkg> [flag]"; return 2; }
            go_ensure || return 0
            # Only remove binaries in the canonical prefix; a PATH-only
            # install is not ours to remove (rm -f would silently "succeed").
            if [[ ! -x "$CLI_BIN_DIR/$1" ]]; then
                info "$1 not found in $CLI_BIN_DIR; nothing to remove"
                return 0
            fi
            go_uninstall_one "$1" "$2" "${3:-}"
            ;;
        *)
            warn "unknown option '$verb' (supported: --list, --outdated, --install-manifest, --install-one, --update-one, --uninstall-one, -h|--help)"
            return 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

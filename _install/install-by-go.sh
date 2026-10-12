#!/usr/bin/env bash
# _install/install-by-go.sh — Go CLI lifecycle (install/upgrade/uninstall) via `go install`
#
# Toolchain comes from the package manager; this channel pins GOBIN and
# GOMODCACHE in GOENV and installs the Go editor tools (gopls, gofumpt) into the
# shared ~/.local/bin CLI prefix.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-registry.sh"
cli_registry_filter_channel go

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
# channel contract, so it runs for every verb (idempotent, warn-only on write).
go_ensure() {
    if [[ -z "$(find_go_bin || true)" ]]; then
        warn "go not found; skipping Go CLI lifecycle"
        return 1
    fi
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

# Go has no registry-wide "outdated": read each binary's embedded module
# metadata for its current version, then ask the proxy once for all of them.
# The first mod line is the main module (works for cmd/ subpath tools); the
# emitted key stays the registry pkg, the module path is only the lookup key.
# Rows without embedded metadata are skipped; a failed lookup fails the query.
# stdout is the result channel, so warn goes to stderr.
go_query_outdated() {
    local go_bin i bin pkg meta mod_path cur latest listed row
    local -a targets=() rows=()
    go_bin="$(find_go_bin)" || return 1

    for i in "${!ECO_CLI_BINS[@]}"; do
        bin="${ECO_CLI_BINS[i]}"
        pkg="${ECO_CLI_PKGS[i]}"
        [[ -x "$CLI_BIN_DIR/$bin" ]] || continue
        meta="$("$go_bin" version -m "$CLI_BIN_DIR/$bin" 2>/dev/null \
            | awk '$1 == "mod" { print $2, $3; exit }')"
        read -r mod_path cur <<<"$meta"
        [[ -n "$mod_path" && -n "$cur" ]] || continue
        case " ${targets[*]:-} " in
            *" $mod_path@latest "*) ;;
            *) targets+=("$mod_path@latest") ;;
        esac
        rows+=("$pkg $mod_path $cur")
    done

    (( ${#targets[@]} > 0 )) || return 0
    if ! listed="$("$go_bin" list -m -f '{{.Path}} {{.Version}}' "${targets[@]}" 2>/dev/null)"; then
        warn "go list -m failed; skipping updates" >&2
        return 1
    fi

    for row in "${rows[@]}"; do
        read -r pkg mod_path cur <<<"$row"
        latest="$(awk -v p="$mod_path" '$1 == p { print $2; exit }' <<<"$listed")"
        [[ -n "$latest" && "$latest" != "$cur" ]] || continue
        printf '%s %s %s\n' "$pkg" "$cur" "$latest"
    done
}

# ── go CLI registry ──────────────────────────────────────────────
# Declarations live in _scripts/cli-registry.sh; only go's rows are kept here.

main() {
    # go_install_one doubles as the upgrader: @latest reinstall is Go's upgrade.
    run_cli_channel go_ensure go_install_one go_query_outdated \
        go_install_one go_uninstall_one "go install" "$(channel_detect go)" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

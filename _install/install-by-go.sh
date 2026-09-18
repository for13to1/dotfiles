#!/usr/bin/env bash
# _install/install-by-go.sh — Go CLI installs via `go install`
#
# Toolchain comes from the package manager; this channel pins GOBIN and
# GOMODCACHE in GOENV and installs the Go editor tools (gopls, gofumpt) into the
# shared ~/.local/bin CLI prefix.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

# The ~/.local/bin CLI prefix, shared with the npm/uv channels.
CLI_DIR="$HOME/.local/bin"

# Go layout declared by this repo: GOBIN is the shared ~/.local/bin prefix, and
# GOMODCACHE lives under ~/.cache instead of Go's default ~/go/pkg/mod. GOPATH is
# left alone — GOBIN and GOMODCACHE take over its only remaining roles in module
# mode.
GO_LAYOUT=(
    "GOBIN=$CLI_DIR"
    "GOMODCACHE=$HOME/.cache/go-mod"
)

find_go_bin() {
    command -v go
}

# Declare the layout in the user-level GOENV (`go env GOENV`). The dotfiles
# are the source of truth, so values are written unconditionally; a value the
# user actually set (persisted in GOENV or exported) is reported when it
# differs, while Go's built-in defaults are never reported. `go env -w` is
# idempotent and a failed write only warns — installs target CLI_DIR anyway.
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

        # A value exported in this shell wins over GOENV, so the write below
        # cannot change what this shell uses — report that instead.
        if [[ -n "${!key:-}" && "${!key}" != "$want" ]]; then
            warn "$key=${!key} is exported in this shell; go env -w will not override it"
        fi
    done

    "$go_bin" env -w "${GO_LAYOUT[@]}" \
        || warn "go env -w failed; the Go layout may not be persisted"
}

install_gopls() {
    local go_bin
    go_bin="$(find_go_bin)" || return 1
    GOBIN="$CLI_DIR" "$go_bin" install golang.org/x/tools/gopls@latest
}

install_gofumpt() {
    local go_bin
    go_bin="$(find_go_bin)" || return 1
    GOBIN="$CLI_DIR" "$go_bin" install mvdan.cc/gofumpt@latest
}

main() {
    if [[ -z "$(find_go_bin || true)" ]]; then
        warn "go not found; skipping Go CLI installs"
        return 0
    fi

    ensure_go_layout

    # The layout is declared, not inherited: gopls/gofumpt always go to CLI_DIR.
    if ! is_installed gopls "$CLI_DIR/gopls"; then
        clean_stale_installs "$CLI_DIR/gopls"
        info "gopls not found; installing it via go install..."
        install_gopls
        ok "gopls installed"
    fi

    if ! is_installed gofumpt "$CLI_DIR/gofumpt"; then
        clean_stale_installs "$CLI_DIR/gofumpt"
        info "gofumpt not found; installing it via go install..."
        install_gofumpt
        ok "gofumpt installed"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

#!/usr/bin/env bash
# _install/install-by-go.sh — Go CLI installs via `go install`
#
# Toolchain comes from the package manager; this channel declares the user-level
# Go layout in GOENV and installs the Go editor tools (gopls, gofumpt) into the
# shared ~/.local/bin CLI prefix.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

# The ~/.local/bin CLI prefix, shared with the npm/uv channels.
CLI_DIR="$HOME/.local/bin"

# User-level Go layout declared by this repo: GOBIN is the shared ~/.local/bin
# prefix, GOPATH/GOMODCACHE live under ~/.cache instead of Go's default ~/go.
GO_LAYOUT=(
    "GOBIN=$CLI_DIR"
    "GOMODCACHE=$HOME/.cache/go-mod"
    "GOPATH=$HOME/.cache/go"
)

find_go_bin() {
    command -v go
}

# Declare the layout in the user-level GOENV (path: `go env GOENV`). The
# dotfiles are the source of truth for this environment, so the values are
# written unconditionally; a different value already in effect is reported
# first, so the change is never silent. `go env -w` is idempotent, and a failed
# write only warns — the installs below target CLI_DIR explicitly.
ensure_go_layout() {
    local go_bin pair key want cur
    go_bin="$(find_go_bin)" || return 1

    for pair in "${GO_LAYOUT[@]}"; do
        key="${pair%%=*}"
        want="${pair#*=}"
        cur="$("$go_bin" env "$key" 2>/dev/null || true)"
        if [[ -n "$cur" && "$cur" != "$want" ]]; then
            warn "$key was $cur; rewriting to $want"
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

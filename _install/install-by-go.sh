#!/usr/bin/env bash
# _install/install-by-go.sh — Go CLI installs via `go install`
#
# Toolchain comes from the package manager; this channel installs the Go editor
# tools (gopls, gofumpt) into the shared ~/.local/bin CLI prefix, pinned
# best-effort via ensure_go_layout.

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

# The ~/.local/bin CLI prefix, shared with the npm/uv channels.
CLI_DIR="$HOME/.local/bin"

find_go_bin() {
    command -v go
}

# Pin the user-level Go layout in GOENV: GOBIN to the shared ~/.local/bin CLI
# prefix, GOPATH/GOMODCACHE under ~/.cache instead of Go's default ~/go.
# `go env -w` is idempotent for matching values, so this runs unconditionally;
# a failure (e.g. an unwritable GOENV) only warns — the installs below target
# the effective GOBIN explicitly, and main falls back to CLI_DIR when nothing
# is pinned. Existing GOENV values are overwritten.
ensure_go_layout() {
    local go_bin
    go_bin="$(find_go_bin)" || return 1
    "$go_bin" env -w GOBIN="$CLI_DIR" \
        GOMODCACHE="$HOME/.cache/go-mod" \
        GOPATH="$HOME/.cache/go" \
        || warn "go env -w failed; installing into the effective GOBIN"
}

install_gopls() {
    local go_bin
    go_bin="$(find_go_bin)" || return 1
    GOBIN="$go_cli_dir" "$go_bin" install golang.org/x/tools/gopls@latest
}

install_gofumpt() {
    local go_bin
    go_bin="$(find_go_bin)" || return 1
    GOBIN="$go_cli_dir" "$go_bin" install mvdan.cc/gofumpt@latest
}

main() {
    if [[ -z "$(find_go_bin || true)" ]]; then
        warn "go not found; skipping Go CLI installs"
        return 0
    fi

    ensure_go_layout

    # Resolve the install target from the established layout. An exported GOBIN
    # wins over GOENV; fall back to CLI_DIR when nothing is pinned (e.g. the
    # write above failed).
    local go_bin
    go_bin="$(find_go_bin)"
    go_cli_dir="$("$go_bin" env GOBIN 2>/dev/null || true)"
    [[ -n "$go_cli_dir" ]] || go_cli_dir="$CLI_DIR"

    if ! is_installed gopls "$go_cli_dir/gopls"; then
        clean_stale_installs "$go_cli_dir/gopls"
        info "gopls not found; installing it via go install..."
        install_gopls
        ok "gopls installed"
    fi

    if ! is_installed gofumpt "$go_cli_dir/gofumpt"; then
        clean_stale_installs "$go_cli_dir/gofumpt"
        info "gofumpt not found; installing it via go install..."
        install_gofumpt
        ok "gofumpt installed"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

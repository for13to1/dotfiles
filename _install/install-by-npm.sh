#!/usr/bin/env bash
# _install/install-by-npm.sh — Node.js CLI installs via npm

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

# ── Node environment activation ──────────────────────────────────
# Reuse the locally fnm-managed Node instead of installing a runtime. All Node/npm
# calls go through fnm exec to enter the pinned runtime, avoiding reliance on fnm
# multishell's internal path layout.
FNM_BIN=""

find_fnm_bin() {
    if command -v fnm &>/dev/null; then
        command -v fnm
    elif [[ -x "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm" ]]; then
        printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm"
    fi
}

fnm_exec() {
    "$FNM_BIN" exec --using lts-latest -- "$@"
}

ensure_fnm_node_env() {
    FNM_BIN="$(find_fnm_bin || true)"
    if [[ -z "$FNM_BIN" ]]; then
        warn "fnm not found; skipping npm CLI installs"
        return 1
    fi

    info "fnm found; preparing the Node LTS environment..."
    "$FNM_BIN" install --lts &>/dev/null || true
    "$FNM_BIN" default lts-latest &>/dev/null || true

    if fnm_exec node --version &>/dev/null; then
        ok "fnm Node $(fnm_exec node --version) ready"
        return 0
    fi

    warn "Node environment setup failed; run 'fnm install --lts' manually later"
    return 1
}

# npm >= 11.10 added a release-age gate; the official installer bypasses it with
# --min-release-age=0.
release_age_flag() {
    local npm_version
    npm_version="$(fnm_exec npm --version)"
    awk -F. '{ exit !($1 > 11 || ($1 == 11 && $2 >= 10)) }' <<<"$npm_version"
}

npm_install_global() {
    if release_age_flag; then
        fnm_exec npm install -g --min-release-age=0 "$@"
    else
        fnm_exec npm install -g "$@"
    fi
}

install_pi() {
    npm_install_global --ignore-scripts @earendil-works/pi-coding-agent
}

# @openai/codex has no postinstall; platform binaries ship via optionalDependencies.
install_codex() {
    npm_install_global @openai/codex
}

install_opencode() {
    npm_install_global opencode-ai
}

install_biome() {
    npm_install_global --prefix "$HOME/.local" @biomejs/biome
}

main() {
    if ! ensure_fnm_node_env; then
        return 0
    fi

    if ! fnm_exec npm --version &>/dev/null; then
        warn "npm not found; skipping npm CLI installs"
        return 0
    fi

    install_with_prompt \
        "biome" \
        "biome not found; install it to ~/.local via npm?" \
        "install_biome" \
        "biome installed" \
        "$HOME/.local/bin/biome"

    install_with_prompt \
        "pi" \
        "pi not found; install it via npm?" \
        "install_pi" \
        "pi installed"

    install_with_prompt \
        "codex" \
        "codex not found; install it via npm?" \
        "install_codex" \
        "codex installed"

    install_with_prompt \
        "opencode" \
        "opencode not found; install it via npm?" \
        "install_opencode" \
        "opencode installed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

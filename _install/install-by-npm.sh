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

# Prompt to install an npm CLI into the pinned runtime. `fnm exec` installs
# into that runtime's global bin without updating this script's PATH, so bin
# (probed once in main) is checked alongside PATH for existing installs.
install_npm_cli() {
    local name="$1" install_fn="$2" bin="$3"
    install_with_prompt \
        "$name" \
        "$name not found; install it via npm?" \
        "$install_fn" \
        "$name installed" \
        "$bin/$name"
}

main() {
    if ! ensure_fnm_node_env; then
        return 0
    fi

    # Probe the pinned runtime: a non-empty prefix both confirms npm is present
    # and yields the global bin `fnm exec` installs into — which this script's
    # PATH cannot see, so the checks below must include it explicitly.
    local fnm_global_prefix fnm_global_bin
    fnm_global_prefix="$(fnm_exec npm prefix -g 2>/dev/null || true)"
    if [[ -z "$fnm_global_prefix" ]]; then
        warn "npm not found; skipping npm CLI installs"
        return 0
    fi
    fnm_global_bin="$fnm_global_prefix/bin"

    if ! is_installed biome "$HOME/.local/bin/biome"; then
        info "biome not found; installing it to ~/.local via npm..."
        install_biome
        ok "biome installed"
    fi

    install_npm_cli pi install_pi "$fnm_global_bin"
    install_npm_cli codex install_codex "$fnm_global_bin"
    install_npm_cli opencode install_opencode "$fnm_global_bin"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

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

# npm 11.x introduced the install-scripts policy (12.x hard-blocks lifecycle
# scripts by default); packages not on the allowlist get their postinstall
# skipped. Older npm does not understand the --allow-scripts flag.
npm_supports_allow_scripts() {
    fnm_exec npm install --help 2>/dev/null | grep -q -- '--allow-scripts'
}

# Install npm globals: pass through policy flags (--min-release-age,
# --allow-scripts) only when this npm supports them, dropping them otherwise
# and forwarding the remaining args untouched.
npm_install_global() {
    local resolved=()
    local arg
    for arg in "$@"; do
        case "$arg" in
            --allow-scripts=*)
                npm_supports_allow_scripts || continue
                ;;
        esac
        resolved+=("$arg")
    done

    if release_age_flag; then
        fnm_exec npm install -g --min-release-age=0 "${resolved[@]}"
    else
        fnm_exec npm install -g "${resolved[@]}"
    fi
}

install_pi() {
    npm_install_global --ignore-scripts @earendil-works/pi-coding-agent
}

# @openai/codex has no postinstall; platform binaries ship via optionalDependencies.
install_codex() {
    npm_install_global @openai/codex
}

# opencode's postinstall copies the platform binary into bin/ (required);
# allow it (npm_install_global drops the flag on old npm).
install_opencode() {
    npm_install_global --allow-scripts=opencode-ai opencode-ai
}

# wrangler depends on workerd/esbuild, whose postinstall seeds the native
# binaries; allow their scripts (npm_install_global drops the flag on old npm).
install_wrangler() {
    npm_install_global --allow-scripts=esbuild,workerd wrangler
}

# codegraph's npm distro is a launcher shim (npm-shim.js) with no lifecycle
# scripts, so a plain global install suffices — no --allow-scripts needed.
install_codegraph() {
    npm_install_global @colbymchenry/codegraph
}

install_biome() {
    npm_install_global --prefix "$HOME/.local" @biomejs/biome
}

# Prebuilt binary from the official npm distribution (@johnnymorganz/stylua-bin).
install_stylua() {
    npm_install_global @johnnymorganz/stylua-bin
}

# Interactive optional CLIs, installed only after confirmation. Each entry must
# have a matching install_<name> function above (carrying its npm flags) — add
# a CLI here AND its function there. biome/stylua install unconditionally when
# missing, so they intentionally stay out of this list.
PROMPTED_CLIS=(pi codex opencode codegraph wrangler)

main() {
    if ! ensure_fnm_node_env; then
        return 0
    fi

    # Probe the pinned runtime: a non-empty prefix both confirms npm is present
    # and yields the global bin `fnm exec` installs into — which this script's
    # PATH cannot see, so the checks below must include it explicitly.
    local fnm_global_prefix fnm_global_bin name
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

    if ! is_installed stylua "$fnm_global_bin/stylua"; then
        info "stylua not found; installing it via npm (prebuilt binary)..."
        install_stylua
        ok "stylua installed"
    fi

    for name in "${PROMPTED_CLIS[@]}"; do
        install_with_prompt \
            "$name" \
            "$name not found; install it via npm?" \
            "install_$name" \
            "$name installed" \
            "$fnm_global_bin/$name"
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

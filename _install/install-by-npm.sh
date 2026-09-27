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

# Global npm CLIs install into a Node-version-independent prefix. fnm's `default`
# alias follows `lts-latest`, so an LTS patch bump re-points PATH at a fresh Node
# with an empty global bin — which used to make every CLI look missing.
# npm's --prefix is the install ROOT; bins land in common.sh's CLI_BIN_DIR, so
# derive the root from it to keep the two paths from drifting apart.
LOCAL_PREFIX="${CLI_BIN_DIR%/*}"

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

# Install npm globals into $LOCAL_PREFIX. Drop --allow-scripts when this npm
# rejects it and disable the release-age gate when this npm enforces one;
# forward all other args untouched.
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
        fnm_exec npm install -g --prefix "$LOCAL_PREFIX" --min-release-age=0 "${resolved[@]}"
    else
        fnm_exec npm install -g --prefix "$LOCAL_PREFIX" "${resolved[@]}"
    fi
}

# The single npm-channel installer: every registry entry is (pkg, flag), and
# npm_install_global carries all the npm-version quirks (dropping
# --allow-scripts on old npm, --min-release-age on npm >= 11.10). Flags are
# documented per entry in the registry below; an empty flag is a plain install.
npm_install_one() {
    if [[ -z "$2" ]]; then
        npm_install_global "$1"
    else
        npm_install_global "$2" "$1"
    fi
}

# ── npm CLI registry ─────────────────────────────────────────────
# Channel data only — the frame (eco_cli/validate/run) lives in common.sh.
#   flag ""                        → plain global install
#   flag --allow-scripts=<list>    → postinstall seeds/links the native binary
#   flag --ignore-scripts          → package has no useful lifecycle scripts
eco_cli biome     @biomejs/biome                   ""                          --always
eco_cli stylua    @johnnymorganz/stylua-bin        ""                          --always
eco_cli pi        @earendil-works/pi-coding-agent  --ignore-scripts            --prompt
eco_cli codex     @openai/codex                    ""                          --prompt
eco_cli opencode  opencode-ai                      --allow-scripts=opencode-ai --prompt
eco_cli mimo      @mimo-ai/cli                     --allow-scripts=@mimo-ai/cli --prompt
eco_cli codegraph @colbymchenry/codegraph          ""                          --prompt
eco_cli wrangler  wrangler                         --allow-scripts=esbuild,workerd --prompt

main() {
    validate_cli_registry

    if ! ensure_fnm_node_env; then
        return 0
    fi

    # `npm prefix -g` prints nothing when npm is missing; use it as a presence gate.
    local npm_prefix
    npm_prefix="$(fnm_exec npm prefix -g 2>/dev/null || true)"
    if [[ -z "$npm_prefix" ]]; then
        warn "npm not found; skipping npm CLI installs"
        return 0
    fi

    run_cli_registry npm_install_one npm
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

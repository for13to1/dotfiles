#!/usr/bin/env bash
# _install/install-by-npm.sh — Node.js CLI lifecycle (install/upgrade/uninstall) via npm

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-registry.sh"
cli_registry_filter_channel npm

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
        warn "fnm not found; skipping npm CLI lifecycle"
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

# Channel runtime gate: fnm-managed Node LTS plus a working npm in front of it.
npm_ensure() {
    ensure_fnm_node_env || return 1

    # `npm prefix -g` prints nothing when npm is missing.
    local npm_prefix
    npm_prefix="$(fnm_exec npm prefix -g 2>/dev/null || true)"
    if [[ -z "$npm_prefix" ]]; then
        warn "npm not found; skipping npm CLI lifecycle"
        return 1
    fi
}

# The single npm-channel installer: every registry entry is (bin, pkg, flag),
# and npm_install_global carries all the npm-version quirks (dropping
# --allow-scripts on old npm, --min-release-age on npm >= 11.10). Flags are
# documented per entry in the registry below; an empty flag is a plain install.
npm_install_one() {
    if [[ -z "$3" ]]; then
        npm_install_global "$2"
    else
        npm_install_global "$3" "$2"
    fi
}

# The upgrade path reuses the single npm installer with <pkg>@latest: same
# prefix, same --allow-scripts/--min-release-age quirks, one code path.
npm_update_one() {
    npm_install_one "$1" "$2@latest" "$3"
}

# The npm-channel uninstaller: npm owns its global tree, so removal goes
# through npm — nothing is rm'ed behind npm's back. A manually placed bin
# survives: npm just reports nothing to remove (exit 0), it does not error.
npm_uninstall_one() {
    fnm_exec npm uninstall -g --prefix "$LOCAL_PREFIX" "$2"
}

# One batch query for the whole prefix. npm outdated exits 1 when anything is
# outdated and prints {} when current; any other exit is an error. stdout is
# the result channel, so warn goes to stderr.
npm_query_outdated() {
    local raw rc=0
    raw="$(fnm_exec npm outdated -g --prefix "$LOCAL_PREFIX" --json 2>/dev/null)" || rc=$?
    case "$rc" in
        0|1) ;;
        *)
            warn "npm outdated query failed (exit $rc); skipping npm CLI updates" >&2
            return 1
            ;;
    esac
    [[ -z "$raw" || "$raw" == "{}" ]] && return 0

    # Parse JSON in the runtime this channel guarantees; only
    # "pkg current latest" lines are emitted.
    fnm_exec node -e '
        const data = JSON.parse(process.argv[1]);
        if (data.error) process.exit(1);
        for (const [pkg, info] of Object.entries(data)) {
            // Skip current === latest so an already-latest package is never
            // "upgraded" to the version it runs.
            if (info && info.current && info.latest && info.current !== info.latest) {
                console.log(pkg, info.current, info.latest);
            }
        }
    ' "$raw"
}

# ── npm CLI registry ─────────────────────────────────────────────
# Declarations live in _scripts/cli-registry.sh; only npm's rows are kept
# here. The eco_cli frame (install/update/uninstall) lives in common.sh.

main() {
    run_cli_channel npm_ensure npm_install_one npm_query_outdated \
        npm_update_one npm_uninstall_one npm "$(channel_detect npm)" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

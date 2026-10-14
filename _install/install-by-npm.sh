#!/usr/bin/env bash
# _install/install-by-npm.sh — Node.js CLI lifecycle (install/upgrade/uninstall) via npm

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-lifecycle.sh"
eco_conf_load
eco_conf_filter_channel node

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

    # Read-only verbs (--list/--outdated) must not prepare anything: probing
    # is enough, and `fnm install --lts` would download a runtime just to list
    # versions. If no LTS is ready, the query cannot run and the caller reports
    # an unknown state rather than blocking on a network install.
    if [[ -n "${CLI_READ_ONLY:-}" ]]; then
        if fnm_exec node --version &>/dev/null; then
            return 0
        fi
        warn "Node LTS not ready; cannot read npm CLI state (run 'fnm install --lts' first)"
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

# npm 11.x introduced the install-scripts policy (12.x hard-blocks lifecycle
# scripts by default); packages not on the allowlist get their postinstall
# skipped. Older npm does not understand the --allow-scripts flag.
npm_supports_allow_scripts() {
    fnm_exec npm install --help 2>/dev/null | grep -q -- '--allow-scripts'
}

# Install npm globals into $LOCAL_PREFIX. Drop --allow-scripts when this npm
# rejects it and disable the release-age gate when this npm enforces one;
# forward all other args untouched. Dropping is loud: a skipped allow-list
# silently breaks the package's postinstall, so it must be visible.
npm_install_global() {
    local resolved=()
    local arg warned=0
    for arg in "$@"; do
        case "$arg" in
            --allow-scripts=*)
                if ! npm_supports_allow_scripts; then
                    (( warned )) || {
                        warn "this npm does not support --allow-scripts; $arg dropped (postinstall may be skipped)"
                        warned=1
                    }
                    continue
                fi
                ;;
        esac
        resolved+=("$arg")
    done

    # No --min-release-age override: npm's release-age gate is opt-in
    # (Default: null, verified against npm 11.19.0 docs), so the default is a
    # no-op — and any gate the user configures in .npmrc must survive us, not
    # be silently relaxed by a CLI flag (CLI source outranks user source).
    # If npm ever ships the gate on by default, we follow it for free.
    fnm_exec npm install -g --prefix "$LOCAL_PREFIX" "${resolved[@]}"
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
# and npm_install_global carries the npm-version quirk (dropping
# --allow-scripts on old npm). Flags are documented per entry in eco.conf;
# an empty flag is a plain install.
npm_install_one() {
    if [[ -z "$3" ]]; then
        npm_install_global "$2"
    else
        npm_install_global "$3" "$2"
    fi
}

# The upgrade path reuses the single npm installer with <pkg>@latest: same
# prefix, same --allow-scripts quirk, one code path.
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

# ── list mode ───────────────────────────────────────────────────
# Read-only: emit "pkg version latest_or_?" rows for the whole prefix.
# Latest comes from the outdated query; a failed latest query degrades to "?".
# A failed listing is a warning, never a hard failure — list is lenient.
npm_list_installed() {
    local ls_raw ls_rc=0
    ls_raw="$(fnm_exec npm ls -g --prefix "$LOCAL_PREFIX" --depth=0 --json 2>/dev/null)" || ls_rc=$?
    (( ls_rc == 0 )) || return 1
    fnm_exec node -e '
        const data = JSON.parse(process.argv[1]);
        const deps = data.dependencies || {};
        for (const [pkg, info] of Object.entries(deps)) {
            if (info && info.version) console.log(pkg, info.version);
        }
    ' "$ls_raw"
}

npm_list_rows() {
    local installed_rows latest_rows="" outdated_out outdated_rc=0 query_failed=0
    if ! installed_rows="$(npm_list_installed 2>/dev/null)"; then
        warn "npm ls failed; cannot list npm CLIs" >&2
        return 0
    fi
    [[ -n "$installed_rows" ]] || return 0
    outdated_out="$(fnm_exec npm outdated -g --prefix "$LOCAL_PREFIX" --json 2>/dev/null)" || outdated_rc=$?
    case "$outdated_rc" in 0|1) ;; *) query_failed=1 ;; esac
    if (( ! query_failed )) && [[ -n "$outdated_out" && "$outdated_out" != "{}" ]]; then
        latest_rows="$(fnm_exec node -e '
            const data = JSON.parse(process.argv[1]);
            for (const [pkg, info] of Object.entries(data)) {
                if (info && info.latest) console.log(pkg, info.latest);
            }
        ' "$outdated_out" 2>/dev/null)" || query_failed=1
    fi
    if (( query_failed )); then
        awk 'NF >= 2 { print $1, $2, "?" }' <<<"$installed_rows"
    elif [[ -z "$latest_rows" ]]; then
        awk 'NF >= 2 { print $1, $2, $2 }' <<<"$installed_rows"
    else
        awk '
            NR == FNR { latest[$1] = $2; next }
            NF >= 2 { print $1, $2, ($1 in latest ? latest[$1] : $2) }
        ' <(printf '%s\n' "$latest_rows") <(printf '%s\n' "$installed_rows")
    fi
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
            npm_ensure || return 0
            npm_list_rows || true
            return 0
            ;;
        --outdated)
            CLI_READ_ONLY=1
            # shellcheck disable=SC2034  # read by msg() in common.sh
            CLI_MACHINE_OUTPUT=1
            npm_ensure || return 1
            npm_query_outdated
            ;;
        --install-manifest)
            npm_ensure || return 0
            eco_manifest_install npm_install_one npm "$(channel_detect npm)"
            ;;
        --install-one)
            shift
            (($# >= 2)) || { warn "usage: $0 --install-one <bin> <pkg> [flag]"; return 2; }
            npm_ensure || return 0
            npm_install_one "$1" "$2" "${3:-}"
            ;;
        --update-one)
            shift
            (($# >= 2)) || { warn "usage: $0 --update-one <bin> <pkg> [flag]"; return 2; }
            npm_ensure || return 0
            npm_update_one "$1" "$2" "${3:-}"
            ;;
        --uninstall-one)
            shift
            (($# >= 1)) || { warn "usage: $0 --uninstall-one <bin> <pkg> [flag]"; return 2; }
            npm_ensure || return 0
            npm_uninstall_one "$1" "$2" "${3:-}"
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

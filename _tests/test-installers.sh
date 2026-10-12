#!/usr/bin/env bash
# test-installers.sh — behavior tests for ecosystem installer orchestration
# Usage: bash _tests/test-installers.sh

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/installers-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# install_cli_registry's prompt branch: declining is a successful skip; an accepted
# installer that then fails returns non-zero.
# shellcheck disable=SC1091
source "$ROOT/_scripts/common.sh"
failed_install() { return 7; }

# Point CLI_BIN_DIR at an empty temp prefix so "missing-optional" is absent.
CLI_BIN_DIR="$TMP/prompt-bin"
mkdir -p "$CLI_BIN_DIR"
eco_cli npm missing-optional missing-pkg "" --prompt

DOTFILES_NON_INTERACTIVE=1 install_cli_registry failed_install mock \
    >/dev/null || fail "declining an optional installer should return success"
unset DOTFILES_NON_INTERACTIVE
if printf 'y\n' | install_cli_registry failed_install mock >/dev/null; then
    fail "an accepted optional installer failure must return non-zero"
fi

# install_ecosystem_tools (bootstrap step #3) must run its platform-
# independent npm/uv/go channels: a failing channel must not skip the other,
# the failure must propagate, and the summary must name the failed channel.
# (The curl channel is apt-specific and lives in pkg-linux's apt branch.)
INSTALLER_REPO="$TMP/repo"
mkdir -p "$INSTALLER_REPO/_install"
for installer in install-by-npm.sh install-by-uv.sh install-by-go.sh; do
    cat > "$INSTALLER_REPO/_install/$installer" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "$INSTALLER_LOG"
[[ "$(basename "$0")" == "install-by-uv.sh" ]]
EOF
done
export INSTALLER_LOG="$TMP/installer.log"
# Used by install_ecosystem_tools (defined in common.sh) via DOTFILES_DIR.
# shellcheck disable=SC2034
DOTFILES_DIR="$INSTALLER_REPO"

if install_ecosystem_tools > "$TMP/ecosystem.out" 2>&1; then
    fail "an ecosystem channel failure must propagate"
fi
[[ "$(wc -l < "$INSTALLER_LOG" | tr -d ' ')" == 3 ]] \
    || fail "a failing channel must not skip the other channels"
grep -q 'install-by-npm.sh' "$TMP/ecosystem.out" \
    || fail "the failure summary must name the npm channel"

# Optional npm CLIs are interactive-only:
# non-interactive mode declines all of them, while an interactive run
# installs only the explicitly accepted tool.
NPM_HOME="$TMP/npm-home"
NPM_BIN="$TMP/npm-bin"
FNM_PREFIX="$TMP/fnm-prefix"
mkdir -p "$NPM_HOME/.local/bin" "$NPM_BIN" "$FNM_PREFIX/bin"
# Seat every --always entry now: run_accepting below asserts exactly one
# `npm install -g` per run, which only holds if these never trigger. A new
# --always entry must be seated here too; --prompt entries need no seat
# (they decline in non-interactive mode).
touch "$NPM_HOME/.local/bin/biome"
chmod +x "$NPM_HOME/.local/bin/biome"
touch "$NPM_HOME/.local/bin/stylua"
chmod +x "$NPM_HOME/.local/bin/stylua"
cat > "$NPM_BIN/fnm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FNM_LOG"
if [[ "$*" == *'node --version'* ]]; then
    printf '%s\n' 'v24.0.0'
elif [[ "$*" == *'npm --version'* ]]; then
    printf '%s\n' '11.9.0'
elif [[ "$*" == *'npm install --help'* ]]; then
    # Unlike the fake 11.9.0 version above, this npm claims to understand
    # --allow-scripts: the installer probes capabilities at runtime, so the
    # flag must be honored regardless of the reported version.
    printf '%s\n' '    [--allow-scripts <package-list>]'
elif [[ "$*" == *'npm prefix -g'* ]]; then
    printf '%s\n' "$FNM_PREFIX"
elif [[ "$*" == *'npm outdated'* ]]; then
    # Fixture-driven: real npm exits 1 when anything is outdated, 0 for a
    # clean {} tree, and >1 with error JSON — all three shapes are exercised.
    if [[ -n "${MOCK_OUTDATED_JSON:-}" ]]; then
        printf '%s' "$MOCK_OUTDATED_JSON"
    else
        printf '{}'
    fi
    exit "${MOCK_OUTDATED_EXIT:-0}"
elif [[ "$*" == *'node -e'* ]]; then
    # Run the real parser on the JSON fixture via the host node when one is
    # available (mock argv mirrors fnm exec: --using lts-latest -- node -e
    # <script> <json>); the pre-rendered lines remain the fallback on
    # node-less hosts, where the JSON-shape tests are skipped instead.
    if [[ -n "${MOCK_HOST_NODE:-}" ]]; then
        "$MOCK_HOST_NODE" "$6" "$7" "$8"
    else
        printf '%s' "${MOCK_OUTDATED_LINES:-}"
    fi
fi
EOF
chmod +x "$NPM_BIN/fnm"
export FNM_LOG="$TMP/fnm.log"
export FNM_PREFIX
# Prefer the host's real node for the JSON→lines parser, so the fixtures
# exercise the actual JavaScript (including the current!==latest guard).
if MOCK_HOST_NODE="$(command -v node)"; then
    export MOCK_HOST_NODE
fi

# A same-named CLI in fnm's PATH must not satisfy the npm installer's canonical
# ~/.local check. This covers migration from the old per-Node global prefix.
cat > "$NPM_BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$NPM_BIN/codex"
ln -s "$TMP/missing-codex" "$NPM_HOME/.local/bin/codex"
MIGRATION_OUTPUT="$TMP/npm-migration.out"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >"$MIGRATION_OUTPUT"
grep -q 'codex not found; install it via npm?' "$MIGRATION_OUTPUT" \
    || fail "an fnm CLI must not satisfy the ~/.local migration check"
grep -q 'removed stale install entry' "$MIGRATION_OUTPUT" \
    || fail "the npm migration must clean stale canonical entries"
[[ ! -L "$NPM_HOME/.local/bin/codex" ]] \
    || fail "the stale canonical codex entry must be removed"
rm -f "$NPM_BIN/codex"

# Non-interactive runs install nothing: every optional CLI declines by default.
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >/dev/null
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "non-interactive mode should decline optional CLI installs"

# Run a full installer pass with exactly one CLI pre-approved
# (DOTFILES_ACCEPT_TOOLS), then assert it alone was installed. Selection is
# by name, so these tests neither know nor care how many CLIs exist or in which
# order they are prompted.
run_accepting() {
    : > "$FNM_LOG"
    HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS="$1" \
        PATH="$NPM_BIN:/usr/bin:/bin" \
        bash "$ROOT/_install/install-by-npm.sh" >/dev/null
    [[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
        || fail "accepting $1 should be the only npm install of the run"
}

run_accepting codex
grep -q '@openai/codex' "$FNM_LOG" \
    || fail "accepting codex should invoke its npm install"

# opencode's postinstall copies its platform binary into bin/; accepting
# opencode must carry --allow-scripts (the mock npm understands it).
run_accepting opencode
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=opencode-ai opencode-ai' "$FNM_LOG" \
    || fail "accepting opencode should install to ~/.local with --allow-scripts"

# codegraph ships a launcher shim with no lifecycle scripts; accepting it must
# run a plain global install, without --allow-scripts.
run_accepting codegraph
grep -qE -- 'npm install -g --prefix [^ ]+ @colbymchenry/codegraph' "$FNM_LOG" \
    || fail "accepting codegraph should run a plain global npm install into ~/.local"
! grep -q -- '--allow-scripts' "$FNM_LOG" \
    || fail "codegraph has no lifecycle scripts and must not be granted --allow-scripts"

# wrangler relies on workerd/esbuild whose postinstall seeds native binaries;
# accepting wrangler must carry --allow-scripts (the mock npm understands it).
run_accepting wrangler
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=esbuild,workerd wrangler' "$FNM_LOG" \
    || fail "accepting wrangler should install to ~/.local with --allow-scripts"

# @mimo-ai/cli's postinstall links the platform binary into bin/; accepting
# mimo must carry --allow-scripts with the scoped package name.
run_accepting mimo
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=@mimo-ai/cli @mimo-ai/cli' "$FNM_LOG" \
    || fail "accepting mimo should install to ~/.local with --allow-scripts"

# Seat every CLI the installer knows about, reading its registry directly so a
# new tool never needs an edit on this side. The registry must also be
# self-consistent (aligned arrays, valid policies, always-before-prompt) —
# verified via the same guard the installer runs, independent of its main().
# Sourcing also imports the installer's globals; this test only reads the
# ECO_CLI_* registry below and invokes none of them.
# shellcheck disable=SC1091
source "$ROOT/_install/install-by-npm.sh"
validate_cli_registry \
    || fail "the npm CLI registry must be self-consistent"
for bin in "${ECO_CLI_BINS[@]}"; do
    touch "$NPM_HOME/.local/bin/$bin"
    chmod +x "$NPM_HOME/.local/bin/$bin"
done

# Baseline installs must land before any question: an --always entry declared
# after a --prompt one is a registry error and has to fail validation.
if bash -c '
    source "$1"
    ECO_CLI_POLICIES[0]=prompt
    validate_cli_registry >/dev/null 2>&1
' _ "$ROOT/_install/install-by-npm.sh"; then
    fail "an --always entry after a --prompt entry must fail validation"
fi

# Global CLIs install into ~/.local, which may not be on the parent shell's
# PATH. They must still be detected and must not trigger duplicate-install prompts.
FNM_OUTPUT="$TMP/fnm-detection.out"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >"$FNM_OUTPUT"
! grep -q 'not found' "$FNM_OUTPUT" \
    || fail "CLIs in the ~/.local prefix must be detected outside the parent PATH"

# A runtime without npm must degrade to a clean skip, not an error.
FNM_PREFIX="" HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >"$TMP/npm-missing.out" 2>&1 \
    || fail "missing npm must skip cleanly"
grep -q 'skipping npm CLI lifecycle' "$TMP/npm-missing.out" \
    || fail "missing npm must warn and skip"

# Upgrades (--update): same registry, same authorization as installs — one
# batch query, only installed rows are candidates, and a non-interactive run
# upgrades exactly the DOTFILES_ACCEPT_TOOLS subset, each row keeping its
# own pkg+flag pair.
NPM_UPDATE_HOME="$TMP/npm-update-home"
mkdir -p "$NPM_UPDATE_HOME/.local/bin"
seat() { touch "$NPM_UPDATE_HOME/.local/bin/$1"; chmod +x "$NPM_UPDATE_HOME/.local/bin/$1"; }
seat biome
seat stylua
seat wrangler
NPM_OUT="$TMP/npm-update.out"
# run_updating <accept> <lines> <json> <json-exit> [bin…]
run_updating() {
    local accept="$1" lines="$2" json="$3" json_exit="$4"
    shift 4
    : > "$FNM_LOG"
    HOME="$NPM_UPDATE_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS="$accept" \
        MOCK_OUTDATED_LINES="$lines" MOCK_OUTDATED_JSON="$json" MOCK_OUTDATED_EXIT="$json_exit" \
        PATH="$NPM_BIN:/usr/bin:/bin" \
        bash "$ROOT/_install/install-by-npm.sh" --update "$@" >"$NPM_OUT" 2>&1
}
NPM_OUTDATED_COUNT=3

# A clean {} tree reports up to date and installs nothing.
run_updating "" '' '{}' 0 || fail "a clean outdated query must not fail"
grep -q 'up to date' "$NPM_OUT" \
    || fail "an outdated-free tree must report up to date"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "an outdated-free tree must not run any install"

# Partial pre-approval upgrades exactly the approved row with its own
# pkg+flag pair — never another row's identity (the parallel-array bug) —
# and an outdated-but-uninstalled package is never installed as a side effect.
# npm outdated keys are package names (scoped ones included), not bin names.
run_updating wrangler \
    '@biomejs/biome 1.0.0 2.0.0
@johnnymorganz/stylua-bin 0.1.0 0.2.0
wrangler 3.0.0 4.0.0
@openai/codex 1.0.0 2.0.0' \
    '{"@biomejs/biome":{"current":"1.0.0","latest":"2.0.0"},"@johnnymorganz/stylua-bin":{"current":"0.1.0","latest":"0.2.0"},"wrangler":{"current":"3.0.0","latest":"4.0.0"},"@openai/codex":{"current":"1.0.0","latest":"2.0.0"}}' \
    1 || fail "a partial-approval update must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "accepting wrangler must upgrade exactly one CLI"
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=esbuild,workerd wrangler@latest' "$FNM_LOG" \
    || fail "the wrangler upgrade must pair wrangler@latest with its own flag"
! grep -qE -- '@biomejs/biome@latest|stylua-bin@latest' "$FNM_LOG" \
    || fail "an unapproved row must not be upgraded under another row's identity"
! grep -q -- '@openai/codex@latest' "$FNM_LOG" \
    || fail "an outdated but uninstalled CLI must not be installed by an update"
[[ "$(grep -c 'update available: ' "$NPM_OUT" || true)" == "$NPM_OUTDATED_COUNT" ]] \
    || fail "every installed outdated row must be listed, installed or not"

# A named scope narrows the upgrade: unnamed outdated rows are neither listed
# nor upgraded, and a named-but-not-approved row upgrades nothing.
run_updating "" \
    '@biomejs/biome 1.0.0 2.0.0
wrangler 3.0.0 4.0.0' \
    '{"@biomejs/biome":{"current":"1.0.0","latest":"2.0.0"},"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    1 wrangler || fail "a declined named-scope update must not fail"
[[ "$(grep -c 'update available: ' "$NPM_OUT" || true)" == 1 ]] \
    || fail "a named scope must list only the named outdated row"
grep -q 'update available: wrangler' "$NPM_OUT" \
    || fail "the named row must be listed"
! grep -q 'update available: biome' "$NPM_OUT" \
    || fail "an unnamed outdated row must not be listed under a named scope"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "without pre-approval a named-scope update must install nothing"

# A named bin that is current must not claim "all installed … up to date" —
# an unnamed outdated row exists; the message names the scope honestly.
run_updating "" \
    'wrangler 3.0.0 4.0.0' \
    '{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    1 biome || fail "a current named bin must not fail the run"
grep -q 'all named npm CLIs are up to date' "$NPM_OUT" \
    || fail "a named scope with a current bin must name its scope"
! grep -q 'all installed npm CLIs are up to date' "$NPM_OUT" \
    || fail "a named scope must never claim all installed CLIs are up to date"

# A named bin with no installed candidate (typo or foreign install)
# short-circuits before the query: no npm outdated round-trip, an honest
# nothing-to-do message, never a false "up to date".
run_updating "" \
    'wrangler 3.0.0 4.0.0' \
    '{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    1 wrrangler || fail "a typo'd named-scope update must not fail"
grep -q 'no installed npm CLIs among the named bins; nothing to update' "$NPM_OUT" \
    || fail "a named bin with no installed candidate must say so"
! grep -q 'npm outdated' "$FNM_LOG" \
    || fail "a named bin with no installed candidate must not run the outdated query"
! grep -q 'up to date' "$NPM_OUT" \
    || fail "a filtered-out named scope must never claim up to date"

# npm can list a package whose current already equals latest; the parser
# must not feed that to the frame as an "update" (upgrading a tool to the
# version it already runs). Needs the host node — the mock then runs the
# real JavaScript parser rather than the pre-rendered lines.
if [[ -n "${MOCK_HOST_NODE:-}" ]]; then
    run_updating "" \
        '' \
        '{"wrangler":{"current":"4.0.0","latest":"4.0.0"}}' \
        1 || fail "a current==latest npm report must not fail"
    grep -q 'all installed npm CLIs are up to date' "$NPM_OUT" \
        || fail "current==latest must be reported as up to date"
    [[ "$(grep -c 'update available: ' "$NPM_OUT" || true)" == 0 ]] \
        || fail "current==latest must not list an update"
    [[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
        || fail "current==latest must not trigger an install"
fi

run_updating wrangler \
    '@biomejs/biome 1.0.0 2.0.0
wrangler 3.0.0 4.0.0' \
    '{"@biomejs/biome":{"current":"1.0.0","latest":"2.0.0"},"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    1 wrangler || fail "an approved named-scope update must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "a named scope must upgrade exactly the named approved row"
! grep -qE -- '@biomejs/biome@latest' "$FNM_LOG" \
    || fail "an unnamed row must not be upgraded under a named scope"

# Non-interactive without pre-approval: nothing upgrades, and it says so.
run_updating "" \
    'wrangler 3.0.0 4.0.0' \
    '{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    1 || fail "a declined update run must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "without pre-approval a non-interactive update must install nothing"
grep -q 'no npm CLIs approved' "$NPM_OUT" \
    || fail "a fully declined update must say so"

# A failed query is an error, never "all up to date".
if run_updating "" '' '{"error":{"code":"ENETUNREACH"}}' 254; then
    fail "a failed outdated query must propagate as failure"
fi
grep -q 'query failed' "$NPM_OUT" \
    || fail "a failed outdated query must be reported"
! grep -q 'up to date' "$NPM_OUT" \
    || fail "a failed query must never be reported as up to date"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "a failed query must not trigger any install"

# Legacy var fallback: DOTFILES_ACCEPT_INSTALLS still pre-approves.
: > "$FNM_LOG"
HOME="$NPM_UPDATE_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_INSTALLS=wrangler \
    MOCK_OUTDATED_LINES='wrangler 3.0.0 4.0.0' \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --update wrangler >"$NPM_OUT" 2>&1 \
    || fail "the legacy accept var must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "the legacy accept var must pre-approve the update"

# Uninstall (--uninstall): same registry and authorization; the argument
# narrows the candidates to named bins, without arguments every installed row
# is a candidate. Seat biome/stylua/wrangler from the update block above.
# run_uninstalling <accept> [bin…]
run_uninstalling() {
    local accept="$1"; shift
    : > "$FNM_LOG"
    HOME="$NPM_UPDATE_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS="$accept" \
        PATH="$NPM_BIN:/usr/bin:/bin" \
        bash "$ROOT/_install/install-by-npm.sh" --uninstall "$@" >"$NPM_OUT" 2>&1
}

# Named + pre-approved: exactly that package goes through npm uninstall;
# --always rows stay unless named (the registry is the desired state, an
# uninstalled baseline row returns on the next install run).
run_uninstalling wrangler wrangler || fail "a named approved uninstall must not fail"
[[ "$(grep -c 'npm uninstall -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "accepting wrangler must uninstall exactly one package"
grep -qE -- 'npm uninstall -g --prefix [^ ]+ wrangler$' "$FNM_LOG" \
    || fail "the wrangler uninstall must name its own package"
! grep -qE -- '@biomejs/biome|stylua-bin' "$FNM_LOG" \
    || fail "an unnamed row must not be uninstalled"

# Named but not installed: a clean no-op that names its scope honestly.
run_uninstalling codex codex || fail "uninstalling a missing CLI must not fail"
grep -q 'no installed npm CLIs among the named bins; nothing to uninstall' "$NPM_OUT" \
    || fail "uninstalling a missing CLI must say so"
[[ "$(grep -c 'npm uninstall -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "uninstalling a missing CLI must not run any uninstall"

# Non-interactive without pre-approval: nothing uninstalls.
run_uninstalling "" || fail "a declined uninstall run must not fail"
[[ "$(grep -c 'npm uninstall -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "without pre-approval a non-interactive uninstall must remove nothing"
grep -q 'no npm CLIs approved for uninstall' "$NPM_OUT" \
    || fail "a fully declined uninstall must say so"

# Unknown options fail loudly (the driver is shared across channels), and
# rejection happens before any runtime work — a stray dash after a verb must
# never reach fnm/npm.
if bash "$ROOT/_install/install-by-npm.sh" --bogus >/dev/null 2>&1; then
    fail "an unknown option must fail"
fi
: > "$FNM_LOG"
if bash "$ROOT/_install/install-by-npm.sh" --update --bogus >/dev/null 2>&1; then
    fail "an unknown option after a verb must fail"
fi
[[ ! -s "$FNM_LOG" ]] \
    || fail "argument rejection must happen before any runtime work"

# --help is answered before any runtime work, without touching the network.
: > "$FNM_LOG"
bash "$ROOT/_install/install-by-npm.sh" --help >"$TMP/npm-help.out" 2>&1 \
    || fail "--help must exit successfully"
grep -q 'usage:' "$TMP/npm-help.out" || fail "--help must print usage"
[[ ! -s "$FNM_LOG" ]] || fail "--help must not run any npm command"

# --status is read-only: it lists installed rows and their update state, and
# never installs/upgrades/uninstalls anything.
: > "$FNM_LOG"
HOME="$NPM_UPDATE_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_OUTDATED_LINES='wrangler 3.0.0 4.0.0' \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --status >"$NPM_OUT" 2>&1 \
    || fail "--status must not fail"
grep -q 'update available: wrangler' "$NPM_OUT" \
    || fail "--status must report the outdated row"
grep -q 'biome (@biomejs/biome) up to date' "$NPM_OUT" \
    || fail "--status must list an up-to-date installed row"
grep -q 'codex (@openai/codex) missing' "$NPM_OUT" \
    || fail "--status must list missing registered rows"
grep -q 'summary: 3 installed, 1 outdated' "$NPM_OUT" \
    || fail "--status must print a summary line"
[[ "$(grep -c 'npm install -g \|npm uninstall -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "--status must never mutate"

# --outdated is the machine verb: stdout carries only data rows (or nothing),
# never messages — even when the caller forgot CLI_MACHINE_OUTPUT.
bash "$ROOT/_install/install-by-npm.sh" --outdated wrrangler \
    >"$TMP/npm-outdated-pure.out" 2>/dev/null \
    || fail "--outdated must not fail for a foreign name"
[[ ! -s "$TMP/npm-outdated-pure.out" ]] \
    || fail "--outdated stdout must stay data-only"

# The uv channel needs a `uv` runtime; a missing runtime must degrade to a
# clean skip, not an error. Simulate a machine without uv by exposing a PATH
# that holds only the few commands the script needs — never `uv`.
NOUV_BIN="$TMP/nouv-bin"
mkdir -p "$NOUV_BIN"
for cmd in env dirname bash; do
    ln -sf "$(command -v "$cmd")" "$NOUV_BIN/$cmd"
done
UV_HOME="$TMP/uv-home"
mkdir -p "$UV_HOME"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NOUV_BIN:/nonexistent" \
    bash "$ROOT/_install/install-by-uv.sh" >"$TMP/uv-missing.out" 2>&1 \
    || fail "missing uv must skip cleanly"
grep -q 'skipping Python CLI lifecycle' "$TMP/uv-missing.out" \
    || fail "missing uv must warn and skip"

# With a runtime present, ruff/yt-dlp install via `uv tool install`.
MOCK_UV="$TMP/mock-uv"
mkdir -p "$MOCK_UV"
cat > "$MOCK_UV/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UV_LOG"
if [[ "$1 $2" == "tool list" && "$*" == *--outdated* ]]; then
    # Fixture-driven text form: "name vX [latest: Y]" + "- " detail lines.
    if [[ -n "${MOCK_UV_OUTDATED:-}" ]]; then
        printf '%s\n' "$MOCK_UV_OUTDATED"
    fi
    exit "${MOCK_UV_OUTDATED_EXIT:-0}"
fi
EOF
chmod +x "$MOCK_UV/uv"
export UV_LOG="$TMP/uv.log"
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" >"$TMP/uv-install.out" 2>&1 \
    || fail "installing uv CLIs must not fail"
grep -q 'tool install ruff' "$UV_LOG" \
    || fail "ruff should install via uv tool"
grep -q 'tool install yt-dlp' "$UV_LOG" \
    || fail "yt-dlp should install via uv tool"
[[ "$(grep -c 'tool install ' "$UV_LOG" || true)" == 2 ]] \
    || fail "exactly ruff and yt-dlp should be installed"

# The uv channel detects via PATH (not just ~/.local/bin): a ruff/yt-dlp
# already seated elsewhere on PATH must not be reinstalled into the canonical
# prefix.
mkdir -p "$TMP/uv-elsewhere"
touch "$TMP/uv-elsewhere/ruff" "$TMP/uv-elsewhere/yt-dlp"
chmod +x "$TMP/uv-elsewhere/ruff" "$TMP/uv-elsewhere/yt-dlp"
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$TMP/uv-elsewhere:$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" >"$TMP/uv-path.out" 2>&1
[[ ! -s "$UV_LOG" ]] \
    || fail "a uv CLI already on PATH must not be reinstalled"

# Upgrades (--update): same registry and authorization as installs; uv's own
# outdated view gates the candidates, and upgrades go through uv tool upgrade.
# Candidates are the canonical prefix only, so seat the uv-managed CLIs there.
UV_OUT="$TMP/uv-update.out"
# run_uv_updating <accept> <list-output> <list-exit> [bin…]
run_uv_updating() {
    local accept="$1" list="$2" list_exit="$3"
    shift 3
    : > "$UV_LOG"
    HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS="$accept" \
        MOCK_UV_OUTDATED="$list" MOCK_UV_OUTDATED_EXIT="$list_exit" \
        PATH="$TMP/uv-elsewhere:$MOCK_UV:/usr/bin:/bin" \
        bash "$ROOT/_install/install-by-uv.sh" --update "$@" >"$UV_OUT" 2>&1
}
mkdir -p "$UV_HOME/.local/bin"
touch "$UV_HOME/.local/bin/ruff" "$UV_HOME/.local/bin/yt-dlp"
chmod +x "$UV_HOME/.local/bin/ruff" "$UV_HOME/.local/bin/yt-dlp"

# Nothing outdated: reported and nothing upgraded.
run_uv_updating "" '' 0 || fail "a clean uv outdated query must not fail"
grep -q 'up to date' "$UV_OUT" \
    || fail "an outdated-free uv tree must report up to date"
[[ "$(grep -c 'tool upgrade' "$UV_LOG" || true)" == 0 ]] \
    || fail "an outdated-free uv tree must not run any upgrade"

# Partial pre-approval: exactly the approved tool upgrades via uv tool upgrade.
run_uv_updating ruff \
    'ruff v0.16.5 [latest: 0.17.0]
- ruff
yt-dlp v2025.1.1 [latest: 2025.10.1]
- yt-dlp' \
    0 || fail "a partial-approval uv update must not fail"
[[ "$(grep -c 'tool upgrade' "$UV_LOG" || true)" == 1 ]] \
    || fail "accepting ruff must upgrade exactly one uv tool"
grep -q '^tool upgrade ruff$' "$UV_LOG" \
    || fail "the ruff upgrade must go through uv tool upgrade"
! grep -q 'tool upgrade yt-dlp' "$UV_LOG" \
    || fail "an unapproved uv tool must not be upgraded"

# Non-interactive without pre-approval: nothing upgrades.
run_uv_updating "" \
    'ruff v0.16.5 [latest: 0.17.0]
- ruff' \
    0 || fail "a declined uv update run must not fail"
[[ "$(grep -c 'tool upgrade' "$UV_LOG" || true)" == 0 ]] \
    || fail "without pre-approval a non-interactive uv update must install nothing"
grep -q 'no uv tool CLIs approved' "$UV_OUT" \
    || fail "a fully declined uv update must say so"

# A failed outdated query is an error, never "all up to date".
if run_uv_updating "" '' 3; then
    fail "a failed uv outdated query must propagate as failure"
fi
grep -q 'query via uv tool failed' "$UV_OUT" \
    || fail "a failed uv query must be reported"
! grep -q 'up to date' "$UV_OUT" \
    || fail "a failed uv query must never be reported as up to date"
[[ "$(grep -c 'tool upgrade' "$UV_LOG" || true)" == 0 ]] \
    || fail "a failed uv query must not trigger any upgrade"

# A named scope narrows the uv upgrade to the named bin.
run_uv_updating yt-dlp \
    'ruff v0.16.5 [latest: 0.17.0]
- ruff
yt-dlp v2025.1.1 [latest: 2025.10.1]
- yt-dlp' \
    0 yt-dlp || fail "a named-scope uv update must not fail"
[[ "$(grep -c 'tool upgrade' "$UV_LOG" || true)" == 1 ]] \
    || fail "a named scope must upgrade exactly one uv tool"
grep -q '^tool upgrade yt-dlp$' "$UV_LOG" \
    || fail "the named uv tool must be the one upgraded"
! grep -q 'tool upgrade ruff' "$UV_LOG" \
    || fail "an unnamed uv tool must not be upgraded under a named scope"

# A named bin with no installed uv candidate (typo or foreign install)
# short-circuits before the query: no uv outdated round-trip, an honest
# nothing-to-do message, never a false "up to date".
run_uv_updating "" '' 0 wrangler || fail "a foreign-named uv update must not fail"
grep -q 'no installed uv tool CLIs among the named bins; nothing to update' "$UV_OUT" \
    || fail "a foreign-named uv update must say so"
[[ ! -s "$UV_LOG" ]] \
    || fail "a foreign-named uv update must not run any uv command"

# Uninstall: removal goes through uv's native verb, named scope only, and
# only from the canonical prefix.
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=ruff \
    PATH="$TMP/uv-elsewhere:$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --uninstall ruff >"$UV_OUT" 2>&1 \
    || fail "a uv uninstall run must not fail"
grep -q '^tool uninstall ruff$' "$UV_LOG" \
    || fail "the ruff removal must go through uv tool uninstall"
! grep -q 'tool uninstall yt-dlp' "$UV_LOG" \
    || fail "an unnamed uv tool must not be uninstalled"

# P0 regression: a foreign same-named binary on PATH (e.g. Homebrew's yt-dlp)
# is not a candidate — mutations only act on the canonical prefix, so
# `uv tool uninstall` is never asked to remove something it does not own.
rm -f "$UV_HOME/.local/bin/yt-dlp"
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=yt-dlp \
    PATH="$TMP/uv-elsewhere:$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --uninstall yt-dlp >"$UV_OUT" 2>&1 \
    || fail "a PATH-only uv CLI must not fail the uninstall run"
grep -q 'no installed uv tool CLIs among the named bins; nothing to uninstall' "$UV_OUT" \
    || fail "a PATH-only uv CLI must not be an uninstall candidate"
[[ "$(grep -c 'tool uninstall' "$UV_LOG" || true)" == 0 ]] \
    || fail "a PATH-only uv CLI must never reach uv tool uninstall"
[[ -x "$TMP/uv-elsewhere/yt-dlp" ]] \
    || fail "a PATH-only yt-dlp must stay untouched"
# Restore the canonical seat for any later tests.
touch "$UV_HOME/.local/bin/yt-dlp"
chmod +x "$UV_HOME/.local/bin/yt-dlp"

# The Go channel needs a `go` runtime; a missing runtime must degrade to a
# clean skip, not an error. Simulate a machine without Go by exposing a PATH
# that holds only the few commands the script needs (env/dirname) — never `go`
# — so this branch fails identically on machines that already have Go installed.
NOGO_BIN="$TMP/nogo-bin"
mkdir -p "$NOGO_BIN"
for cmd in env dirname bash; do
    ln -sf "$(command -v "$cmd")" "$NOGO_BIN/$cmd"
done
GO_HOME="$TMP/go-home"
mkdir -p "$GO_HOME"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NOGO_BIN:/nonexistent" \
    bash "$ROOT/_install/install-by-go.sh" >"$TMP/go-missing.out" 2>&1 \
    || fail "missing go must skip cleanly"
grep -q 'skipping Go CLI lifecycle' "$TMP/go-missing.out" \
    || fail "missing go must warn and skip"

# With a runtime present, gopls/gofumpt install into ~/.local/bin (GOBIN) —
# the same CLI prefix as the npm/uv channels — via `go install tool@latest`.
# Clear any Go layout the developer's shell exported, so the run starts clean.
unset GOBIN GOMODCACHE

MOCK_GO="$TMP/mock-go"
mkdir -p "$MOCK_GO"
cat > "$MOCK_GO/go" <<'EOF'
#!/usr/bin/env bash
# `go install` records to the install log. `go env GOENV` is the only `go env`
# the script reads: it points at the file under test ($GO_ENV_FILE), so a clean
# machine with no GOENV file is never mistaken for user config. `go env -w`
# records the persisted keys so the test can assert what is written.
if [[ "$1" == install ]]; then
    printf 'GOBIN=%s tool=%s\n' "${GOBIN:-<unset>}" "$2" >> "$GO_LOG"
elif [[ "$1" == env && "$2" == -w ]]; then
    shift 2
    printf '%s\n' "$@" >> "$GO_WRITE_LOG"
elif [[ "$1" == env && "$2" == GOENV ]]; then
    printf '%s\n' "${GO_ENV_FILE:-}"
elif [[ "$1" == version && "$2" == -m ]]; then
    # Emulate the embedded module metadata: "mod\t<pkg>\t<version>" keyed by
    # the binary basename via MOCK_GO_PKG_<bin>/MOCK_GO_CUR_<bin>.
    name="$(basename "$3")"
    eval "pkg=\${MOCK_GO_PKG_$name:-}; cur=\${MOCK_GO_CUR_$name:-}"
    printf 'mod\t%s\t%s\n' "$pkg" "$cur"
elif [[ "$1" == list && "$2" == -m ]]; then
    # Emulate the module proxy: "path version" lines (the -f template form),
    # one per requested module, keyed by the module path with
    # non-alphanumerics folded to underscores. Recorded so tests can assert
    # the proxy was (or was not) queried at all. MOCK_GO_LIST_FAIL forces a
    # proxy error so the failure path is exercised.
    if [[ -n "${MOCK_GO_LIST_FAIL:-}" ]]; then
        printf '%s\n' 'proxy unreachable' >&2
        exit "${MOCK_GO_LIST_FAIL}"
    fi
    printf 'list %s\n' "$*" >> "$GO_LOG"
    shift 4   # drop list -m -f <template>
    for spec in "$@"; do
        pkg="${spec%@latest}"
        key="${pkg//[^a-zA-Z0-9]/_}"
        eval "lat=\${MOCK_GO_LAT_$key:-}"
        printf '%s %s\n' "$pkg" "$lat"
    done
fi
EOF
chmod +x "$MOCK_GO/go"
export GO_LOG="$TMP/go.log" GO_WRITE_LOG="$TMP/go-write.log"
: > "$GO_LOG"
: > "$GO_WRITE_LOG"

# A failed `go env -w` is best effort, not fatal: the tools must still install
# into ~/.local/bin.
BAD_GO="$TMP/bad-go"
cat > "$BAD_GO" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == env && "$2" == -w ]]; then
    printf 'go env is disabled\n' >&2
    exit 1
fi
if [[ "$1" == install ]]; then
    printf 'GOBIN=%s tool=%s\n' "${GOBIN:-<unset>}" "$2" >> "$GO_LOG"
fi
EOF
chmod +x "$BAD_GO"
: > "$GO_LOG"
if ! HOME="$GO_HOME" PATH="$TMP:/usr/bin:/bin" GO_LOG="$GO_LOG" \
    bash -c 'mkdir -p "$0"; ln -sf "$1" "$0/go"; PATH="$0:/usr/bin:/bin" bash "$2/_install/install-by-go.sh"' \
    "$TMP/bad-go-bin" "$BAD_GO" "$ROOT" >"$TMP/go-bad.out" 2>&1; then
    fail "a failed go env -w must not fail the Go channel"
fi
grep -q 'go env -w failed' "$TMP/go-bad.out" \
    || fail "a failed go env -w must be reported"
[[ "$(grep -c 'tool=' "$GO_LOG")" == 2 ]] \
    || fail "tools must still install after a failed go env -w"

# Only a value the user actually set is reported, from two sources: persisted
# in GOENV, or exported in the shell. Go's built-in defaults (exercised by the
# clean run below) must never trigger a warning.
printf 'GOMODCACHE=%s\n' "$TMP/old-mod" > "$TMP/goenv"
: > "$GO_LOG"
HOME="$GO_HOME" PATH="$MOCK_GO:/usr/bin:/bin" GO_LOG="$GO_LOG" \
    GO_ENV_FILE="$TMP/goenv" \
    bash "$ROOT/_install/install-by-go.sh" >"$TMP/go-file.out" 2>&1 \
    || fail "a value persisted in GOENV must not fail the channel"
grep -q "GOMODCACHE=$TMP/old-mod in $TMP/goenv; replacing it with" "$TMP/go-file.out" \
    || fail "a value persisted in GOENV must be reported before being replaced"
[[ "$(grep -c 'tool=' "$GO_LOG")" == 2 ]] \
    || fail "tools must still install when GOENV has a differing value"

: > "$GO_LOG"
HOME="$GO_HOME" PATH="$MOCK_GO:/usr/bin:/bin" GO_LOG="$GO_LOG" \
    GOMODCACHE="$TMP/exported-mod" \
    bash "$ROOT/_install/install-by-go.sh" >"$TMP/go-export.out" 2>&1 \
    || fail "an exported Go value must not fail the channel"
grep -q "GOMODCACHE=$TMP/exported-mod is exported in this shell" "$TMP/go-export.out" \
    || fail "an exported Go value must be reported as winning over GOENV"
[[ "$(grep -c 'tool=' "$GO_LOG")" == 2 ]] \
    || fail "tools must still install when a Go value is exported"

: > "$GO_WRITE_LOG"
HOME="$GO_HOME" PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" >"$TMP/go-install.out" 2>&1
# A clean machine (only Go's built-in defaults) must not warn.
! grep -qE 'replacing it with|is exported in this shell' "$TMP/go-install.out" \
    || fail "Go's built-in defaults must not be reported as user config"
grep -q 'GOBIN=.*\.local/bin tool=golang.org/x/tools/gopls@latest' "$GO_LOG" \
    || fail "gopls should install into ~/.local/bin via go install"
grep -q 'GOBIN=.*\.local/bin tool=mvdan.cc/gofumpt@latest' "$GO_LOG" \
    || fail "gofumpt should install into ~/.local/bin via go install"
# GOBIN and GOMODCACHE are persisted; GOPATH is intentionally left alone.
grep -q '^GOBIN=.*\.local/bin$' "$GO_WRITE_LOG" \
    || fail "the layout write must persist GOBIN"
grep -q '^GOMODCACHE=.*\.cache/go-mod$' "$GO_WRITE_LOG" \
    || fail "the layout write must persist GOMODCACHE"
! grep -q '^GOPATH=' "$GO_WRITE_LOG" \
    || fail "GOPATH must be left untouched"

# Idempotent: CLIs already seated in the ~/.local/bin prefix are skipped.
mkdir -p "$GO_HOME/.local/bin"
touch "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
chmod +x "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
: > "$GO_LOG"
HOME="$GO_HOME" PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" >"$TMP/go-idempotent.out" 2>&1
[[ ! -s "$GO_LOG" ]] \
    || fail "existing gopls/gofumpt must not be reinstalled"
! grep -q 'not found' "$TMP/go-idempotent.out" \
    || fail "installed Go CLIs must be detected and skipped"

# The uv/go channels detect via PATH, not just ~/.local/bin: a tool already
# seated elsewhere on PATH must not be reinstalled into the
# canonical prefix.
rm -f "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
mkdir -p "$TMP/elsewhere"
touch "$TMP/elsewhere/gopls" "$TMP/elsewhere/gofumpt"
chmod +x "$TMP/elsewhere/gopls" "$TMP/elsewhere/gofumpt"
: > "$GO_LOG"
HOME="$GO_HOME" PATH="$TMP/elsewhere:$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" >"$TMP/go-path.out" 2>&1
[[ ! -s "$GO_LOG" ]] \
    || fail "a CLI already on PATH must not be reinstalled into ~/.local/bin"

# Upgrades (--update): same registry and authorization; current versions come
# from the binaries' embedded module metadata, latest from the module proxy.
# gopls is outdated, gofumpt is current — only gopls may be offered.
mkdir -p "$GO_HOME/.local/bin"
touch "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
chmod +x "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
GO_OUT="$TMP/go-update.out"
# run_go_updating <accept>
run_go_updating() {
    : > "$GO_LOG"
    HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS="$1" \
        MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
        MOCK_GO_LAT_golang_org_x_tools_gopls=v0.19.0 \
        MOCK_GO_PKG_gofumpt=mvdan.cc/gofumpt MOCK_GO_CUR_gofumpt=v0.8.0 \
        MOCK_GO_LAT_mvdan_cc_gofumpt=v0.8.0 \
        PATH="$MOCK_GO:/usr/bin:/bin" \
        bash "$ROOT/_install/install-by-go.sh" --update >"$GO_OUT" 2>&1
}

run_go_updating gopls || fail "a go update run must not fail"
[[ "$(grep -c 'update available: ' "$GO_OUT" || true)" == 1 ]] \
    || fail "only the outdated go tool must be offered"
grep -q 'update available: gopls (golang.org/x/tools/gopls) v0.18.0 → v0.19.0' "$GO_OUT" \
    || fail "the gopls update line must name its module and both versions"
[[ "$(grep -c 'tool=' "$GO_LOG" || true)" == 1 ]] \
    || fail "accepting gopls must run exactly one go install"
grep -q 'GOBIN=.*\.local/bin tool=golang.org/x/tools/gopls@latest' "$GO_LOG" \
    || fail "the gopls upgrade must reinstall its own module at @latest"
! grep -q 'tool=mvdan.cc/gofumpt' "$GO_LOG" \
    || fail "an up-to-date go tool must not be reinstalled"

run_go_updating "" || fail "a declined go update run must not fail"
[[ "$(grep -c 'tool=' "$GO_LOG" || true)" == 0 ]] \
    || fail "without pre-approval a non-interactive go update must install nothing"
grep -q 'no go install CLIs approved' "$GO_OUT" \
    || fail "a fully declined go update must say so"

# A failed module-proxy query is an error, never "all up to date".
: > "$GO_LOG"
if HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=gopls \
    MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
    MOCK_GO_LIST_FAIL=1 \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --update >"$GO_OUT" 2>&1; then
    fail "a failed go list -m must propagate as failure"
fi
grep -q 'go list -m failed' "$GO_OUT" \
    || fail "a failed go list -m must be reported"
! grep -q 'up to date' "$GO_OUT" \
    || fail "a failed go query must never be reported as up to date"
[[ "$(grep -c 'tool=' "$GO_LOG" || true)" == 0 ]] \
    || fail "a failed go query must not trigger any install"

# A cmd/ subpath tool: the binary embeds the parent module as its first mod
# line while the registry pkg carries the subpath. The query must key the
# proxy lookup on the embedded module path and still emit the registry pkg,
# so the frame matches the row and upgrades by the subpath at @latest.
mkdir -p "$GO_HOME/.local/bin"
touch "$GO_HOME/.local/bin/gopls"
chmod +x "$GO_HOME/.local/bin/gopls"
: > "$GO_LOG"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=gopls \
    MOCK_GO_PKG_gopls=golang.org/x/tools MOCK_GO_CUR_gopls=v0.18.0 \
    MOCK_GO_LAT_golang_org_x_tools=v0.19.0 \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --update >"$GO_OUT" 2>&1 \
    || fail "a cmd-subpath go update run must not fail"
grep -q 'update available: gopls (golang.org/x/tools/gopls) v0.18.0 → v0.19.0' "$GO_OUT" \
    || fail "a subpath tool's update line must keep the registry pkg"
grep -q 'tool=golang.org/x/tools/gopls@latest' "$GO_LOG" \
    || fail "a subpath tool must upgrade by its registry pkg at @latest"

# A named bin with no installed go candidate (typo or foreign install)
# short-circuits before the query: no embedded-metadata read, no module-proxy
# round-trip, an honest nothing-to-do message.
: > "$GO_LOG"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=wrangler \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --update wrangler >"$GO_OUT" 2>&1 \
    || fail "a foreign-named go update must not fail"
grep -q 'no installed go install CLIs among the named bins; nothing to update' "$GO_OUT" \
    || fail "a foreign-named go update must say so"
[[ ! -s "$GO_LOG" ]] \
    || fail "a foreign-named go update must not run any go query"

# Uninstall: Go has no uninstall verb; removal deletes the GOBIN binary,
# named scope only, shared GOMODCACHE untouched.
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=gopls \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --uninstall gopls >"$GO_OUT" 2>&1 \
    || fail "a go uninstall run must not fail"
[[ ! -e "$GO_HOME/.local/bin/gopls" ]] \
    || fail "the gopls binary must be removed"
[[ -x "$GO_HOME/.local/bin/gofumpt" ]] \
    || fail "an unnamed go tool must stay"

# P0 regression: a foreign same-named binary on PATH is not a candidate —
# mutations only act on the canonical prefix, so go never rm's an absent bin
# and never lies about removing a tool it does not own.
rm -f "$GO_HOME/.local/bin/gofumpt"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=gofumpt \
    PATH="$TMP/elsewhere:$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --uninstall gofumpt >"$GO_OUT" 2>&1 \
    || fail "a PATH-only go CLI must not fail the uninstall run"
grep -q 'no installed go install CLIs' "$GO_OUT" \
    || fail "a PATH-only go CLI must not be an uninstall candidate"
[[ -x "$TMP/elsewhere/gofumpt" ]] \
    || fail "a PATH-only gofumpt must stay untouched"
[[ -x "$TMP/elsewhere/gopls" ]] \
    || fail "a PATH-only gopls must stay untouched"

# The unified entrypoint routes bins to their owning channel: an unknown bin
# fails once (no per-channel guessing), and a known bin only invokes its own
# channel — other ecosystems never speak.
MANAGE_OUT="$TMP/manage.out"
: > "$FNM_LOG"
if HOME="$NPM_UPDATE_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/manage-tools.sh" update wrangler-typo >"$MANAGE_OUT" 2>&1; then
    fail "an unknown bin must fail the unified entrypoint"
fi
grep -q 'unknown bin' "$MANAGE_OUT" \
    || fail "an unknown bin must be reported once by the entrypoint"
[[ ! -s "$FNM_LOG" ]] \
    || fail "an unknown bin must not run any channel"

: > "$FNM_LOG"
HOME="$NPM_UPDATE_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=wrangler \
    MOCK_OUTDATED_LINES='wrangler 3.0.0 4.0.0' \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/manage-tools.sh" update wrangler >"$MANAGE_OUT" 2>&1 \
    || fail "a routed update must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "routing wrangler must update exactly the npm row"
! grep -q 'no installed uv tool CLIs\|no installed go install CLIs' "$MANAGE_OUT" \
    || fail "a routed update must not make other channels speak"

# The unified entrypoint merges channels: one combined list, ONE confirm, and
# each approved bin updates through its own channel — never re-asking.
MERGE_HOME="$TMP/merge-home"
MERGE_OUT="$TMP/merge.out"
mkdir -p "$MERGE_HOME/.local/bin"
for b in wrangler ruff yt-dlp gopls gofumpt; do
    touch "$MERGE_HOME/.local/bin/$b"
    chmod +x "$MERGE_HOME/.local/bin/$b"
done
: > "$FNM_LOG"; : > "$UV_LOG"; : > "$GO_LOG"
printf 'y\n' | HOME="$MERGE_HOME" \
    MOCK_OUTDATED_LINES='wrangler 3.0.0 4.0.0' \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    MOCK_OUTDATED_EXIT=1 \
    MOCK_UV_OUTDATED='ruff v0.16.5 [latest: 0.17.0]
- ruff' \
    MOCK_UV_OUTDATED_EXIT=0 \
    MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
    MOCK_GO_LAT_golang_org_x_tools_gopls=v0.19.0 \
    MOCK_GO_PKG_gofumpt=mvdan.cc/gofumpt MOCK_GO_CUR_gofumpt=v0.8.0 \
    MOCK_GO_LAT_mvdan_cc_gofumpt=v0.8.0 \
    PATH="$NPM_BIN:$MOCK_UV:$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/manage-tools.sh" update >"$MERGE_OUT" 2>&1 \
    || fail "a merged update must not fail"
# One 'y' on stdin approves all three rows — proof of a single merged confirm:
# were it per-channel, the first read would consume the 'y' and the rest would
# hit EOF and decline. (read -p suppresses its prompt on a pipe, so the
# prompt text itself cannot be asserted here.)
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "the merged update must update the npm row"
grep -q '^tool upgrade ruff$' "$UV_LOG" \
    || fail "the merged update must upgrade the uv row"
grep -q 'tool=golang.org/x/tools/gopls@latest' "$GO_LOG" \
    || fail "the merged update must reinstall the go row"
! grep -q 'tool upgrade yt-dlp' "$UV_LOG" \
    || fail "an up-to-date uv row must not be upgraded"
# The known-outdated path skips the second query: each channel queries exactly
# once (during collection), never again on execution.
[[ "$(grep -c 'npm outdated' "$FNM_LOG" || true)" == 1 ]] \
    || fail "the merged update must query npm outdated exactly once"
[[ "$(grep -c 'tool list --outdated' "$UV_LOG" || true)" == 1 ]] \
    || fail "the merged update must query uv outdated exactly once"
[[ "$(grep -c '^list ' "$GO_LOG" || true)" == 1 ]] \
    || fail "the merged update must query the go proxy exactly once"

# A channel whose query fails is skipped, not fatal: the others still update,
# and the aggregate exit code reports the failure.
: > "$FNM_LOG"; : > "$UV_LOG"; : > "$GO_LOG"
if printf 'y\n' | HOME="$MERGE_HOME" \
    MOCK_OUTDATED_JSON='{"error":{"code":"ENETUNREACH"}}' \
    MOCK_OUTDATED_EXIT=254 \
    MOCK_UV_OUTDATED='ruff v0.16.5 [latest: 0.17.0]
- ruff' \
    MOCK_UV_OUTDATED_EXIT=0 \
    MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
    MOCK_GO_LAT_golang_org_x_tools_gopls=v0.19.0 \
    PATH="$NPM_BIN:$MOCK_UV:$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/manage-tools.sh" update >"$MERGE_OUT" 2>&1; then
    fail "a failed channel query must propagate as failure"
fi
grep -q 'skipping npm' "$MERGE_OUT" \
    || fail "a failed channel query must name the skipped channel"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "the failed channel must not update"
grep -q '^tool upgrade ruff$' "$UV_LOG" \
    || fail "a healthy channel must still update after another channel fails"
grep -q 'tool=golang.org/x/tools/gopls@latest' "$GO_LOG" \
    || fail "the go channel must still update after npm fails"

# Under a named scope the all-clear never overreaches: an up-to-date named
# bin must not claim every installed CLI is current (an unnamed row is
# outdated in the fixture).
: > "$FNM_LOG"
HOME="$NPM_UPDATE_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_OUTDATED_LINES='wrangler 3.0.0 4.0.0' \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' \
    MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/manage-tools.sh" update biome >"$MANAGE_OUT" 2>&1 \
    || fail "a named up-to-date update must not fail"
grep -q 'no named CLIs need updating' "$MANAGE_OUT" \
    || fail "a named scope with nothing outdated must say so"
! grep -q 'all installed CLIs are up to date' "$MANAGE_OUT" \
    || fail "a named scope must never claim all installed CLIs are up to date"

# install-tools routes and narrows: only the named row installs, the
# channel's other missing rows stay untouched.
INST_HOME="$TMP/install-narrow-home"
mkdir -p "$INST_HOME/.local/bin"
: > "$FNM_LOG"
HOME="$INST_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/manage-tools.sh" install biome >"$TMP/install-narrow.out" 2>&1 \
    || fail "a narrowed install must not fail"
grep -q '@biomejs/biome' "$FNM_LOG" \
    || fail "the named row must be installed"
! grep -q 'stylua-bin' "$FNM_LOG" \
    || fail "an unnamed row must not install under a named scope"

# Uninstall routes through the owning channel's native verb, named only.
: > "$UV_LOG"
HOME="$MERGE_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=yt-dlp \
    PATH="$NPM_BIN:$MOCK_UV:$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/manage-tools.sh" uninstall yt-dlp >"$MANAGE_OUT" 2>&1 \
    || fail "a routed uninstall must not fail"
grep -q '^tool uninstall yt-dlp$' "$UV_LOG" \
    || fail "the routed uninstall must go through uv tool uninstall"
! grep -q 'tool uninstall ruff' "$UV_LOG" \
    || fail "an unnamed uv row must stay"

# Unified status is read-only: it queries but never installs.
: > "$FNM_LOG"
HOME="$NPM_UPDATE_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_OUTDATED_JSON='{}' MOCK_OUTDATED_EXIT=0 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/manage-tools.sh" status biome >"$MANAGE_OUT" 2>&1 \
    || fail "a unified status must not fail"
grep -q 'summary:' "$MANAGE_OUT" \
    || fail "unified status must print a summary"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "unified status must never install"

# Default official downloads run without prompting and use hardened HTTPS flags.
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0'
EOF
chmod +x "$MOCK_BIN/curl"
export CURL_LOG="$TMP/curl.log"

HOME="$TMP/home" PATH="$MOCK_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-curl.sh" >/dev/null
[[ "$(wc -l < "$CURL_LOG" | tr -d ' ')" == 3 ]] \
    || fail "default tools should download all three official installers without prompting"
while IFS= read -r args; do
    [[ "$args" == *"--proto =https"* ]] || fail "curl must require HTTPS"
    [[ "$args" == *"--tlsv1.2"* ]] || fail "curl must require TLS 1.2 or newer"
    [[ "$args" == *"--fail"* && "$args" == *"--show-error"* && "$args" == *"--location"* ]] \
        || fail "curl must use hardened failure and redirect handling"
done < "$CURL_LOG"

echo "PASS installer orchestration tests"

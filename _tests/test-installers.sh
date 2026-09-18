#!/usr/bin/env bash
# test-installers.sh — behavior tests for ecosystem installer orchestration
# Usage: bash _tests/test-installers.sh

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/installers-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Accepted installer failures must propagate to the caller.
# shellcheck disable=SC1091
source "$ROOT/_scripts/common.sh"
failed_install() { return 7; }

DOTFILES_NON_INTERACTIVE=1 install_with_prompt \
    missing-optional "install missing-optional?" failed_install "installed" \
    >/dev/null || fail "declining an optional installer should return success"
unset DOTFILES_NON_INTERACTIVE
if printf 'y\n' | install_with_prompt \
    missing-optional "install missing-optional?" failed_install "installed" >/dev/null; then
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

# Optional npm CLIs (pi/codex/opencode/codegraph/wrangler) are interactive-only:
# non-interactive mode declines all of them, while an interactive run
# installs only the explicitly accepted tool.
NPM_HOME="$TMP/npm-home"
NPM_BIN="$TMP/npm-bin"
FNM_PREFIX="$TMP/fnm-prefix"
mkdir -p "$NPM_HOME/.local/bin" "$NPM_BIN" "$FNM_PREFIX/bin"
touch "$NPM_HOME/.local/bin/biome"
chmod +x "$NPM_HOME/.local/bin/biome"
# stylua installs unconditionally (no interactive prompt), so seat it now
# to keep the prompt-flow tests below free of an extra install call.
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
fi
EOF
chmod +x "$NPM_BIN/fnm"
export FNM_LOG="$TMP/fnm.log"
export FNM_PREFIX

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

HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >/dev/null
grep -q '@earendil-works/pi-coding-agent\|@openai/codex\|opencode-ai\|wrangler\|@colbymchenry/codegraph' "$FNM_LOG" \
    && fail "non-interactive mode should decline optional CLI installs"

: > "$FNM_LOG"
printf 'n\ny\nn\nn\nn\n' | HOME="$NPM_HOME" PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >/dev/null
grep -q '@openai/codex' "$FNM_LOG" \
    || fail "accepting codex should invoke its npm install"
grep -q '@earendil-works/pi-coding-agent\|opencode-ai\|wrangler\|@colbymchenry/codegraph' "$FNM_LOG" \
    && fail "declining pi/opencode/wrangler/codegraph should not invoke their npm installs"

: > "$FNM_LOG"
# opencode's postinstall copies its platform binary into bin/; accepting
# opencode must carry --allow-scripts (the mock npm understands it).
printf 'n\nn\ny\nn\nn\n' | HOME="$NPM_HOME" PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >/dev/null
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=opencode-ai opencode-ai' "$FNM_LOG" \
    || fail "accepting opencode should install to ~/.local with --allow-scripts"

: > "$FNM_LOG"
# codegraph ships a launcher shim with no lifecycle scripts; accepting it must
# run a plain global install, without --allow-scripts.
printf 'n\nn\nn\ny\nn\n' | HOME="$NPM_HOME" PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >/dev/null
grep -qE -- 'npm install -g --prefix [^ ]+ @colbymchenry/codegraph' "$FNM_LOG" \
    || fail "accepting codegraph should run a plain global npm install into ~/.local"

: > "$FNM_LOG"
# wrangler relies on workerd/esbuild whose postinstall seeds native binaries;
# accepting wrangler must carry --allow-scripts (the mock npm understands it).
printf 'n\nn\nn\nn\ny\n' | HOME="$NPM_HOME" PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >/dev/null
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=esbuild,workerd wrangler' "$FNM_LOG" \
    || fail "accepting wrangler should install to ~/.local with --allow-scripts"

for cli in pi codex opencode codegraph wrangler; do
    touch "$NPM_HOME/.local/bin/$cli"
    chmod +x "$NPM_HOME/.local/bin/$cli"
done

# Global CLIs install into ~/.local, which may not be on the parent shell's
# PATH. They must still be detected and must not trigger duplicate-install prompts.
FNM_OUTPUT="$TMP/fnm-detection.out"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >"$FNM_OUTPUT"
! grep -q 'pi not found\|codex not found\|opencode not found\|wrangler not found\|codegraph not found\|stylua not found' "$FNM_OUTPUT" \
    || fail "CLIs in the ~/.local prefix must be detected outside the parent PATH"

# A runtime without npm must degrade to a clean skip, not an error.
FNM_PREFIX="" HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >"$TMP/npm-missing.out" 2>&1 \
    || fail "missing npm must skip cleanly"
grep -q 'skipping npm CLI installs' "$TMP/npm-missing.out" \
    || fail "missing npm must warn and skip"

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
grep -q 'skipping Go CLI installs' "$TMP/go-missing.out" \
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

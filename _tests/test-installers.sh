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

# pkg-linux must try every ecosystem installer before returning a failure summary.
INSTALLER_REPO="$TMP/repo"
mkdir -p "$INSTALLER_REPO/_install"
for installer in install-by-curl.sh install-by-npm.sh install-by-uv.sh install-by-cargo.sh; do
    cat > "$INSTALLER_REPO/_install/$installer" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$(basename "$0")" >> "$INSTALLER_LOG"
[[ "$(basename "$0")" != "install-by-npm.sh" ]]
EOF
done
export INSTALLER_LOG="$TMP/installer.log"
# shellcheck disable=SC1091
source "$ROOT/_bootstrap/pkg-linux.sh"
DOTFILES_DIR="$INSTALLER_REPO"
if install_ecosystem_tools > "$TMP/ecosystem.out" 2>&1; then
    fail "an ecosystem installer failure must propagate"
fi
[[ "$(wc -l < "$INSTALLER_LOG" | tr -d ' ')" == 4 ]] \
    || fail "all ecosystem installers must run even when one fails"
grep -q 'install-by-npm.sh' "$TMP/ecosystem.out" \
    || fail "the failure summary must name the failed installer"

# AI CLIs are optional: non-interactive mode declines all three, while an
# interactive run installs only the explicitly accepted tool.
NPM_HOME="$TMP/npm-home"
NPM_BIN="$TMP/npm-bin"
FNM_PREFIX="$TMP/fnm-prefix"
mkdir -p "$NPM_HOME/.local/bin" "$NPM_BIN" "$FNM_PREFIX/bin"
touch "$NPM_HOME/.local/bin/biome"
chmod +x "$NPM_HOME/.local/bin/biome"
cat > "$NPM_BIN/fnm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FNM_LOG"
if [[ "$*" == *'node --version'* ]]; then
    printf '%s\n' 'v24.0.0'
elif [[ "$*" == *'npm --version'* ]]; then
    printf '%s\n' '11.9.0'
elif [[ "$*" == *'npm prefix -g'* ]]; then
    printf '%s\n' "$FNM_PREFIX"
fi
EOF
chmod +x "$NPM_BIN/fnm"
export FNM_LOG="$TMP/fnm.log"
export FNM_PREFIX

HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >/dev/null
grep -q '@earendil-works/pi-coding-agent\|@openai/codex\|opencode-ai' "$FNM_LOG" \
    && fail "non-interactive mode should decline optional AI CLI installs"

: > "$FNM_LOG"
printf 'n\ny\nn\n' | HOME="$NPM_HOME" PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >/dev/null
grep -q '@openai/codex' "$FNM_LOG" \
    || fail "accepting codex should invoke its npm install"
grep -q '@earendil-works/pi-coding-agent\|opencode-ai' "$FNM_LOG" \
    && fail "declining pi and opencode should not invoke their npm installs"

for cli in pi codex opencode; do
    touch "$FNM_PREFIX/bin/$cli"
    chmod +x "$FNM_PREFIX/bin/$cli"
done

# The CLIs can be installed in fnm's Node environment while remaining absent
# from the parent shell's PATH. They must not trigger duplicate-install prompts.
FNM_OUTPUT="$TMP/fnm-detection.out"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >"$FNM_OUTPUT"
! grep -q 'pi not found\|codex not found\|opencode not found' "$FNM_OUTPUT" \
    || fail "fnm-managed CLIs must be detected outside the parent PATH"

# A runtime without npm must degrade to a clean skip, not an error.
FNM_PREFIX="" HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" >"$TMP/npm-missing.out" 2>&1 \
    || fail "missing npm must skip cleanly"
grep -q 'skipping npm CLI installs' "$TMP/npm-missing.out" \
    || fail "missing npm must warn and skip"

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

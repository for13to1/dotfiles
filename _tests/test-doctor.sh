#!/usr/bin/env bash
# test-doctor.sh — exit-code contract tests for _scripts/doctor.sh
# Usage: bash _tests/test-doctor.sh
#
# Only assert doctor's exit-code semantics (the core contract):
#   clean → 0; warnings only → 0; blocking issues → non-zero
# Never grep output text, so message changes do not make the test brittle.

set -euo pipefail
# shellcheck disable=SC1091  # helpers.sh is sourced via a dynamic path
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/doctor.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

DOCTOR="$ROOT/_scripts/doctor.sh"

mkdir -p "$TMP/dotfiles/_scripts" "$TMP/dotfiles/git" "$TMP/home"
cp "$ROOT/_scripts/common.sh" "$TMP/dotfiles/_scripts/common.sh"
cp "$ROOT/_scripts/list-modules.sh" "$TMP/dotfiles/_scripts/list-modules.sh"
cp "$ROOT/_scripts/check-links.sh" "$TMP/dotfiles/_scripts/check-links.sh"
printf 'git\n' > "$TMP/dotfiles/_scripts/modules.conf"
printf 'user = test\n' > "$TMP/dotfiles/git/.gitconfig"

ln -s ../dotfiles/git/.gitconfig "$TMP/home/.gitconfig"
printf '# local zsh\n' > "$TMP/home/.zshrc.local"
printf '[user]\n' > "$TMP/home/.gitconfig.local"

# Stub every required tool: doctor's verdict must not depend on the host's toolchain.
MOCK_BIN="$TMP/bin"
mkdir -p "$MOCK_BIN"
for cmd in git stow zsh make uv ruff shellcheck; do
    cat > "$MOCK_BIN/$cmd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$MOCK_BIN/$cmd"
done

# Clean environment: exit 0.
assert_pass "synced dotfiles should exit 0" \
    env PATH="$MOCK_BIN:$PATH" bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

# Missing required command: blocking issue, exit non-zero. PATH omits ruff to
# simulate absence; hosts that ship ruff in /usr/bin cannot be simulated, so skip.
MISSING_TOOL_BIN="$TMP/bin-missing-tool"
mkdir -p "$MISSING_TOOL_BIN"
for cmd in git stow zsh make uv shellcheck; do
    ln -s "$MOCK_BIN/$cmd" "$MISSING_TOOL_BIN/$cmd"
done
if (PATH="$MISSING_TOOL_BIN:/usr/bin:/bin" command -v ruff >/dev/null 2>&1); then
    echo "SKIP missing-required assertion: ruff resolvable in /usr/bin:/bin"
else
    assert_fail "missing required command should be a blocking failure" \
        env PATH="$MISSING_TOOL_BIN:/usr/bin:/bin" bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"
fi

# Missing optional local state: warn but still exit 0.
rm -f "$TMP/home/.gitconfig" "$TMP/home/.zshrc.local" "$TMP/home/.gitconfig.local"
assert_pass "missing optional local state should warn but exit 0" \
    env PATH="$MOCK_BIN:$PATH" bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

# Missing module dir: blocking issue, exit non-zero.
rm -rf "$TMP/dotfiles/git"
assert_fail "missing stow module should be a blocking failure" \
    env PATH="$MOCK_BIN:$PATH" bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

echo "PASS doctor tests"

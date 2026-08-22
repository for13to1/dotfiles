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

# Clean environment: exit 0.
assert_pass "synced dotfiles should exit 0" \
    bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

# Missing optional local state: warn but still exit 0.
rm -f "$TMP/home/.gitconfig" "$TMP/home/.zshrc.local" "$TMP/home/.gitconfig.local"
assert_pass "missing optional local state should warn but exit 0" \
    bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

# Missing module dir: blocking issue, exit non-zero.
rm -rf "$TMP/dotfiles/git"
assert_fail "missing stow module should be a blocking failure" \
    bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

echo "PASS doctor tests"

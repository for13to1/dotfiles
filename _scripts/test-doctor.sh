#!/usr/bin/env bash
#
# test-doctor.sh - doctor.sh behavior tests
# Usage: bash _scripts/test-doctor.sh
#

set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCTOR="$ROOT/_scripts/doctor.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/doctor.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_pass() {
    local desc="$1"
    shift
    if ! "$@" >/dev/null; then
        fail "$desc"
    fi
}

assert_contains() {
    local desc="$1"
    local path="$2"
    local pattern="$3"
    grep -q -- "$pattern" "$path" || fail "$desc"
}

mkdir -p "$TMP/dotfiles/_scripts" "$TMP/dotfiles/git" "$TMP/home"
cp "$ROOT/_scripts/common.sh" "$TMP/dotfiles/_scripts/common.sh"
cp "$ROOT/_scripts/list-modules.sh" "$TMP/dotfiles/_scripts/list-modules.sh"
cp "$ROOT/_scripts/check-links.sh" "$TMP/dotfiles/_scripts/check-links.sh"
printf 'git\n' > "$TMP/dotfiles/_scripts/modules.conf"
printf 'user = test\n' > "$TMP/dotfiles/git/.gitconfig"

ln -s ../dotfiles/git/.gitconfig "$TMP/home/.gitconfig"
printf '# local zsh\n' > "$TMP/home/.zshrc.local"
printf '[user]\n' > "$TMP/home/.gitconfig.local"

assert_pass "doctor should pass for synced dotfiles" \
    bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

rm -f "$TMP/home/.gitconfig" "$TMP/home/.zshrc.local" "$TMP/home/.gitconfig.local"
if ! bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home" > "$TMP/warn.out"; then
    fail "doctor should warn but not fail for optional local state"
fi
assert_contains "doctor should report warnings" \
    "$TMP/warn.out" 'doctor completed with'
assert_contains "doctor should mention unsynced links" \
    "$TMP/warn.out" 'stow links are not fully synced'

echo "PASS doctor tests"

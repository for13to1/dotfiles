#!/usr/bin/env bash
# test-check-links.sh — behavior tests for _scripts/check-links.sh (verify/preflight and stow_find)
# Usage: bash _tests/test-check-links.sh

set -euo pipefail
# shellcheck disable=SC1091  # helpers.sh is sourced via a dynamic path
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-links.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

CHECK="$ROOT/_scripts/check-links.sh"

reset_home() {
    rm -rf "${TMP:?}/home"
    mkdir -p "$TMP/home"
}

mkdir -p "$TMP/dotfiles/git" "$TMP/home" "$TMP/wrong"
printf 'user = test\n' > "$TMP/dotfiles/git/.gitconfig"

ln -s ../dotfiles/git/.gitconfig "$TMP/home/.gitconfig"
assert_pass "verify: correct file symlink" \
    bash "$CHECK" verify "$TMP/dotfiles" "$TMP/home" git

ln -s "$TMP/dotfiles" "$TMP/dotfiles-link"
assert_pass "verify: dotfiles dir reached through symlink" \
    bash "$CHECK" verify "$TMP/dotfiles-link" "$TMP/home" git

reset_home
printf 'wrong\n' > "$TMP/wrong/other"
ln -s "$TMP/wrong/other" "$TMP/home/.gitconfig"
assert_fail "preflight: wrong file symlink" \
    bash "$CHECK" preflight "$TMP/dotfiles" "$TMP/home" git
assert_fail "verify: wrong file symlink" \
    bash "$CHECK" verify "$TMP/dotfiles" "$TMP/home" git

reset_home
mkdir -p "$TMP/dotfiles/zsh/.zsh.d"
printf 'export FOO=1\n' > "$TMP/dotfiles/zsh/.zsh.d/foo.sh"
ln -s "$TMP/dotfiles/zsh/.zsh.d" "$TMP/home/.zsh.d"
assert_pass "preflight: correct directory fold" \
    bash "$CHECK" preflight "$TMP/dotfiles" "$TMP/home" zsh
assert_pass "verify: correct directory fold" \
    bash "$CHECK" verify "$TMP/dotfiles" "$TMP/home" zsh

reset_home
ln -s "$TMP/wrong" "$TMP/home/.zsh.d"
assert_fail "preflight: wrong parent symlink" \
    bash "$CHECK" preflight "$TMP/dotfiles" "$TMP/home" zsh

assert_fail "preflight: missing module" \
    bash "$CHECK" preflight "$TMP/dotfiles" "$TMP/home" does-not-exist

# ── stow_find tests: type filtering and ignored dirs ──
# shellcheck disable=SC1091
source "$ROOT/_scripts/common.sh"

SF="$TMP/stowfind"
mkdir -p "$SF/.venv/bin" "$SF/__pycache__" "$SF/sub"
printf 'a\n' > "$SF/afile.txt"
printf 'b\n' > "$SF/.venv/bin/python"
printf 'c\n' > "$SF/__pycache__/x.pyc"
printf 'd\n' > "$SF/sub/deep.txt"

sf_list() { stow_find "$SF" "$@" | tr '\0' '\n' | sed -e "s#^$SF/##" -e "s#^$SF\$##" | grep -v '^$' | sort; }

[[ "$(sf_list -mindepth 1 -type d)" == "sub" ]] \
    || fail "stow_find -type d should return only directories: $(sf_list -mindepth 1 -type d | tr '\n' ' ')"

[[ "$(sf_list -mindepth 1 \( -type f -o -type l \))" == $'afile.txt\nsub/deep.txt' ]] \
    || fail "stow_find -type f should return only files and not enter ignored dirs: $(sf_list -mindepth 1 \( -type f -o -type l \) | tr '\n' ' ')"

[[ "$(sf_list -mindepth 1 -maxdepth 1)" == $'afile.txt\nsub' ]] \
    || fail "stow_find -maxdepth 1 should return only one level: $(sf_list -mindepth 1 -maxdepth 1 | tr '\n' ' ')"

[[ "$(sf_list)" == $'afile.txt\nsub\nsub/deep.txt' ]] \
    || fail "stow_find without predicates should list everything and not enter ignored dirs: $(sf_list | tr '\n' ' ')"

echo "PASS check-links tests"

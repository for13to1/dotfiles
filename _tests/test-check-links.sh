#!/usr/bin/env bash
#
# test-check-links.sh — check-links.sh 行为测试
# 用法: bash _tests/test-check-links.sh
#

set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/_scripts/check-links.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-links.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_pass() {
    local desc="$1"
    shift
    if ! bash "$CHECK" "$@" >/dev/null; then
        fail "$desc"
    fi
}

assert_fail() {
    local desc="$1"
    shift
    if bash "$CHECK" "$@" >/dev/null 2>&1; then
        fail "$desc"
    fi
}

reset_home() {
    rm -rf "${TMP:?}/home"
    mkdir -p "$TMP/home"
}

mkdir -p "$TMP/dotfiles/git" "$TMP/home" "$TMP/wrong"
printf 'user = test\n' > "$TMP/dotfiles/git/.gitconfig"

ln -s ../dotfiles/git/.gitconfig "$TMP/home/.gitconfig"
assert_pass "verify: correct file symlink" \
    verify "$TMP/dotfiles" "$TMP/home" git

ln -s "$TMP/dotfiles" "$TMP/dotfiles-link"
assert_pass "verify: dotfiles dir reached through symlink" \
    verify "$TMP/dotfiles-link" "$TMP/home" git

reset_home
printf 'wrong\n' > "$TMP/wrong/other"
ln -s "$TMP/wrong/other" "$TMP/home/.gitconfig"
assert_fail "preflight: wrong file symlink" \
    preflight "$TMP/dotfiles" "$TMP/home" git
assert_fail "verify: wrong file symlink" \
    verify "$TMP/dotfiles" "$TMP/home" git

reset_home
mkdir -p "$TMP/dotfiles/zsh/.zsh.d"
printf 'export FOO=1\n' > "$TMP/dotfiles/zsh/.zsh.d/foo.sh"
ln -s "$TMP/dotfiles/zsh/.zsh.d" "$TMP/home/.zsh.d"
assert_pass "preflight: correct directory fold" \
    preflight "$TMP/dotfiles" "$TMP/home" zsh
assert_pass "verify: correct directory fold" \
    verify "$TMP/dotfiles" "$TMP/home" zsh

reset_home
ln -s "$TMP/wrong" "$TMP/home/.zsh.d"
assert_fail "preflight: wrong parent symlink" \
    preflight "$TMP/dotfiles" "$TMP/home" zsh

assert_fail "preflight: missing module" \
    preflight "$TMP/dotfiles" "$TMP/home" does-not-exist

# ── stow_find 测试：类型过滤与忽略目录 ──
# shellcheck disable=SC1091
source "$ROOT/_scripts/common.sh"

SF="$TMP/stowfind"
mkdir -p "$SF/.venv/bin" "$SF/__pycache__" "$SF/sub"
printf 'a\n' > "$SF/afile.txt"
printf 'b\n' > "$SF/.venv/bin/python"
printf 'c\n' > "$SF/__pycache__/x.pyc"
printf 'd\n' > "$SF/sub/deep.txt"

sf_list() { stow_find "$SF" "$@" | tr '\0' '\n' | sed "s#^$SF/##" | sort; }

[[ "$(sf_list -mindepth 1 -type d)" == "sub" ]] \
    || fail "stow_find -type d 应只返回目录: $(sf_list -mindepth 1 -type d | tr '\n' ' ')"

[[ "$(sf_list -mindepth 1 \( -type f -o -type l \))" == $'afile.txt\nsub/deep.txt' ]] \
    || fail "stow_find -type f 应只返回文件且不进入忽略目录: $(sf_list -mindepth 1 \( -type f -o -type l \) | tr '\n' ' ')"

[[ "$(sf_list -mindepth 1 -maxdepth 1)" == $'afile.txt\nsub' ]] \
    || fail "stow_find -maxdepth 1 应只返回一级条目: $(sf_list -mindepth 1 -maxdepth 1 | tr '\n' ' ')"

echo "PASS check-links tests"

#!/usr/bin/env bash
# test-doctor.sh — _scripts/doctor.sh 退出码契约测试
# 用法: bash _tests/test-doctor.sh
#
# 只断言 doctor 的退出码语义（核心契约）：
#   干净环境 → 0；仅有警告 → 0；存在阻断问题 → 非 0
# 不 grep 输出文案，避免文案改动导致测试脆断。

set -euo pipefail
# shellcheck disable=SC1091  # helpers.sh 动态路径
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

# 干净环境：退出 0
assert_pass "synced dotfiles should exit 0" \
    bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

# 可选本地状态缺失：警告而非失败，仍退出 0
rm -f "$TMP/home/.gitconfig" "$TMP/home/.zshrc.local" "$TMP/home/.gitconfig.local"
assert_pass "missing optional local state should warn but exit 0" \
    bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

# 模块目录缺失：阻断问题，退出非 0
rm -rf "$TMP/dotfiles/git"
assert_fail "missing stow module should be a blocking failure" \
    bash "$DOCTOR" "$TMP/dotfiles" "$TMP/home"

echo "PASS doctor tests"

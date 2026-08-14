#!/usr/bin/env bash
#
# test-install.sh — _install/install 行为测试（干跑模式）
# 用法: bash _tests/test-install.sh
#

set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# ── 搭建临时主题树（apt/ pacman/ brew/ 三平台）────────────────────
mkdir -p "$TMP/apt" "$TMP/pacman" "$TMP/brew"

printf 'git\nzsh\nstow\n' > "$TMP/apt/base.txt"
printf '# shell 主题\n# 注释行\n\ngit\nbat\neza\n' > "$TMP/apt/shell.txt"
printf 'ffmpeg\nopencv\n' > "$TMP/apt/media.txt"

printf 'git\nzsh\n' > "$TMP/pacman/base.txt"
printf 'ffmpeg\nopencv\n' > "$TMP/pacman/media.txt"

printf 'brew "git"\nbrew "zsh"\n' > "$TMP/brew/base.Brewfile"
printf 'brew "git"\nbrew "bat"\n' > "$TMP/brew/shell.Brewfile"
printf 'brew "postgresql@18", restart_service: :changed\nbrew "mysql"\n' > "$TMP/brew/db.Brewfile"
printf 'brew "postgresql@18"\n' > "$TMP/brew/db2.Brewfile"

run() {
    INSTALL_DRY=1 INSTALL_BASE_DIR="$TMP" bash "$ROOT/_install/install" "$@"
}

# ── 多主题合并去重：重复包只出现一次，且保留首次出现位置 ─────────
run --apt base shell > "$TMP/a1"
grep -qx 'git' "$TMP/a1" || fail "git 应出现"
[[ "$(grep -cx 'git' "$TMP/a1")" == 1 ]] || fail "git 应去重为一次"
[[ "$(sed -n '1p' "$TMP/a1")" == "git" ]] || fail "去重应保留首次出现位置（git 应为第一行）"
grep -qx 'zsh' "$TMP/a1" || fail "base 的 zsh 应出现"
grep -qx 'bat' "$TMP/a1" || fail "shell 的 bat 应出现"

# ── 注释与空行应被过滤 ───────────────────────────────────────────
grep -q '注释' "$TMP/a1" && fail "注释行不应出现在输出"
grep -qx '' "$TMP/a1" && fail "空行不应出现在输出"

# ── brew 路线：按 brew/cask 包名去重，保留首个完整行 ─────────────
run --brew base shell > "$TMP/b1"
[[ "$(grep -cx 'brew "git"' "$TMP/b1")" == 1 ]] || fail "brew git 应去重为一次"
grep -qx 'brew "bat"' "$TMP/b1" || fail "brew bat 应出现"

# 带选项的重复行：postgresql@18 出现在两个主题，应合并为一行并保留完整语法
run --brew db db2 > "$TMP/b2"
postgres_lines="$(grep -c 'postgresql@18' "$TMP/b2")"
[[ "$postgres_lines" == 1 ]] || fail "postgresql@18 应合并为一行（实际 $postgres_lines 行）"
grep -q 'restart_service' "$TMP/b2" || fail "应保留首个完整行（含 restart_service 选项）"
grep -qx 'brew "mysql"' "$TMP/b2" || fail "db 的 mysql 应出现"

# ── 缺失主题：警告跳过而不报错 ───────────────────────────────────
run --apt doesnotexist > "$TMP/a2" 2>&1
grep -q '不存在' "$TMP/a2" || fail "缺失主题应给出警告"

# ── 无效平台应报错 ───────────────────────────────────────────────
if run --foo base > /dev/null 2>&1; then
    fail "非法平台 foo 应报错退出"
fi

# ── 缺省主题 = 只装 base ─────────────────────────────────────────
run --apt > "$TMP/a3"
grep -qx 'git' "$TMP/a3" || fail "base 应包含 git"
grep -qx 'zsh' "$TMP/a3" || fail "base 应包含 zsh"
grep -qx 'stow' "$TMP/a3" || fail "base 应包含 stow"
grep -q 'ffmpeg' "$TMP/a3" && fail "缺省不应包含 media 的 ffmpeg"
grep -q 'bat' "$TMP/a3" && fail "缺省不应包含 shell 的 bat"

# ── 无可用包：警告且退出 0 ───────────────────────────────────────
mkdir -p "$TMP/empty"
printf '# 只有注释\n' > "$TMP/empty/base.txt"
if INSTALL_DRY=1 INSTALL_BASE_DIR="$TMP/empty" bash "$ROOT/_install/install" --apt base > "$TMP/a4" 2>&1; then
    :
else
    fail "无可用包时不应报错退出"
fi

echo "PASS install tests"

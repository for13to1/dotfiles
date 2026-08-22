#!/usr/bin/env bash
# helpers.sh — 测试共享断言库（供各 test-*.sh source，不直接执行）
#
# 只提供通用断言；环境搭建（ROOT/TMP、临时目录、退出清理）由各测试文件自行负责，
# 避免跨文件变量依赖带来的 shellcheck 噪音。
# 文件名不匹配 test-*.sh，因此不会被 Makefile 的 for 循环当作测试执行。

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# ── 命令级断言 ──────────────────────────────────────────────────
assert_pass() {
    local desc="$1"; shift
    if ! "$@" >/dev/null; then
        fail "$desc"
    fi
}

assert_fail() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        fail "$desc"
    fi
}

# ── 文件系统断言 ────────────────────────────────────────────────
assert_file()    { local desc="$1" path="$2"; [[ -f "$path" ]] || fail "$desc"; }
assert_dir()     { local desc="$1" path="$2"; [[ -d "$path" ]] || fail "$desc"; }
assert_missing() { local desc="$1" path="$2"; [[ ! -e "$path" ]] || fail "$desc"; }

# ── 内容断言 ────────────────────────────────────────────────────
# 字符串包含（haystack 为变量内容）
assert_contains() {
    local desc="$1" haystack="$2" pattern="$3"
    grep -q -- "$pattern" <<<"$haystack" || fail "$desc (actual: $haystack)"
}

# 文件包含（path 为文件路径）
assert_file_contains() {
    local desc="$1" path="$2" pattern="$3"
    grep -q -- "$pattern" "$path" || fail "$desc"
}

# 相等
assert_equals() {
    local desc="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] || fail "$desc: expected '$expected', got '$actual'"
}

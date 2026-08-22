#!/usr/bin/env bash
# helpers.sh — shared test assertion library (sourced by test-*.sh, not run directly)
#
# Provides only generic assertions; each test file owns its environment setup
# (ROOT/TMP, temp dir, exit cleanup) to avoid shellcheck noise from cross-file variables.
# The name does not match test-*.sh, so the Makefile's for loop never runs it as a test.

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# ── Command-level assertions ───────────────────────────────────────
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

# ── Filesystem assertions ────────────────────────────────────────
assert_file()    { local desc="$1" path="$2"; [[ -f "$path" ]] || fail "$desc"; }
assert_dir()     { local desc="$1" path="$2"; [[ -d "$path" ]] || fail "$desc"; }
assert_missing() { local desc="$1" path="$2"; [[ ! -e "$path" ]] || fail "$desc"; }

# ── Content assertions ─────────────────────────────────────────
# String contains (haystack is a variable's content).
assert_contains() {
    local desc="$1" haystack="$2" pattern="$3"
    grep -q -- "$pattern" <<<"$haystack" || fail "$desc (actual: $haystack)"
}

# File contains (path is a file path).
assert_file_contains() {
    local desc="$1" path="$2" pattern="$3"
    grep -q -- "$pattern" "$path" || fail "$desc"
}

# Equality.
assert_equals() {
    local desc="$1" expected="$2" actual="$3"
    [[ "$actual" == "$expected" ]] || fail "$desc: expected '$expected', got '$actual'"
}

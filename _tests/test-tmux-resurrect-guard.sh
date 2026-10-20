#!/usr/bin/env bash
# test-tmux-resurrect-guard.sh — behavior tests for tmux/.config/tmux/resurrect-guard.sh:
# corrupt archives are dropped, restore falls back to the newest intact one, and with
# nothing usable left the session-0 kill is suppressed.
# Usage: bash _tests/test-tmux-resurrect-guard.sh

set -euo pipefail
# shellcheck disable=SC1091  # helpers.sh is sourced via a dynamic path
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/resurrect-guard-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

GUARD="$ROOT/tmux/.config/tmux/resurrect-guard.sh"
CONF="$ROOT/tmux/.tmux.conf"

# The hook line is the whole wiring: a drifted path or a stray quote breaks it.
assert_file "guard script present" "$GUARD"
# shellcheck disable=SC2016  # the expected value is the conf's literal text
assert_equals "conf sources the guard script" \
    'source "$HOME/.config/tmux/resurrect-guard.sh"' \
    "$(sed -n "s/^set -g @resurrect-hook-pre-restore-all '\(.*\)'\$/\1/p" "$CONF")"

# Run the guard in a subshell with the plugin helpers stubbed; prints "1" when the
# session-0 kill was suppressed.
run_guard() {
    local dir="$1"
    # shellcheck disable=SC2329  # the stubs below are called by the sourced guard
    (
        flag=""
        resurrect_dir() { printf '%s\n' "$dir"; }
        last_resurrect_file() { printf '%s/last\n' "$dir"; }
        restored_session_0_true() { flag=1; }
        # shellcheck source=/dev/null
        source "$GUARD"
        printf '%s' "$flag"
    )
}

# seed <dir> <archive-name> — one pane line is enough to count as intact.
seed() {
    printf 'pane\t0\t1\t1\t1\t0\t:\tzsh\t1\tzsh\t1\t0\n' >"$1/$2"
}

# ── intact last: no-op ────────────────────────────────────────────
dir="$TMP/intact"
mkdir -p "$dir"
seed "$dir" tmux_resurrect_20250101T000000.txt
ln -s tmux_resurrect_20250101T000000.txt "$dir/last"

assert_equals "intact: no session-0 suppression" "" "$(run_guard "$dir")"
assert_equals "intact: last untouched" "tmux_resurrect_20250101T000000.txt" "$(readlink "$dir/last")"
assert_file "intact: archive kept" "$dir/tmux_resurrect_20250101T000000.txt"

# ── 0-byte last: newest intact wins, corrupt archive dropped ───────
dir="$TMP/empty-last"
mkdir -p "$dir"
seed "$dir" tmux_resurrect_20250101T000000.txt
seed "$dir" tmux_resurrect_20250102T000000.txt
touch -t 202501010000 "$dir/tmux_resurrect_20250101T000000.txt"
touch -t 202501020000 "$dir/tmux_resurrect_20250102T000000.txt"
: >"$dir/tmux_resurrect_20250103T000000.txt"
ln -s tmux_resurrect_20250103T000000.txt "$dir/last"

assert_equals "empty last: no session-0 suppression" "" "$(run_guard "$dir")"
assert_equals "empty last: relinked to newest intact" "tmux_resurrect_20250102T000000.txt" "$(readlink "$dir/last")"
assert_missing "empty last: corrupt archive removed" "$dir/tmux_resurrect_20250103T000000.txt"
assert_file "empty last: candidates kept" "$dir/tmux_resurrect_20250101T000000.txt"
assert_equals "empty last: idempotent on rerun" "" "$(run_guard "$dir")"
assert_equals "empty last: link stable on rerun" "tmux_resurrect_20250102T000000.txt" "$(readlink "$dir/last")"

# ── equal mtimes: the names still decide ──────────────────────────
dir="$TMP/same-mtime"
mkdir -p "$dir"
seed "$dir" tmux_resurrect_20250101T000000.txt
seed "$dir" tmux_resurrect_20250102T000000.txt
touch -t 202501030000 "$dir"/tmux_resurrect_2025010*.txt
: >"$dir/tmux_resurrect_20250103T000000.txt"
ln -s tmux_resurrect_20250103T000000.txt "$dir/last"

assert_equals "same mtime: no session-0 suppression" "" "$(run_guard "$dir")"
assert_equals "same mtime: newest name wins" "tmux_resurrect_20250102T000000.txt" "$(readlink "$dir/last")"

# ── truncated archive (no pane line) ──────────────────────────────
dir="$TMP/truncated-with-fallback"
mkdir -p "$dir"
seed "$dir" tmux_resurrect_20250101T000000.txt
printf 'window\t0\t1\tbash\t1\t*Z\t\t0\n' >"$dir/tmux_resurrect_20250104T000000.txt"
ln -s tmux_resurrect_20250104T000000.txt "$dir/last"

assert_equals "truncated: no session-0 suppression" "" "$(run_guard "$dir")"
assert_equals "truncated: falls back to intact" "tmux_resurrect_20250101T000000.txt" "$(readlink "$dir/last")"
assert_missing "truncated: corrupt archive removed" "$dir/tmux_resurrect_20250104T000000.txt"

dir="$TMP/truncated-only"
mkdir -p "$dir"
printf 'window\t0\t1\tbash\t1\t*Z\t\t0\n' >"$dir/tmux_resurrect_20250104T000000.txt"
ln -s tmux_resurrect_20250104T000000.txt "$dir/last"

assert_equals "truncated only: session-0 kill suppressed" "1" "$(run_guard "$dir")"
assert_equals "truncated only: last kept (no dangling link)" "tmux_resurrect_20250104T000000.txt" "$(readlink "$dir/last")"
assert_file "truncated only: archive kept" "$dir/tmux_resurrect_20250104T000000.txt"

# ── no archive at all ─────────────────────────────────────────────
dir="$TMP/no-archive"
mkdir -p "$dir"

assert_equals "no archive: session-0 kill suppressed" "1" "$(run_guard "$dir")"
assert_missing "no archive: no last fabricated" "$dir/last"

echo "PASS tmux-resurrect-guard tests"

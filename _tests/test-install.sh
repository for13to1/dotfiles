#!/usr/bin/env bash
# test-install.sh — behavior tests for _install/install (dry-run mode)
# Usage: bash _tests/test-install.sh

set -euo pipefail
# shellcheck disable=SC1091  # helpers.sh is sourced via a dynamic path
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ── Build a temp .group tree (apt/pacman/brew platforms) ──
mkdir -p "$TMP/apt" "$TMP/pacman" "$TMP/brew"

printf 'git\nzsh\nstow\n' > "$TMP/apt/core.group"
printf '# shell group\n# comment line\n\ngit\nbat\neza\n' > "$TMP/apt/shell.group"
printf 'ffmpeg\nopencv\n' > "$TMP/apt/media.group"
printf 'git\nripgrep\neza\n' > "$TMP/apt/default.group"

printf 'git\nzsh\n' > "$TMP/pacman/core.group"
printf 'ffmpeg\nopencv\n' > "$TMP/pacman/media.group"

printf 'brew "git"\nbrew "zsh"\n' > "$TMP/brew/core.group"
printf 'brew "git"\nbrew "bat"\n' > "$TMP/brew/shell.group"
printf 'brew "postgresql@18", restart_service: :changed\nbrew "mysql"\n' > "$TMP/brew/db.group"
printf 'brew "postgresql@18"\n' > "$TMP/brew/db2.group"

run() {
    INSTALL_DRY=1 INSTALL_BASE_DIR="$TMP" bash "$ROOT/_install/install" "$@"
}

# ── Multi-group merge/dedupe: dupes appear once, keep first occurrence ──
run --apt core shell > "$TMP/a1"
grep -qx 'git' "$TMP/a1" || fail "git should appear"
[[ "$(grep -cx 'git' "$TMP/a1")" == 1 ]] || fail "git should be deduped to one occurrence"
[[ "$(sed -n '1p' "$TMP/a1")" == "git" ]] || fail "dedupe keeps first occurrence (git should be line 1)"
grep -qx 'zsh' "$TMP/a1" || fail "core's zsh should appear"
grep -qx 'bat' "$TMP/a1" || fail "shell's bat should appear"

# ── Comment and blank lines are filtered ──
grep -q 'comment line' "$TMP/a1" && fail "comment lines must not appear in the output"
grep -qx '' "$TMP/a1" && fail "blank lines must not appear in the output"

# ── brew route: dedupe by brew/cask name, keep first full line ──
run --brew core shell > "$TMP/b1"
[[ "$(grep -cx 'brew "git"' "$TMP/b1")" == 1 ]] || fail "brew git should be deduped to one occurrence"
grep -qx 'brew "bat"' "$TMP/b1" || fail "brew bat should appear"

# Duplicate line with options: postgresql@18 in two groups must merge to one line
# with full syntax.
run --brew db db2 > "$TMP/b2"
postgres_lines="$(grep -c 'postgresql@18' "$TMP/b2")"
[[ "$postgres_lines" == 1 ]] || fail "postgresql@18 should merge to one line (got $postgres_lines)"
grep -q 'restart_service' "$TMP/b2" || fail "should keep the first full line (with restart_service)"
grep -qx 'brew "mysql"' "$TMP/b2" || fail "db's mysql should appear"

# ── Missing group: fail loudly so a typo can't silently skip installs ──
if run --apt doesnotexist > "$TMP/a2" 2>&1; then
    fail "a missing group should fail"
fi
grep -q 'Unknown apt install group: doesnotexist' "$TMP/a2" || fail "a missing group should give a clear error"

# A valid + missing group mix must also fail, never run a partial install.
if run --apt core doesnotexist > "$TMP/a2-mixed" 2>&1; then
    fail "mixing valid and missing groups should fail"
fi
grep -q 'Unknown apt install group: doesnotexist' "$TMP/a2-mixed" || fail "the mix should name the missing group"

# ── Invalid platform errors ──
if run --foo core > /dev/null 2>&1; then
    fail "invalid platform foo should fail"
fi

# ── Default = default group ──
run --apt > "$TMP/a3"
grep -qx 'git' "$TMP/a3" || fail "default should include git"
grep -qx 'ripgrep' "$TMP/a3" || fail "default should include ripgrep (project dependency)"
grep -qx 'eza' "$TMP/a3" || fail "default should include eza"
grep -q 'ffmpeg' "$TMP/a3" && fail "default must not include media's ffmpeg"
grep -qx 'bat' "$TMP/a3" && fail "default must not include shell's bat"

# ── default as a named group, mergeable/dedupable with others ──
run --apt core default > "$TMP/a5"
[[ "$(grep -cx 'git' "$TMP/a5")" == 1 ]] || fail "core+default git should be deduped to one occurrence"
grep -qx 'ripgrep' "$TMP/a5" || fail "core+default should include default's ripgrep"
grep -qx 'zsh' "$TMP/a5" || fail "core+default should include core's zsh"


# ── No packages available: warn and exit 0 ──
mkdir -p "$TMP/empty/apt"
printf '# comment only\n' > "$TMP/empty/apt/core.group"
if INSTALL_DRY=1 INSTALL_BASE_DIR="$TMP/empty" bash "$ROOT/_install/install" --apt core > "$TMP/a4" 2>&1; then
    :
else
    fail "no packages available should not error"
fi

echo "PASS install tests"

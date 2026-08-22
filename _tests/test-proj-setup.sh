#!/usr/bin/env bash
# test-proj-setup.sh — behavior tests for proj-setup/bin/proj-setup.sh (templates and placeholders)
# Usage: bash _tests/test-proj-setup.sh

set -euo pipefail
# shellcheck disable=SC1091  # helpers.sh is sourced via a dynamic path
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/proj-setup.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/dotfiles/_scripts" "$TMP/dotfiles/proj-setup/bin" "$TMP/work"
cp "$ROOT/_scripts/common.sh" "$TMP/dotfiles/_scripts/common.sh"
cp "$ROOT/proj-setup/bin/proj-setup.sh" "$TMP/dotfiles/proj-setup/bin/proj-setup.sh"
cp -R "$ROOT/proj-setup/templates" "$TMP/dotfiles/proj-setup/templates"

mkdir -p "$TMP/dotfiles/proj-setup/templates/language/python/src/__PROJECT_NAME__"
printf 'PACKAGE = "__PROJECT_NAME__"\n' \
    > "$TMP/dotfiles/proj-setup/templates/language/python/src/__PROJECT_NAME__/__init__.py"

PROJ_SETUP="$TMP/dotfiles/proj-setup/bin/proj-setup.sh"

new_target="$TMP/work/New Project"
assert_pass "default setup should create target and initialize git" \
    bash "$PROJ_SETUP" "$new_target"
assert_dir "new target directory should be created" "$new_target"
assert_dir "default setup should initialize git" "$new_target/.git"
assert_file "git template should be copied" "$new_target/.gitignore"
assert_file_contains "base README should use normalized project name" \
    "$new_target/README.md" '^# new-project$'

python_target="$TMP/work/My App"
mkdir -p "$python_target"
printf 'keep __PROJECT_NAME__ unchanged\n' > "$python_target/NOTES.md"
printf 'existing readme __PROJECT_NAME__\n' > "$python_target/EXISTING.md"

assert_pass "python setup without vcs should succeed" \
    bash "$PROJ_SETUP" --vcs=none --lang=python "$python_target"
assert_missing "--vcs=none should not initialize git" "$python_target/.git"
assert_file "python pyproject should be copied" "$python_target/pyproject.toml"
assert_file "nested language template should be copied" \
    "$python_target/src/__PROJECT_NAME__/__init__.py"
assert_file_contains "README placeholder should be customized" \
    "$python_target/README.md" '^# my-app$'
assert_file_contains "pyproject placeholder should be customized" \
    "$python_target/pyproject.toml" '^name = "my-app"$'
assert_file_contains "nested template placeholder should be customized" \
    "$python_target/src/__PROJECT_NAME__/__init__.py" '^PACKAGE = "my-app"$'
assert_equals "existing files should not be customized" \
    'keep __PROJECT_NAME__ unchanged' "$(cat "$python_target/NOTES.md")"
assert_equals "unrelated existing files should not be customized" \
    'existing readme __PROJECT_NAME__' "$(cat "$python_target/EXISTING.md")"

printf '# original __PROJECT_NAME__\n' > "$python_target/README.md"
assert_pass "rerunning should skip existing files" \
    bash "$PROJ_SETUP" --vcs=none --lang=python "$python_target"
assert_equals "existing template path should not be overwritten or customized on rerun" \
    '# original __PROJECT_NAME__' "$(cat "$python_target/README.md")"

assert_fail "multiple positional args should fail" \
    bash "$PROJ_SETUP" "$TMP/work/one" "$TMP/work/two"
assert_fail "unsupported vcs should fail" \
    bash "$PROJ_SETUP" --vcs=unknown "$TMP/work/bad-vcs"
assert_fail "unsupported language should fail" \
    bash "$PROJ_SETUP" --lang=unknown "$TMP/work/bad-lang"

echo "PASS proj-setup tests"

#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/install-ecosystem-tools-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# shellcheck disable=SC1091
source "$ROOT/_install/install-by-uv.sh"

uv() {
    printf '%s\n' "$*" > "$TMP/uv.args"
}

install_ruff

grep -qx 'tool install ruff' "$TMP/uv.args" || fail "ruff must use uv tool install"

# shellcheck disable=SC1091
source "$ROOT/_install/install-by-cargo.sh"

cargo() {
    printf '%s\n' "$*" > "$TMP/cargo.args"
}

install_stylua

grep -qx 'install stylua --features lua54' "$TMP/cargo.args" \
    || fail "stylua must enable the lua54 feature"

# shellcheck disable=SC1091
source "$ROOT/_install/install-by-npm.sh"

release_age_flag() {
    return 1
}

fnm_exec() {
    printf '%s\n' "$*" > "$TMP/npm.args"
}

install_biome

grep -qx "npm install -g --prefix $HOME/.local @biomejs/biome" "$TMP/npm.args" \
    || fail "biome must be installed into the shared ~/.local prefix"

echo "PASS ecosystem tool installer tests"

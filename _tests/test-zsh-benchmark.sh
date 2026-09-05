#!/usr/bin/env bash
# test-zsh-benchmark.sh — latency & correctness benchmark test for zsh configuration
# Usage: bash _tests/test-zsh-benchmark.sh

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP zsh-benchmark tests (zsh not found)"
    exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/zsh-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Prepare sandbox home
mkdir -p "$TMP/home/.zsh.d"
cp "$ROOT/zsh/.zshrc" "$TMP/home/.zshrc"
cp -r "$ROOT/zsh/.zsh.d/"* "$TMP/home/.zsh.d/"
if [[ -d "$HOME/.oh-my-zsh" ]]; then
    ln -s "$HOME/.oh-my-zsh" "$TMP/home/.oh-my-zsh"
fi

# 1. Correctness check: source in isolated zsh subshell
assert_pass "zshrc should source cleanly without syntax or runtime error" \
    env HOME="$TMP/home" ZDOTDIR="$TMP/home" zsh -c "source $TMP/home/.zshrc"

# 2. Performance benchmark: verify startup latency is within acceptable threshold (default: < 1000ms)
MAX_THRESHOLD_MS="${DOTFILES_BENCH_MAX_MS:-1000}"
# shellcheck disable=SC2016
elapsed_ms=$(env HOME="$TMP/home" ZDOTDIR="$TMP/home" zsh -c '
    zmodload zsh/datetime 2>/dev/null || true
    start=${EPOCHREALTIME:-0}
    source "$HOME/.zshrc" >/dev/null 2>&1 || true
    end=${EPOCHREALTIME:-0}
    if (( start > 0 && end > 0 )); then
        elapsed=$(( (end - start) * 1000 ))
        printf "%.0f" "$elapsed"
    else
        echo "0"
    fi
')

if [[ "$elapsed_ms" -gt 0 && "$elapsed_ms" -gt "$MAX_THRESHOLD_MS" ]]; then
    fail "Zsh startup latency too high: ${elapsed_ms}ms (threshold: ${MAX_THRESHOLD_MS}ms)"
fi

echo "PASS zsh-benchmark tests"

#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted strings are intentional: written verbatim by run(), evaluated in a subshell
#
# test-net-proxy.sh — behavior tests for zsh/.zsh.d/net_proxy.sh (proxy on/off and config)
# Usage: bash _tests/test-net-proxy.sh

set -euo pipefail
# shellcheck disable=SC1091  # helpers.sh is sourced via a dynamic path
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/net-proxy.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

NET_PROXY_SH="$ROOT/zsh/.zsh.d/net_proxy.sh"

# Run a snippet under an isolated HOME (a fresh shell each time, simulating a new terminal).
run() {
    printf '%s\n' "$1" > "$TMP/run.sh"
    HOME="$TMP/home" bash -c "source '$NET_PROXY_SH'; . '$TMP/run.sh'"
}

# Read the currently saved proxy address from the config file.
conf_addr() {
    sed -n 's/^net_proxy_addr=//p' "$TMP/home/.net_proxy.conf" | head -1 | sed 's/^"//; s/"$//'
}

mkdir -p "$TMP/home"

# ── Initial state: status shows off when no config exists ──
out="$(run 'net_proxy status')"
assert_contains "status shows off with no config" "$out" 'Proxy status: ⭕ off'

# ── set: save the address to ~/.net_proxy.conf ──
run 'net_proxy set 192.168.1.5:8888' >/dev/null || fail "net_proxy set should succeed"
grep -q '^net_proxy_addr=192.168.1.5:8888$' "$TMP/home/.net_proxy.conf" \
    || fail "config should contain the new address"
grep -q 'net_proxy_enabled=0' "$TMP/home/.net_proxy.conf" \
    || fail "net_proxy_enabled should be 0 when off"

# ── on: export env vars and persist the on/off state ──
out="$(run 'net_proxy on >/dev/null; printf "%s|%s|%s" "$http_proxy" "$https_proxy" "$all_proxy"')"
[[ "$out" == "http://192.168.1.5:8888|http://192.168.1.5:8888|socks5://192.168.1.5:8888" ]] \
    || fail "on should export http:// and socks5:// proxy vars; got: $out"
grep -q 'net_proxy_enabled=1' "$TMP/home/.net_proxy.conf" \
    || fail "on should write net_proxy_enabled=1"

# ── on should set no_proxy ──
out="$(run 'net_proxy on >/dev/null; printf "%s" "$no_proxy"')"
[[ "$out" == *"localhost"* ]] || fail "on should set no_proxy"

# ── off: clear env vars and persist the on/off state ──
out="$(run 'net_proxy on >/dev/null; net_proxy off >/dev/null; printf "%s|%s" "${http_proxy:-unset}" "${all_proxy:-unset}"')"
[[ "$out" == "unset|unset" ]] || fail "off should clear proxy vars; got: $out"
grep -q 'net_proxy_enabled=0' "$TMP/home/.net_proxy.conf" \
    || fail "off should write net_proxy_enabled=0"

# ── Auto-restore in a new terminal: on should reapply after reopening a shell ──
run 'net_proxy on' >/dev/null
out="$(run 'printf "%s" "${http_proxy:-unset}"')"
[[ "$out" == "http://192.168.1.5:8888" ]] \
    || fail "a new terminal should auto-restore the proxy; got: $out"

# ── No restore in a new terminal after off ──
run 'net_proxy off' >/dev/null
out="$(run 'printf "%s" "${http_proxy:-unset}"')"
[[ "$out" == "unset" ]] || fail "a new terminal must not restore after off; got: $out"

# ── Shortcut: passing ip:port directly equals set ──
run 'net_proxy 127.0.0.1:9999' >/dev/null || fail "net_proxy ip:port should equal set"
grep -q '^net_proxy_addr=127.0.0.1:9999$' "$TMP/home/.net_proxy.conf" \
    || fail "the shortcut should update the address"

# ── scheme switch: all_proxy follows when http ──
out="$(run 'net_proxy on >/dev/null; net_proxy scheme http >/dev/null; printf "%s|%s" "$all_proxy" "$http_proxy"')"
[[ "$out" == "http://127.0.0.1:9999|http://127.0.0.1:9999" ]] \
    || fail "scheme http should apply; got: $out"

# ── Invalid scheme / unknown command should error ──
if run 'net_proxy scheme ftp' >/dev/null 2>&1; then
    fail "an invalid scheme should be rejected"
fi
if run 'net_proxy nonsense' >/dev/null 2>&1; then
    fail "an unknown command should fail"
fi

# ── set takes effect immediately while on ──
run 'net_proxy on' >/dev/null
out="$(run 'net_proxy set 10.0.0.2:3128 >/dev/null; printf "%s" "$http_proxy"')"
[[ "$out" == "http://10.0.0.2:3128" ]] \
    || fail "set should take effect immediately while on; got: $out"

# ── Interactive set: Enter keeps the default; the prompt must not leak into the value ──
printf '\n' | HOME="$TMP/home" bash -c "source '$NET_PROXY_SH'; net_proxy set" >/dev/null 2>&1
out="$(conf_addr)"
[[ "$out" == "10.0.0.2:3128" ]] || fail "interactive set with Enter should keep the current address; got: $out"

printf '172.16.0.9:8080\n' | HOME="$TMP/home" bash -c "source '$NET_PROXY_SH'; net_proxy set" >/dev/null 2>&1
out="$(conf_addr)"
[[ "$out" == "172.16.0.9:8080" ]] || fail "interactive set should accept the typed value; got: $out"

# The prompt must not leak into the saved address.
[[ "$out" != *"Enter proxy address"* ]] || fail "the prompt must not leak into the saved address; got: $out"

# ── IPv6 addresses save and restore in a new terminal ──
run 'net_proxy set "[::1]:1080" >/dev/null; net_proxy on >/dev/null' \
    || fail "a bracketed IPv6 address should be settable"
out="$(run 'printf "%s" "$all_proxy"')"
[[ "$out" == "http://[::1]:1080" ]] || fail "the IPv6 address should restore in a new terminal; got: $out"

# ── Invalid addresses are rejected immediately and must not overwrite existing config ──
before="$(conf_addr)"
marker="$TMP/should-not-exist"
if HOME="$TMP/home" MARKER="$marker" bash -c "source '$NET_PROXY_SH'; addr='\$(touch \"\$MARKER\")'; net_proxy set \"\$addr\"" >/dev/null 2>&1; then
    fail "an address with shell special chars should be rejected"
fi
[[ ! -e "$marker" ]] || fail "an invalid address must not execute commands"
[[ "$(conf_addr)" == "$before" ]] || fail "an invalid address must not overwrite existing config"

if run 'net_proxy set host:70000' >/dev/null 2>&1; then
    fail "an out-of-range port should be rejected"
fi
if run 'net_proxy set user:pass@host:7890' >/dev/null 2>&1; then
    fail "an unsupported auth address should be explicitly rejected"
fi

echo "PASS net_proxy tests"

#!/usr/bin/env bash
# shellcheck disable=SC2016  # 单引号字符串是刻意为之：传给 run() 后原样写入临时文件，在子 shell 中才求值
#
# test-net-proxy.sh — net_proxy.sh 行为测试（网络代理开关与配置）
# 用法: bash _tests/test-net-proxy.sh
#

set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NET_PROXY_SH="$ROOT/zsh/.zsh.d/net_proxy.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/net-proxy.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# 在隔离的 HOME 下执行一段脚本（每次全新 shell，模拟新终端）
run() {
    printf '%s\n' "$1" > "$TMP/run.sh"
    HOME="$TMP/home" bash -c "source '$NET_PROXY_SH'; . '$TMP/run.sh'"
}

assert_contains() {
    local desc="$1" haystack="$2" pattern="$3"
    grep -q -- "$pattern" <<<"$haystack" || fail "$desc (实际输出: $haystack)"
}

# 读取配置文件中当前保存的代理地址
conf_addr() {
    sed -n 's/^net_proxy_addr=//p' "$TMP/home/.net_proxy.conf" | head -1 | sed 's/^"//; s/"$//'
}

mkdir -p "$TMP/home"

# ── 初始状态：无配置文件时 status 显示已关闭 ───────────────────
out="$(run 'net_proxy status')"
assert_contains "无配置时应显示已关闭" "$out" '已关闭'

# ── set：保存地址到 ~/.net_proxy.conf ─────────────────────────
run 'net_proxy set 192.168.1.5:8888' >/dev/null || fail "net_proxy set 应成功"
grep -q '^net_proxy_addr=192.168.1.5:8888$' "$TMP/home/.net_proxy.conf" \
    || fail "配置应包含新地址"
grep -q 'net_proxy_enabled=0' "$TMP/home/.net_proxy.conf" \
    || fail "未开启时 net_proxy_enabled 应为 0"

# ── on：导出正确环境变量并持久化开关状态 ───────────────────────
out="$(run 'net_proxy on >/dev/null; printf "%s|%s|%s" "$http_proxy" "$https_proxy" "$all_proxy"')"
[[ "$out" == "http://192.168.1.5:8888|http://192.168.1.5:8888|socks5://192.168.1.5:8888" ]] \
    || fail "on 应导出 http:// 与 socks5:// 代理变量，实际: $out"
grep -q 'net_proxy_enabled=1' "$TMP/home/.net_proxy.conf" \
    || fail "on 应写入 net_proxy_enabled=1"

# ── on 时应设置 no_proxy ───────────────────────────────────────
out="$(run 'net_proxy on >/dev/null; printf "%s" "$no_proxy"')"
[[ "$out" == *"localhost"* ]] || fail "on 应设置 no_proxy"

# ── off：清除环境变量并持久化开关状态 ──────────────────────────
out="$(run 'net_proxy on >/dev/null; net_proxy off >/dev/null; printf "%s|%s" "${http_proxy:-unset}" "${all_proxy:-unset}"')"
[[ "$out" == "unset|unset" ]] || fail "off 后代理变量应被清除，实际: $out"
grep -q 'net_proxy_enabled=0' "$TMP/home/.net_proxy.conf" \
    || fail "off 应写入 net_proxy_enabled=0"

# ── 新终端自动恢复：on 之后重开 shell 应自动生效 ───────────────
run 'net_proxy on' >/dev/null
out="$(run 'printf "%s" "${http_proxy:-unset}"')"
[[ "$out" == "http://192.168.1.5:8888" ]] \
    || fail "新终端应自动恢复代理，实际: $out"

# ── off 之后新终端不恢复 ───────────────────────────────────────
run 'net_proxy off' >/dev/null
out="$(run 'printf "%s" "${http_proxy:-unset}"')"
[[ "$out" == "unset" ]] || fail "关闭后新终端不应再自动恢复，实际: $out"

# ── 快捷方式：直接传 ip:port 等价于 set ────────────────────────
run 'net_proxy 127.0.0.1:9999' >/dev/null || fail "net_proxy ip:port 应等价于 set"
grep -q '^net_proxy_addr=127.0.0.1:9999$' "$TMP/home/.net_proxy.conf" \
    || fail "快捷方式应更新地址"

# ── scheme 切换：http 时 all_proxy 跟随 ────────────────────────
out="$(run 'net_proxy on >/dev/null; net_proxy scheme http >/dev/null; printf "%s|%s" "$all_proxy" "$http_proxy"')"
[[ "$out" == "http://127.0.0.1:9999|http://127.0.0.1:9999" ]] \
    || fail "scheme http 应生效，实际: $out"

# ── 非法 scheme / 未知命令应报错 ──────────────────────────────
if run 'net_proxy scheme ftp' >/dev/null 2>&1; then
    fail "非法 scheme 应被拒绝"
fi
if run 'net_proxy nonsense' >/dev/null 2>&1; then
    fail "未知命令应失败"
fi

# ── set 后（处于开启）立即生效 ─────────────────────────────────
run 'net_proxy on' >/dev/null
out="$(run 'net_proxy set 10.0.0.2:3128 >/dev/null; printf "%s" "$http_proxy"')"
[[ "$out" == "http://10.0.0.2:3128" ]] \
    || fail "开启状态下 set 应立即生效，实际: $out"

# ── 交互式 set：回车使用默认值，提示符不应污染返回值 ───────────
printf '\n' | HOME="$TMP/home" bash -c "source '$NET_PROXY_SH'; net_proxy set" >/dev/null 2>&1
out="$(conf_addr)"
[[ "$out" == "10.0.0.2:3128" ]] || fail "交互式 set 回车应保留当前地址，实际: $out"

printf '172.16.0.9:8080\n' | HOME="$TMP/home" bash -c "source '$NET_PROXY_SH'; net_proxy set" >/dev/null 2>&1
out="$(conf_addr)"
[[ "$out" == "172.16.0.9:8080" ]] || fail "交互式 set 应接受输入值，实际: $out"

# 提示符不应出现在保存的地址中（曾发生的 bug）
[[ "$out" != *"请输入"* ]] || fail "提示符不应污染保存的地址，实际: $out"

# 配置值必须按字面量保存，重新加载时不能执行命令替换。
marker="$TMP/should-not-exist"
HOME="$TMP/home" MARKER="$marker" bash -c "source '$NET_PROXY_SH'; addr='\$(touch \"\$MARKER\")'; net_proxy set \"\$addr\"" >/dev/null 2>&1 \
    || fail "包含 shell 特殊字符的地址应可安全保存"
HOME="$TMP/home" bash -c "source '$NET_PROXY_SH'; net_proxy status" >/dev/null 2>&1 \
    || fail "重新加载特殊字符配置不应失败"
[[ ! -e "$marker" ]] || fail "重新加载配置不应执行地址中的命令"

echo "PASS net_proxy tests"

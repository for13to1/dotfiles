# shellcheck shell=bash
# net_proxy — 网络代理开关与配置
#
# 用法: net_proxy [on|off|set [ip:port]|scheme [http|https|socks5]|status|help]
#   无参数 = status；直接传 ip:port 等价于 set（可交互输入）。
#
# 配置保存在 ~/.net_proxy.conf（默认即关闭，不导出任何环境变量）。
# net_proxy on 时导出:
#   http_proxy / https_proxy = http://$addr（大写形式同）
#   all_proxy / ALL_PROXY    = $scheme://$addr（默认 socks5）
#   no_proxy / NO_PROXY      = localhost,127.0.0.1,0.0.0.0,::1
# 新终端启动自动恢复最近一次状态。

NET_PROXY_CONF_FILE="${NET_PROXY_CONF_FILE:-$HOME/.net_proxy.conf}"
NET_PROXY_DEFAULT_ADDR="${NET_PROXY_DEFAULT_ADDR:-127.0.0.1:7890}"
NET_PROXY_DEFAULT_SCHEME="${NET_PROXY_DEFAULT_SCHEME:-socks5}"
NET_PROXY_NO_PROXY="${NET_PROXY_NO_PROXY:-localhost,127.0.0.1,0.0.0.0,::1}"

# 载入保存的配置（若存在），由命令分发器统一调用
net_proxy_load_conf() {
    if [[ -f "$NET_PROXY_CONF_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$NET_PROXY_CONF_FILE"
    fi
}

# 在当前 shell 导出全部代理环境变量
net_proxy_export_env() {
    export http_proxy="http://$net_proxy_addr" \
           https_proxy="http://$net_proxy_addr" \
           all_proxy="${net_proxy_scheme}://$net_proxy_addr" \
           HTTP_PROXY="http://$net_proxy_addr" \
           HTTPS_PROXY="http://$net_proxy_addr" \
           ALL_PROXY="${net_proxy_scheme}://$net_proxy_addr" \
           no_proxy="$NET_PROXY_NO_PROXY" \
           NO_PROXY="$NET_PROXY_NO_PROXY"
}

# 移除当前 shell 的代理环境变量（no_proxy 泛用性更广，保留不动）
net_proxy_unset_env() {
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
}

# 唯一变更出口：归一默认值 → 按开关状态导出/清除 → 持久化。
# on/off/set/scheme 全部经由这里提交，保证配置与当前 shell 始终一致。
net_proxy_apply() {
    net_proxy_addr="${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}"
    net_proxy_scheme="${net_proxy_scheme:-$NET_PROXY_DEFAULT_SCHEME}"
    if (( net_proxy_enabled == 1 )); then
        net_proxy_export_env
    else
        net_proxy_unset_env
    fi
    net_proxy_save_conf
}

# 持久化配置到 ~/.net_proxy.conf（文件权限收紧为 600，可能包含凭据）
net_proxy_save_conf() {
    local fdir
    fdir="$(dirname "$NET_PROXY_CONF_FILE")"
    [[ -d "$fdir" ]] || mkdir -p "$fdir"
    (
        umask 077
        cat > "$NET_PROXY_CONF_FILE" <<EOF
# 本文件由 net_proxy 命令维护；如需修改请使用 net_proxy 命令，或编辑后重启终端。
net_proxy_addr="$net_proxy_addr"
net_proxy_scheme="$net_proxy_scheme"
net_proxy_enabled=${net_proxy_enabled:-0}
EOF
    )
    chmod 600 "$NET_PROXY_CONF_FILE"
}

# 交互式输入：bash / zsh 通用（避免 zsh 中 read 的 -p 表示协程而非提示符）
# 提示符写入 stderr，否则在命令替换 $(net_proxy_prompt ...) 中会被误捕为返回值。
net_proxy_prompt() {
    local reply=""
    printf '%s' "$1" >&2
    read -r reply || true
    printf '%s\n' "${reply:-$2}"
}

# 设置代理地址（net_proxy set 与快捷传址共用；配置已由分发器载入）
net_proxy_set() {
    local addr="${1:-}"
    if [[ -z "$addr" ]]; then
        addr="$(net_proxy_prompt "请输入代理地址 (默认: ${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}): " "${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}")"
    fi
    [[ -n "$addr" ]] || { echo "错误: 代理地址不能为空" >&2; return 1; }
    net_proxy_addr="$addr"
    net_proxy_apply
    if (( net_proxy_enabled == 1 )); then
        echo "✅ 代理地址已更新并生效: $net_proxy_addr"
    else
        echo "💾 代理地址已保存: $net_proxy_addr（运行 net_proxy on 启用）"
    fi
}

net_proxy_status() {
    local addr="${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}"
    local scheme="${net_proxy_scheme:-$NET_PROXY_DEFAULT_SCHEME}"
    if [[ "${net_proxy_enabled:-0}" == "1" ]]; then
        if [[ -n "${http_proxy:-}" ]]; then
            echo "代理状态: ✅ 已开启并生效"
        else
            echo "代理状态: ✅ 已配置开启，当前会话未生效（运行 net_proxy on 或重开终端）"
        fi
    else
        echo "代理状态: ⭕ 已关闭"
    fi
    echo "  地址:       $addr"
    echo "  http(s):    http://$addr"
    echo "  all_proxy:  ${scheme}://$addr"
    echo "  no_proxy:   ${no_proxy:-未设置}"
}

net_proxy_help() {
    cat <<'EOF'
用法: net_proxy <命令> [参数]
  无参数              等价于 status
  on                  开启代理（应用已保存的配置）
  off                 关闭代理
  set [ip:port]       设置代理地址；不带参数则交互式输入
                      （也可直接写 net_proxy 127.0.0.1:7890）
  scheme [http|https|socks5]  设置 all_proxy 协议（默认 socks5）
  status              查看当前状态
  help                显示本帮助
配置保存在 ~/.net_proxy.conf，默认关闭，新终端自动恢复最近状态。
EOF
}

# 命令分发：先统一载入配置，各子命令只修改状态，统一交给 net_proxy_apply 提交
net_proxy() {
    local cmd="${1:-status}"
    net_proxy_load_conf
    case "$cmd" in
        on|enable)
            net_proxy_enabled=1
            net_proxy_apply
            echo "✅ 代理已开启: http_proxy=$net_proxy_addr / all_proxy=$net_proxy_scheme://$net_proxy_addr"
            ;;
        off|disable)
            net_proxy_enabled=0
            net_proxy_apply
            echo "🔄 代理已关闭"
            ;;
        set)
            net_proxy_set "${2:-}"
            ;;
        scheme)
            if [[ -z "${2:-}" ]]; then
                echo "当前 all_proxy 协议: ${net_proxy_scheme:-$NET_PROXY_DEFAULT_SCHEME}"
            else
                case "$2" in
                    http|https|socks5) ;;
                    *) echo "错误: 协议仅支持 http / https / socks5" >&2; return 1 ;;
                esac
                net_proxy_scheme="$2"
                net_proxy_apply
                echo "✅ all_proxy 协议已设为 $2"
            fi
            ;;
        status)
            net_proxy_status
            ;;
        help|-h|--help)
            net_proxy_help
            ;;
        *)
            # 直接传 ip:port 视为快捷设置
            if [[ "$cmd" == *:* ]]; then
                net_proxy_set "$cmd"
            else
                echo "错误: 未知命令 '$cmd'，运行 net_proxy help 查看用法" >&2
                return 1
            fi
            ;;
    esac
}

# 本文件被 .zshrc 加载（~/.zsh.d/*.sh）时自动恢复代理配置
net_proxy_load_conf
if [[ "${net_proxy_enabled:-0}" == "1" ]]; then
    net_proxy_addr="${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}"
    net_proxy_scheme="${net_proxy_scheme:-$NET_PROXY_DEFAULT_SCHEME}"
    net_proxy_export_env
fi
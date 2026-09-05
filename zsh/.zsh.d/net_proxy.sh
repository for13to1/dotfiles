# shellcheck shell=bash
# net_proxy — proxy on/off and configuration
#
# Usage: net_proxy [on|off|set [ip:port]|scheme [http|https|socks5]|status|help]
#   No argument = status; a bare ip:port is equivalent to set (with interactive prompt).
#
# Config is stored in ~/.local/state/net_proxy.conf (off by default; no env vars are exported).
# `net_proxy on` exports:
#   http_proxy / https_proxy = http://$addr (plus uppercase variants)
#   all_proxy / ALL_PROXY    = $scheme://$addr (socks5 by default)
#   no_proxy / NO_PROXY      = localhost,127.0.0.1,0.0.0.0,::1
# A new terminal auto-restores the last state.

if [[ -z "${NET_PROXY_CONF_FILE:-}" ]]; then
    _xdg_conf="${XDG_STATE_HOME:-$HOME/.local/state}/net_proxy.conf"
    _legacy_conf="$HOME/.net_proxy.conf"
    # Compatibility: auto-migrate legacy config if present
    if [[ -f "$_legacy_conf" && ! -f "$_xdg_conf" ]]; then
        mkdir -p "$(dirname "$_xdg_conf")"
        mv "$_legacy_conf" "$_xdg_conf" 2>/dev/null || true
    fi
    NET_PROXY_CONF_FILE="$_xdg_conf"
    unset _xdg_conf _legacy_conf
fi
NET_PROXY_DEFAULT_ADDR="${NET_PROXY_DEFAULT_ADDR:-127.0.0.1:7890}"
NET_PROXY_DEFAULT_SCHEME="${NET_PROXY_DEFAULT_SCHEME:-socks5}"
NET_PROXY_NO_PROXY="${NET_PROXY_NO_PROXY:-localhost,127.0.0.1,0.0.0.0,::1}"

# Accepts hostname/IPv4 or bracketed IPv6, with port 1-65535.
net_proxy_valid_addr() {
    local addr="$1" port
    [[ "$addr" =~ ^([[:alnum:]._-]+|\[[[:xdigit:]:]+\]):[[:digit:]]+$ ]] || return 1
    port="${addr##*:}"
    (( 10#$port >= 1 && 10#$port <= 65535 ))
}

# Load the saved config (if any).
net_proxy_load_conf() {
    net_proxy_addr="$NET_PROXY_DEFAULT_ADDR"
    net_proxy_scheme="$NET_PROXY_DEFAULT_SCHEME"
    net_proxy_enabled=0

    [[ -f "$NET_PROXY_CONF_FILE" ]] || return 0

    local key value
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
            ''|'#'*) continue ;;
            net_proxy_addr)
                if net_proxy_valid_addr "$value"; then
                    net_proxy_addr="$value"
                fi
                ;;
            net_proxy_scheme)
                case "$value" in
                    http|https|socks5) net_proxy_scheme="$value" ;;
                esac
                ;;
            net_proxy_enabled)
                case "$value" in
                    0|1) net_proxy_enabled="$value" ;;
                esac
                ;;
        esac
    done < "$NET_PROXY_CONF_FILE"
}

# Export all proxy env vars in the current shell.
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

# Remove proxy env vars from the current shell (keep no_proxy: it is more general).
net_proxy_unset_env() {
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
}

# Single mutation exit: normalize defaults → export/unset per on/off state → persist.
# on/off/set/scheme all funnel through here, keeping config and shell always in sync.
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

# Persist config to $NET_PROXY_CONF_FILE (a plain data file, permissions tightened to 600).
net_proxy_save_conf() {
    local fdir
    fdir="$(dirname "$NET_PROXY_CONF_FILE")"
    [[ -d "$fdir" ]] || mkdir -p "$fdir"
    (
        umask 077
        {
            printf '%s\n' '# This file is maintained by the net_proxy command; edit via net_proxy, or edit then restart your terminal.'
            printf 'net_proxy_addr=%s\n' "$net_proxy_addr"
            printf 'net_proxy_scheme=%s\n' "$net_proxy_scheme"
            printf 'net_proxy_enabled=%s\n' "${net_proxy_enabled:-0}"
        } > "$NET_PROXY_CONF_FILE"
    )
    chmod 600 "$NET_PROXY_CONF_FILE"
}

# Interactive input, portable across bash/zsh (in zsh, read -p means coproc, not prompt).
# The prompt goes to stderr so command substitution doesn't capture it as the return value.
net_proxy_prompt() {
    local reply=""
    printf '%s' "$1" >&2
    read -r reply || true
    printf '%s\n' "${reply:-$2}"
}

# Set the proxy address (shared by `net_proxy set` and the quick ip:port form; config is
# already loaded by the dispatcher).
net_proxy_set() {
    local addr="${1:-}"
    if [[ -z "$addr" ]]; then
        addr="$(net_proxy_prompt "Enter proxy address (default: ${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}): " "${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}")"
    fi
    if ! net_proxy_valid_addr "$addr"; then
        echo "Error: proxy address must be host:port or [IPv6]:port, port 1-65535" >&2
        return 1
    fi
    net_proxy_addr="$addr"
    net_proxy_apply
    if (( net_proxy_enabled == 1 )); then
        echo "✅ Proxy address updated and active: $net_proxy_addr"
    else
        echo "💾 Proxy address saved: $net_proxy_addr (run 'net_proxy on' to enable)"
    fi
}

net_proxy_status() {
    local addr="${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}"
    local scheme="${net_proxy_scheme:-$NET_PROXY_DEFAULT_SCHEME}"
    if [[ "${net_proxy_enabled:-0}" == "1" ]]; then
        if [[ -n "${http_proxy:-}" ]]; then
            echo "Proxy status: ✅ on and active"
        else
            echo "Proxy status: ✅ configured on, not active in this session (run 'net_proxy on' or reopen the terminal)"
        fi
    else
        echo "Proxy status: ⭕ off"
    fi
    echo "  Address:    $addr"
    echo "  http(s):    http://$addr"
    echo "  all_proxy:  ${scheme}://$addr"
    echo "  no_proxy:   ${no_proxy:-not set}"
}

net_proxy_help() {
    cat <<'EOF'
Usage: net_proxy <command> [args]
  (no args)           equivalent to status
  on                  enable the proxy (applies the saved config)
  off                 disable the proxy
  set [ip:port]       set the proxy address; without an arg, prompts interactively
                      (you can also write net_proxy 127.0.0.1:7890 directly)
  scheme [http|https|socks5]  set the all_proxy scheme (default socks5)
  status              show the current status
  help                show this help
Config is stored in ~/.local/state/net_proxy.conf,
  off by default; a new terminal auto-restores the last state.
EOF
}

# Dispatch: load config once, subcommands only mutate state, and net_proxy_apply commits it.
net_proxy() {
    local cmd="${1:-status}"
    net_proxy_load_conf
    case "$cmd" in
        on|enable)
            net_proxy_enabled=1
            net_proxy_apply
            echo "✅ Proxy enabled: http_proxy=$net_proxy_addr / all_proxy=$net_proxy_scheme://$net_proxy_addr"
            ;;
        off|disable)
            net_proxy_enabled=0
            net_proxy_apply
            echo "🔄 Proxy disabled"
            ;;
        set)
            net_proxy_set "${2:-}"
            ;;
        scheme)
            if [[ -z "${2:-}" ]]; then
                echo "Current all_proxy scheme: ${net_proxy_scheme:-$NET_PROXY_DEFAULT_SCHEME}"
            else
                case "$2" in
                    http|https|socks5) ;;
                    *) echo "Error: scheme must be http / https / socks5" >&2; return 1 ;;
                esac
                net_proxy_scheme="$2"
                net_proxy_apply
                echo "✅ all_proxy scheme set to $2"
            fi
            ;;
        status)
            net_proxy_status
            ;;
        help|-h|--help)
            net_proxy_help
            ;;
        *)
            # A bare ip:port is treated as a quick set.
            if [[ "$cmd" == *:* ]]; then
                net_proxy_set "$cmd"
            else
                echo "Error: unknown command '$cmd'; run 'net_proxy help'" >&2
                return 1
            fi
            ;;
    esac
}

# Auto-restore the proxy config when this file is sourced by .zshrc (~/.zsh.d/*.sh).
net_proxy_load_conf
if [[ "${net_proxy_enabled:-0}" == "1" ]]; then
    net_proxy_addr="${net_proxy_addr:-$NET_PROXY_DEFAULT_ADDR}"
    net_proxy_scheme="${net_proxy_scheme:-$NET_PROXY_DEFAULT_SCHEME}"
    net_proxy_export_env
fi

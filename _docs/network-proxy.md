# 网络代理 (net_proxy)

定义于 `zsh/.zsh.d/net_proxy.sh`，用于管理当前会话及跨终端持久化的代理环境变量。

## 配置文件与路径

配置存储路径：

- 默认路径：`${XDG_STATE_HOME:-$HOME/.local/state}/net_proxy.conf`。
- 自定义路径：可通过环境变量 `$NET_PROXY_CONF_FILE` 覆盖。

文件权限固定为 `600`。新建终端加载 `net_proxy.sh` 时，若文件中 `net_proxy_enabled=1`，则自动恢复环境变量。

## 命令用法

```bash
net_proxy [status]                   # 显示当前状态与变量值（无参数时默认为 status）
net_proxy on                         # 启用代理并写入持久化配置
net_proxy off                        # 停用代理并写入持久化配置
net_proxy set <host:port>            # 更新代理地址（无参数时进入交互输入）
net_proxy <host:port>                # 快捷设置代理地址
net_proxy scheme <socks5|http|https> # 设置 all_proxy 协议类型（默认 socks5）
net_proxy help                       # 显示帮助信息
```

## 环境变量

执行 `net_proxy on` 时导出的环境变量：

| 变量名 | 格式 | 说明 |
| :--- | :--- | :--- |
| `http_proxy` / `HTTP_PROXY` | `http://<host:port>` | HTTP 代理 |
| `https_proxy` / `HTTPS_PROXY` | `http://<host:port>` | HTTPS 代理 |
| `all_proxy` / `ALL_PROXY` | `<scheme>://<host:port>` | 全协议代理，协议由 `scheme` 参数决定 |
| `no_proxy` / `NO_PROXY` | `localhost,127.0.0.1,0.0.0.0,::1` | 本地与回环地址排除列表 |

执行 `net_proxy off` 时清空上述代理变量（`no_proxy` / `NO_PROXY` 保持保留）。

## 协议与行为说明

- 工具仅设置应用层环境变量；ICMP 流量（如 `ping`）不受环境变量控制。
- Git 的 HTTP(S) 传输读取当前 Shell 的 `https_proxy`；SSH 传输（`git@github.com`）需在 `~/.ssh/config` 中配置 `ProxyCommand`。

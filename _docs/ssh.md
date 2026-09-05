# SSH 基础设施

由 [`_bootstrap/ssh.sh`](../_bootstrap/ssh.sh) 初始化 SSH 目录、生成默认密钥并配置权限。

## 目录与文件权限

初始化流程对 `~/.ssh` 及其内容应用以下权限约束：

| 路径 / 文件匹配 | 权限 | 说明 |
| :--- | :--- | :--- |
| `~/.ssh` | `700` | 仅属主可读写执行 |
| `id_*`（私钥）、`*.pem` | `600` | 仅属主可读写 |
| `config`、`authorized_keys`、`known_hosts*` | `600` | 仅属主可读写 |
| `*.pub`（公钥） | `644` | 属主读写，组及其他用户只读 |

## 密钥与常用操作

```bash
# 生成 ed25519 密钥对（bootstrap.sh 交互执行内容）
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"

# 将私钥加入 ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 测试 GitHub 连接
ssh -T git@github.com

# 部署公钥至远端主机
ssh-copy-id -i ~/.ssh/id_ed25519.pub <user>@<host>
```

## 配置模板 (`~/.ssh/config`)

```ssh-config
Host *
    AddKeysToAgent yes
    IdentitiesOnly yes
    ServerAliveInterval 60
    ServerAliveCountMax 3

# 通过本地 SOCKS5 代理连接 GitHub（可选）
# Host github.com
#     User git
#     ProxyCommand nc -X 5 -x 127.0.0.1:7890 %h %p
```

# SSH 密钥

`bootstrap.sh` 会检查 SSH 环境，可选生成 Ed25519 密钥并修正文件权限。

```bash
ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
ssh -T git@github.com
ssh-copy-id <user>@<host>
```

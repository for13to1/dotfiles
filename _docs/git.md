# Git 全局配置

`git` Stow 包提供全局 Git 配置，并通过 `~/.gitconfig.local` 引入本机身份信息。

`git/.config/git/ignore` 由 Stow 挂载到 `~/.config/git/ignore`，并由 `git/.gitconfig` 的
`core.excludesFile` 引用。当前默认忽略 CodeGraph 创建的 `.codegraph/` 目录。

```bash
cd ~/dotfiles && make sync
git check-ignore -v /path/to/repo/.codegraph/
```

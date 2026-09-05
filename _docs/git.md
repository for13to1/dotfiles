# Git 全局配置

`git` 模块提供用户级 Git 基础配置、排除规则及提交前质量钩子。

## 目录与文件布局

- `git/.gitconfig`：主配置文件，Stow 软链接至 `~/.gitconfig`。包含默认分支、编码、LFS 过滤器与局部配置包含规则。
- `git/.config/git/ignore`：用户级全局忽略文件，Stow 软链接至 `~/.config/git/ignore`，由 `core.excludesFile` 引用。默认忽略 `.codegraph/` 等本地工具索引。
- `~/.gitconfig.local`：本地身份文件（未纳入版本控制）。由 `bootstrap.sh` 在首次运行时引导创建，通过 `[include]` 引入主配置。

## 文件系统大小写处理

- 全局配置不显式指定 `core.ignorecase`，由 Git 在 `init` 或 `clone` 时针对目标文件系统（如 macOS APFS、Linux ext4）自动探测。
- 在大小写不敏感的文件系统上重命名仅有大小写差异的文件时，使用 `git mv`（例如 `git mv file.txt File.txt`），避免产生文件系统与索引冲突。

## 自动化钩子 (pre-push)

`_bootstrap/git.sh` 将当前仓库的 `core.hooksPath` 设置为 `_scripts/hooks`。
每次执行 `git push` 时，[`_scripts/hooks/pre-push`](../_scripts/hooks/pre-push) 执行 `make test`；若检查失败，中断推送。

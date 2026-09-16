# 软件安装与软件包组

软件按平台分组安装，`_install/<platform>/<group>.group` 是组文件，`_install/install` 是统一安装入口。

## 安装

```bash
# 预览合并去重后的最终列表（不真正安装）
INSTALL_DRY=1 bash ~/dotfiles/_install/install --brew default shell editor

# 实际安装：多选组，自动合并去重后一次性交给包管理器
bash ~/dotfiles/_install/install --apt default shell editor

# 不指定组 = 默认安装 default 组（见 _install/<platform>/default.group）
bash ~/dotfiles/_install/install --brew
```

## 编辑软件包组

`.group` 文件是各平台系统包的唯一数据源，组间允许重复包名，安装前统一去重：

```bash
# 编辑某平台的 .group 文件
${EDITOR:-vi} ~/dotfiles/_install/brew/vcs.group
```

## 安装途径边界

- `.group` 文件只包含各平台包管理器可安装的软件（`_install/install` 为统一安装入口）；
- **平台差异层**（`pkg-*`）：仅 apt 缺 fnm/rustup/uv，由 `install-by-curl.sh` 官方安装器补齐（brew/pacman 经 default 组提供，无需此渠道）；
- **平台无关层**：
  - `install-by-npm.sh` 安装 Node.js CLI 及预编译分发的工具（pi、codex、opencode、codegraph、wrangler、biome、stylua）；
  - `install-by-uv.sh` 通过 `uv tool` 安装 Python CLI（ruff、yt-dlp）；
  - `install-by-go.sh` 通过 `go install` 安装 Go 编辑器工具（gopls、gofumpt），固定落入 `~/.local/bin`；布局（`GOBIN`/`GOPATH`/`GOMODCACHE`）经 `go env -w` 写入用户级 GOENV（路径由 `go env GOENV` 决定：macOS 为 `~/Library/Application Support/go/env`，Linux 为 `~/.config/go/env`）——同值重写为 no-op；当前生效值与目标值不同时先告警，再写入 GOENV（环境变量优先于 GOENV，故当值来自 shell 导出时，生效值不变）——写入失败只告警、不阻断安装；写入成功后 Go 默认的 `~/go` 不再使用；
  - `install-by-cargo.sh` 保留为 Rust CLI 备用渠道（暂不启用）。

各渠道按需通过 `is_installed` 幂等跳过已装工具，不重复安装；`DOTFILES_SKIP_ECOSYSTEM_TOOLS=1` 跳过全部生态安装（测试/无网络环境）。

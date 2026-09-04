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
  - `install-by-cargo.sh` 保留为 Rust CLI 备用渠道（暂不启用）。

各渠道按需通过 `is_installed` 幂等跳过已装工具，不重复安装；`DOTFILES_SKIP_ECOSYSTEM_TOOLS=1` 跳过全部生态安装（测试/无网络环境）。

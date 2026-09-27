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
  - `install-by-npm.sh` / `install-by-uv.sh` / `install-by-go.sh` 三个渠道共用同一套 CLI 注册表（`eco_cli` 声明，见下方「CLI 注册表」）；清单以各渠道源码中的 `eco_cli` 声明为准，不在文档里重复罗列；
  - `install-by-go.sh` 额外把 `GOBIN`（产物）定到 `~/.local/bin`、`GOMODCACHE`（模块缓存）定到 `~/.cache/go-mod`，经 `go env -w` 写入 Go 用户配置，对所有 `go` 命令生效（`GOPATH` 不设）。
    - 覆盖已有值前先提示，不静默改写。
    - `go env -w` 写入失败不影响工具安装。
  - `install-by-cargo.sh` 保留为 Rust CLI 备用渠道（暂不启用）。

已装工具按各渠道的检测策略幂等跳过（npm 查 `~/.local/bin/<bin>`，uv/go 先查 PATH 再查该路径，详见下方「CLI 注册表」），不重复安装；`DOTFILES_SKIP_ECOSYSTEM_TOOLS=1` 跳过全部生态安装（测试/无网络环境）。

## CLI 注册表

npm / uv / go 三个渠道共用一套声明式注册表（框架在 `_scripts/common.sh`）。每个工具
是一行 `eco_cli` 数据，声明顺序即执行顺序（`--always` 排在 `--prompt` 之前，基线安装
先于任何询问）：

```bash
eco_cli <bin> <pkg> <flag|""> --always|--prompt
```

| 字段 | 含义 |
| --- | --- |
| `<bin>` | 检测、提示与 `DOTFILES_ACCEPT_INSTALLS` 都按它，从不使用包名 |
| `<pkg>` | 安装目标：npm 包 / pip 包 / go module 路径 |
| `<flag>` | 渠道透传参数（如 `--allow-scripts=...`、`--ignore-scripts`），无则 `""`，不得含空格 |
| `--always` | 缺失即装 |
| `--prompt` | 逐工具询问（y/N），可由 `DOTFILES_ACCEPT_INSTALLS` 预批准 |

检测策略：npm 只查 `~/.local/bin/<bin>`（canonical，避免旧 fnm 前缀里的同名 CLI 被
误判为已装）；uv/go 先查 PATH 再查该路径（尊重组文件之外的既有安装，不重复安装）。

每个渠道只保留**一个**安装函数 `*_install_one <pkg> <flag>`，负责把数据变成具体的
npm / `uv tool` / `go install` 调用。新增工具 = 加一行 `eco_cli`，通常零函数改动。

缺字段、未知旗标、重名（bin 或 pkg）、flag 含空格在 `eco_cli` 声明时即失败
（脚本加载阶段退出）；`--always` 排在 `--prompt` 之后由 `validate_cli_registry`
兜底——无论哪种，都在任何安装执行前直接失败。

**框架边界**：本注册表只建模「单一包源 → 单个 bin → `~/.local/bin`」的生态 CLI。
一包多 bin（如 cargo crate）、或经官方安装器安装的运行时（fnm/rustup/uv，
走 `install-by-curl.sh`）不在本框架内，各走各的形态。

非交互模式下 `prompt` 条目全部跳过；`DOTFILES_ACCEPT_INSTALLS="codex mimo"`
（空格分隔的 bin 名）可按名预先批准——被批准的条目跳过确认直接安装，其余条目仍按
交互/非交互规则处理（交互逐个询问、非交互全部跳过）。

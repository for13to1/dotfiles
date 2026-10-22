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
- **平台无关层**：生态 CLI（npm/uv/go/cargo）由统一入口 `eco` 管理（见下方「生态 CLI 管理」）。

`DOTFILES_SKIP_ECOSYSTEM_TOOLS=1` 跳过自动安装（测试/无网络），不影响显式的 `eco <ch> update`/`uninstall`。

## 生态 CLI 管理

`eco` 管理 node / py / go / rust 四类包管理器可装的 CLI。

```bash
eco <node|py|go|rust> <list|install|update|uninstall> [-y] [-q] [-n] [pkg…]
```

| 动词 | 说明 |
| --- | --- |
| `list` | 已装版本与最新版本（只读） |
| `install [pkg…]` | 不带包名＝补装清单；带包名＝装指定包（已装的跳过） |
| `update [pkg…]` | 不带包名＝升级该渠道全部已装；带包名＝只升这些 |
| `uninstall <pkg…>` | 卸载（给包名，或该包声明过的可执行名） |

`-y` 不问确认；`-q` 只静音进度行（告警、错误、`list` 表格与 `-n` 计划照常）；`-n` 只打印计划。`list` 不接受 `-y`/`-n`。

`DOTFILES_NON_INTERACTIVE=1` 时全程不问，只装 `y` 行。

### 清单：`_scripts/eco.conf`

一行一工具，格式 `<渠道> <默认y|n> <bin> <pkg> [flag]`：

| 字段 | 说明 |
| --- | --- |
| 渠道 | `node` `py` `go` `rust` |
| 默认 | `y` 缺失即装、不问；`n` 交互时询问 `[y/N]`，非交互跳过 |
| bin | 用户敲的命令名，必须是包真实提供的可执行文件 |
| pkg | npm 包 / pip 包 / go module 路径 / cargo crate |
| flag | 透传参数（仅 `node`、`rust` 支持），不得含空格 |

加载时校验并直接失败：渠道白名单、重复 bin（全局）、同渠道重复 pkg、bin 含空格或 `/` 或为 `.`/`..`、flag 含空格、给 `py`/`go` 写 flag。

新增工具＝加一行，不动代码。

### 行为

- **不钉版本**：装与升都取包管理器解析的版本，`pkg@版本` 直接报错（各家 `@` 语义不同）。要锁版本用包管理器自己的机制或 lockfile。
- **装完校验**：`install` 后确认可执行文件真的出现在 `~/.local/bin`，否则失败（包名与命令名不同时，查该包声明的任一命令）。
- **动手前校验**：`update`/`uninstall` 要求快照里有该包、且 `~/.local/bin` 里有它的可执行文件；缺一个就跳过并提示。包管理器的退出码不作判据（npm 退出 0、uv 退出 2、cargo 退出 101）。
- **结果照实报**：`update` 比对动手前后的版本，报真实变化或 `already up to date`。
- **查不到就报错**：不把失败报成「空列表」或「全部最新」；只有状态确实无法确定时才失败退出。

### 常用命令

```bash
eco node list
eco node install                     # 补装清单里缺的
eco node install biome codex         # 装指定包
eco node update                      # 升级全部已装
eco node update wrangler             # 只升一个
eco go uninstall gopls               # 卸载
```

### 退出码

`eco`：`0` 成功、`1` 执行失败或无法校验、`2` 用法错误。渠道脚本另有 `3`＝运行时缺失、未执行任何动作（清单模式据此跳过，不阻塞 bootstrap）。

### 渠道实现

| 渠道 | 快照（本地） | 最新版本 | 升级 | 卸载 |
| --- | --- | --- | --- | --- |
| node (npm) | `npm ls -g --prefix ~/.local --json` | `npm outdated -g … --json` | `npm install -g <pkg>@latest` | `npm uninstall -g --prefix ~/.local <pkg>` |
| py (uv) | `uv tool list` | `uv tool list --outdated` | `uv tool upgrade` | `uv tool uninstall <pkg>` |
| go | `go version -m <prefix>/*` | `go list -m`（批量） | `go install <包路径>@latest` | 确认是 Go 产物后 `rm ~/.local/bin/<bin>` |
| rust (cargo) | `cargo install --list --root ~/.local` | 逐 crate `cargo search` | `cargo install --force --root ~/.local` | `cargo uninstall --root ~/.local <pkg>` |

`~/.local/bin` 是四个渠道共用的前缀，所以 go 卸载前用 `go version -m` 确认目标是 Go 产物，避免删掉别家的文件。

检测策略：npm 只看 `~/.local/bin/<bin>`（避开旧 fnm 前缀的同名 CLI）；uv/go/cargo 先看 PATH 再看该路径，代价是 PATH 上任何同名可执行文件都算已装。

## 框架边界

包管理器收到的一律是包名，bin 只是磁盘上的影子。快照为 `<key> <version> <package> [aliases…]`：key 是用户敲的名字，package 是安装目标，aliases 是磁盘上可能出现哪些可执行文件。所以 `eco.conf` 一行只登记一个代表 bin。

只建模「单一包源 → `~/.local/bin`」。经官方安装器装的运行时（fnm/rustup/uv）不在此列，它们各管各的升级。

## go 布局

`install-by-go.sh` 额外把 `GOBIN`（产物）定到 `~/.local/bin`、`GOMODCACHE`（模块缓存）定到 `~/.cache/go-mod`，经 `go env -w` 写入 Go 用户配置，对所有 `go` 命令生效（`GOPATH` 不设）。

- 覆盖已有值前先提示，不静默改写。
- `go env -w` 写入失败不影响工具安装。

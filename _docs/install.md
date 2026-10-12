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
  - `install-by-npm.sh` / `install-by-uv.sh` / `install-by-go.sh` 三个渠道共用同一套 CLI 注册表（`eco_cli` 声明，见下方「CLI 注册表」）；清单以集中式注册表 `_scripts/cli-registry.sh` 中的 `eco_cli` 声明为准，不在文档里重复罗列；
  - `install-by-go.sh` 额外把 `GOBIN`（产物）定到 `~/.local/bin`、`GOMODCACHE`（模块缓存）定到 `~/.cache/go-mod`，经 `go env -w` 写入 Go 用户配置，对所有 `go` 命令生效（`GOPATH` 不设）。
    - 覆盖已有值前先提示，不静默改写。
    - `go env -w` 写入失败不影响工具安装。
  - `install-by-cargo.sh` 保留为 Rust CLI 备用渠道（暂不启用）。

已装工具按各渠道的检测策略幂等跳过（npm 查 `~/.local/bin/<bin>`，uv/go 先查 PATH 再查该路径，详见下方「CLI 注册表」），不重复安装；`DOTFILES_SKIP_ECOSYSTEM_TOOLS=1` 跳过全部生态自动安装（测试/无网络环境），不影响显式的 `--update`/`--uninstall`。

## CLI 注册表

npm / uv / go 三个渠道共用一套声明式注册表：**声明**（一行一工具）集中在
`_scripts/cli-registry.sh`，**引擎**（表结构、校验、生命周期驱动）在
`_scripts/cli-lifecycle.sh`（下层只依赖通用基础设施 `_scripts/common.sh`）。每个工具
是一行 `eco_cli` 数据，声明顺序即执行顺序（`--always` 排在 `--prompt` 之前，基线安装
先于任何询问）：

```bash
eco_cli <channel> <bin> <pkg> <flag|""> --always|--prompt
```

| 字段 | 含义 |
| --- | --- |
| `<channel>` | 归属渠道（npm / uv / go）；路由是框架的事，各渠道只认自己的行 |
| `<bin>` | 检测、提示与 `DOTFILES_ACCEPT_TOOLS` 都按它，从不使用包名 |
| `<pkg>` | 安装目标：npm 包 / pip 包 / go module 路径 |
| `<flag>` | 渠道透传参数（如 `--allow-scripts=...`、`--ignore-scripts`），无则 `""`，不得含空格 |
| `--always` | 缺失即装 |
| `--prompt` | 逐工具询问（y/N），可由 `DOTFILES_ACCEPT_TOOLS` 预批准 |

检测策略：npm 只查 `~/.local/bin/<bin>`（canonical，避免旧 fnm 前缀里的同名 CLI 被
误判为已装）；uv/go 先查 PATH 再查该路径（尊重组文件之外的既有安装，不重复安装）。

**只读动词不产生副作用**：`--status` / `--outdated` 不会准备运行时（不跑 `fnm install`、
不写 `go env -w`），只做探测；运行时缺失时它们报告 `state unknown` 并非零退出，绝不
把未知当成「已是最新」。

每个渠道把数据变成具体调用的函数统一吃整行 `<bin> <pkg> <flag>`，每个动作一个函数：
`*_install_one`（安装）、`*_update_one`（升级，go 直接复用安装函数）、`*_uninstall_one`
（卸载），外加各自的 `*_ensure`（运行时门）与 `*_query_outdated`（过期查询）。新增
工具 = 在 `cli-registry.sh` 加一行 `eco_cli`，通常零函数改动。

缺字段、未知旗标、重名（bin 或 pkg）、flag 含空格在 `eco_cli` 声明时即失败
（脚本加载阶段退出）；`--always` 排在 `--prompt` 之后由 `validate_cli_registry`
兜底——无论哪种，都在任何安装执行前直接失败。

**框架边界**：本注册表只建模「单一包源 → 单个 bin → `~/.local/bin`」的生态 CLI。
一包多 bin（如 cargo crate）、或经官方安装器安装的运行时（fnm/rustup/uv，
走 `install-by-curl.sh`）不在本框架内，各走各的形态。

非交互模式下 `prompt` 条目全部跳过；`DOTFILES_ACCEPT_TOOLS="codex mimo"`
（空格分隔的 bin 名）可按名预先批准——被批准的条目跳过确认直接安装，其余条目仍按
交互/非交互规则处理（交互逐个询问、非交互全部跳过）。

## 升级与卸载

```bash
make status-tools                        # 只读：列出已装 + 过期状态
make install-tools                       # 补装缺失（BIN="a b" 限定范围）
make update-tools                        # 升级全部已装（三渠道）
make uninstall-tools                     # 卸载（危险，交互确认）
make update-tools BIN=wrangler           # BIN 由统一入口按归属路由，只命中对应渠道
# 统一入口：bash _install/manage-tools.sh <status|install|update|uninstall> [bin…]
# 单渠道：bash _install/install-by-{npm,uv,go}.sh --status|--install|--update|--uninstall [bin…]
```

统一入口 `_install/manage-tools.sh` 按注册表把每个 bin 路由到归属渠道，其余渠道不感知；
未知 bin 在入口一次报错。

- **status**：只读，列出全部注册行（已装 / 缺失 / 过期 / 别处同名 / 状态未知）+ 全局汇总；某渠道不可查询（运行时缺失/离线）时该渠道行标为 `state unknown` 且退出码非零。无已装行的渠道不查询、不参与判定（其运行时缺失不影响结果）。
- **update / uninstall**：合并三个渠道的候选为一张清单、一次确认，再分派执行；其中 update 只查询持有已装行的渠道（uninstall 不做查询）。

三渠道共用 `run_cli_channel` 驱动与同一套授权规则；失败渠道不阻塞其余、退出码聚合：

| 动作 | npm | uv | go |
| --- | --- | --- | --- |
| 查询 | `npm outdated -g --prefix ~/.local --json` | `uv tool list --outdated` | 逐行 `go version -m` + 一次批量 `go list -m` |
| 升级 | `npm_update_one`（`<pkg>@latest` 复用安装） | `uv tool upgrade` | `go install <pkg>@latest` |
| 卸载 | `npm uninstall -g --prefix ~/.local <pkg>` | `uv tool uninstall` | `rm ~/.local/bin/<bin>` |

共同规则：

- **只动已装**：升级/卸载只作用于 `~/.local/bin` 的已装条目；不补装缺失、不碰外来安装、忽略注册表外的包。
- **同一授权**：`DOTFILES_ACCEPT_TOOLS` 预批准的直接执行，其余合并成一次确认（默认 N）；旧名 `DOTFILES_ACCEPT_INSTALLS` 仍兼容但会警告一次。
- **可指定 bin**：缺省为全部；指定时只在归属渠道生效，未知 bin 由统一入口报错。`--always` 行被卸载后下次 install 自愈。
- **失败隔离 + 不撒谎**：任一行（含基线 `--always`）失败只警告并继续其余，退出码非零聚合；查询失败报错退出，不伪装「全部最新」，也不把查询失败的行显示为「up to date」。

brew 与官方安装器管理的运行时（fnm/rustup/uv）不在本框架内：系统包管理器与各
工具自己管升级（如 `brew upgrade`）。

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

已装工具按各渠道的检测策略幂等跳过（npm 查 `~/.local/bin/<bin>`，uv/go/cargo 先查 PATH 再查该路径），不重复安装；`DOTFILES_SKIP_ECOSYSTEM_TOOLS=1` 跳过生态自动安装（测试/无网络环境），不影响显式的 `eco <ch> update`/`uninstall`。

## 生态 CLI 管理

生态 CLI（node/python/go/rust 包管理器可装的工具）由统一入口 `eco` 管理：

```bash
eco <node|py|go|rust> <list|install|update|uninstall> [pkg…]
```

| 动词 | 行为 |
| --- | --- |
| `list` | 只读：列出该渠道已装工具的当前版本与最新版本 |
| `install [pkg…]` | 补装缺失工具；带包名 = 批量确认后安装指定工具；不带包名 = 清单模式（逐项确认，按 `eco.conf` 的 y/n 默认值预选） |
| `update [pkg…]` | 升级已装工具；带包名 = 不查过期直接升级；不带包名 = 先查过期列表、一次确认、只升有新版的 |
| `uninstall <pkg…>`` | 卸载（必须指定包名） |

渠道词汇只有 `node` / `py` / `go` / `rust`（对应底层 npm / uv / go / cargo，不暴露内部实现）。包名可以是 `eco.conf` 中的 bin 名（自动解析为安装目标），也可以是任意包名（未经登记的临时工具）。

### 清单（eco.conf）

清单以 `_scripts/eco.conf` 为唯一数据源，一行一工具：

```
<渠道> <默认y|n> <bin> <pkg> [flag]
```

| 字段 | 含义 |
| --- | --- |
| `<渠道>` | `node` / `py` / `go` / `rust` |
| `<默认>` | `y` = 安装时预选中；`n` = 预跳过（确认时可改） |
| `<bin>` | 身份主键——检测、提示与 `DOTFILES_ACCEPT_TOOLS` 都按它 |
| `<pkg>` | 安装目标：npm 包 / pip 包 / go module 路径 / cargo crate |
| `<flag>` | 渠道透传参数（如 `--allow-scripts=...`），无则省略，不得含空格 |

校验规则（加载时响亮失败）：渠道白名单、重复 bin、重复 pkg、flag 含空格。

新增工具 = 在 `eco.conf` 加一行，零函数改动。

### 检测策略

npm 只查 `~/.local/bin/<bin>`（canonical，避免旧 fnm 前缀里的同名 CLI 被误判为已装）；uv/go/cargo 先查 PATH 再查该路径（尊重组文件之外的既有安装，不重复安装）。

### 授权

- `DOTFILES_ACCEPT_TOOLS="biome codex"`（空格分隔的 bin 名）预先批准：被批准的工具跳过确认直接执行。
- 交互模式下：清单模式逐项 `[Y/n]`/`[y/N]`；带包名词一次性批量确认（默认 N）。
- 非交互模式下：清单模式按 `eco.conf` 默认值执行（y 装、n 跳）；带包名词无预批准则全部跳过（exit 0）。

### 各渠道实现

| 渠道 | 查询 | 升级 | 卸载 |
| --- | --- | --- | --- |
| node (npm) | `npm outdated -g --prefix ~/.local --json` | `npm install -g <pkg>@latest` | `npm uninstall -g --prefix ~/.local <pkg>` |
| py (uv) | `uv tool list --outdated` | `uv tool upgrade` | `uv tool uninstall` |
| go | 逐二进制 `go version -m` + 批量 `go list -m` | `go install <pkg>@latest` | `rm ~/.local/bin/<bin>` |
| rust (cargo) | `cargo install --list` + 逐 crate `cargo search` | `cargo install --force --root ~/.local` | `cargo uninstall --root ~/.local` |

失败隔离：任一行失败只警告并继续其余，退出码非零聚合；查询失败报错退出，不伪装「全部最新」。

### 只读动词不产生副作用

`list` 和 `--outdated`（内部机器动词）不会准备运行时（不跑 `fnm install`、不写 `go env -w`），只做探测；运行时缺失时 `list` 输出空列表并 exit 0，`--outdated` 报错退出。

## go 布局

`install-by-go.sh` 额外把 `GOBIN`（产物）定到 `~/.local/bin`、`GOMODCACHE`（模块缓存）定到 `~/.cache/go-mod`，经 `go env -w` 写入 Go 用户配置，对所有 `go` 命令生效（`GOPATH` 不设）。

- 覆盖已有值前先提示，不静默改写。
- `go env -w` 写入失败不影响工具安装。

## 升级与卸载

```bash
eco node list                        # 只读：列出已装 + 版本
eco node install                     # 清单模式：补装缺失（逐项确认）
eco node install biome codex         # 指定安装（一次批量确认）
eco node update                      # 升级全部已装（先查过期）
eco node update wrangler             # 直接升级指定工具（不查过期）
eco py update                        # 升级 Python 工具
eco go uninstall gopls               # 卸载（交互确认）
eco rust list                        # 列出 cargo 工具
```

brew 与官方安装器管理的运行时（fnm/rustup/uv）不在本框架内：系统包管理器与各工具自己管升级（如 `brew upgrade`）。

## 框架边界

本框架只建模「单一包源 → 单个 bin → `~/.local/bin`」的生态 CLI。一包多 bin（如多二进制 crate）、或经官方安装器安装的运行时（fnm/rustup/uv，走 `install-by-curl.sh`）不在本框架内，各走各的形态。

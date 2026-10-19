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

生态 CLI 的自动安装同样按各渠道的检测策略幂等跳过；参数是包名时再查一次已装快照（包名未必等于可执行名，如 `typescript` → `tsc`）。`DOTFILES_SKIP_ECOSYSTEM_TOOLS=1` 跳过自动安装（测试/无网络），不影响显式的 `eco <ch> update`/`uninstall`。

## 生态 CLI 管理

生态 CLI（node/python/go/rust 包管理器可装的工具）由统一入口 `eco` 管理：

```bash
eco <node|py|go|rust> <list|install|update|uninstall> [-y] [-q] [-n] [pkg…]
```

| 动词 | 行为 |
| --- | --- |
| `list` | 只读：列出该渠道已装工具的当前版本与最新版本 |
| `install [pkg…]` | 补装缺失工具；带包名 = 确认后安装指定工具（已装的幂等跳过）；不带包名 = 清单模式（逐项确认，按 `eco.conf` 的 y/n 默认值预选） |
| `update [-y] [pkg…]` | 升级已装工具；不带包名 = 升级该渠道全部已装工具。确认前先列出要动的每个工具及其**当前版本**；执行后逐条报告**实际观测到**的变化（`ruff updated (0.16.5 → 0.17.1)`），没有变化则说 `already up to date` |
| `uninstall [-y] <pkg…>` | 卸载（必须指定包名或该包声明的任一 bin，一律确认） |

- `-y` / `--yes`：跳过确认（`list` 不接受）。
- `-q` / `--quiet`：只静音 eco 自己的进度行（`ℹ️`/`✅`），警告、错误和包管理器输出照常；`list` 的数据不受影响。
- `-n` / `--dry-run`：只打印计划，不提问、不执行、不准备运行时、不清理 stale 文件。`update`/`uninstall` 仍会只读快照，计划基于真实已装状态；清单模式按 `eco.conf` 默认值算，加 `-y` 则按「全都装」算。`list` 不接受。

`DOTFILES_NON_INTERACTIVE=1`（CI/容器）且不加 `-y`：清单模式按 conf 默认值安装，带包名则什么都不做。

```bash
$ eco node update -n -y
ℹ️  updating via npm:
  package   current
  wrangler  4.130.0
ℹ️  would update wrangler (wrangler) [--allow-scripts=esbuild,workerd] via npm
ℹ️  dry run: no action taken
```

**观测，而不是预测。** `update` 不预查最新版本：动作前后各读一次本地快照（`--installed`，零网络），用两次读数之差作为结果。确认前的预览只有当前版本——本地已知的事实；新版本执行后才写得出。

代价是不预判「是否需要升级」：每个候选都跑一次包管理器升级命令（npm/go/cargo 是重装最新版），装完再比对版本号，所以已是最新的包也会被重装。省下的是那次网络往返，不是升级动作。

**先确认存在，再动手。** 各包管理器对「目标不存在」态度不一（npm 退出 0、uv 退出 2、cargo 退出 101），返回值不足以判断。`update`/`uninstall` 要求两个 witness：快照里有这个包，且 `~/.local/bin` 里有它声明的至少一个可执行文件。快照有、磁盘无 → 警告并跳过（提示用 `install` 重装）；快照无 → `not installed`。动手后再读一次快照核对，仍在即失败；读不出来是「状态未知」，同样失败。

渠道词汇只有 `node` / `py` / `go` / `rust`（对应底层 npm / uv / go / cargo，不暴露内部实现）。包名可以是 `eco.conf` 中的 bin 名（自动解析为安装目标），也可以是任意包名（未经登记的临时工具）。

### 不钉版本

`eco` 不管理版本，只借用各包管理器的解析结果：

- `install` / `update` 装的是包管理器解析出的版本（npm/go 显式 `@latest`，uv/cargo 用自己的默认）；
- 版本只在 `list`（当前 / 最新）和 `update` 的结果（升级前 → 升级后）里**展示**，从不回传给包管理器；
- 因此 `pkg@版本` 这种写法会被拒绝并提示：三家包管理器对 `@` 的语义各不相同（npm 认 dist-tag/范围/别名，uv 当成路径，cargo 认 `crate@ver`），在 shell 里复刻三套解析得不偿失。

需要精确锁定版本时，用对应包管理器的原生机制（`npm install -g pkg@1.2.3`、`uv tool install pkg==1.2.3`、`cargo install --version`），或依赖 lockfile —— 那是它们擅长的部分。

### 清单（eco.conf）

清单以 `_scripts/eco.conf` 为唯一数据源，一行一工具：

```
<渠道> <默认y|n> <bin> <pkg> [flag]
```

| 字段 | 含义 |
| --- | --- |
| `<渠道>` | `node` / `py` / `go` / `rust` |
| `<默认>` | `y` = 安装时预选中；`n` = 预跳过（确认时可改） |
| `<bin>` | 身份主键——检测、提示与所有消息都按它 |
| `<pkg>` | 安装目标：npm 包 / pip 包 / go module 路径 / cargo crate |
| `<flag>` | 渠道透传参数（如 `--allow-scripts=...`），无则省略，不得含空格 |

校验规则（加载时响亮失败）：渠道白名单、重复 bin、重复 pkg、bin 含空格或 `/`、bin 为 `.`/`..`、flag 含空格。

新增工具 = 在 `eco.conf` 加一行，零函数改动。

### 检测策略

npm 只查 `~/.local/bin/<bin>`（避开旧 fnm 前缀的同名 CLI）；uv/go/cargo 先查 PATH 再查该路径，尊重既有安装。代价是 PATH 上任何同名可执行文件都会被当成「已装」，不管它从哪来——要避免歧义就保持 PATH 干净，或用 npm 渠道。

`install` 后会校验可执行文件是否真的出现：先看参数名对应的路径；参数是包名时（`typescript`、`ripgrep`、`python-lsp-server`）改查快照，确认这个包声明的任一可执行文件（`tsc`、`rg`、`pylsp`）存在。退出 0 但什么都没装出 → 失败，因为退出码只说明命令跑过。命名安装的幂等判断同样查快照，所以包名不是文件名也不会反复重装。

### 授权

- 不带 `-y`：清单模式逐项 `[Y/n]`/`[y/N]`（按 conf 默认值预选）；带包名时一次性批量确认（默认 N）。
- 带 `-y`：清单模式全装（不看 y/n），带包名直接执行。
- `DOTFILES_NON_INTERACTIVE=1` 且无 `-y`：清单模式按 conf 默认值（y 装、n 跳），带包名什么都不做（exit 0）。
- 其余情况交互；提问读到 EOF（无 TTY）时按该提问的默认值处理，所以清单模式的 y 行会装。要完全不动机器，用 `DOTFILES_NON_INTERACTIVE=1`，不要只依赖空 stdin。

### 各渠道实现

| 渠道 | 已装快照（本地） | 最新版本（`list` 用） | 升级 | 卸载 |
| --- | --- | --- | --- | --- |
| node (npm) | `npm ls -g --prefix ~/.local --json` | `npm outdated -g … --json` | `npm install -g <pkg>@latest` | `npm uninstall -g --prefix ~/.local <pkg>` |
| py (uv) | `uv tool list`（含 `- <exec>` 明细） | `uv tool list --outdated` | `uv tool upgrade` | `uv tool uninstall` |
| go | `go version -m <prefix>/*`（一次批量调用） | 批量 `go list -m` | `go install <pkg>@latest` | 校验是 Go 产物后 `rm ~/.local/bin/<bin>` |
| rust (cargo) | `cargo install --list --root ~/.local` | 逐 crate `cargo search` | `cargo install --force --root ~/.local` | `cargo uninstall --root ~/.local` |

go 的卸载会先用 `go version -m` 确认目标确实带 Go 模块元数据：`~/.local/bin` 是所有渠道共用的前缀，裸 `rm` 会把 npm/uv 装的工具一起删掉。

go 的 `go install` 收包路径，二进制名取最后一段（`staticcheck` 来自 `honnef.co/go/tools/cmd/staticcheck`）。未登记参数同时拆成 bin 与 pkg：`install` 按 bin 判幂等，`uninstall` 删 bin，`update` 从快照第三列取包路径（`go install <path>@latest`）。

卸载接受包名或该包声明过的任一可执行名（`eco node uninstall cf-wrangler`、`eco rust uninstall rg`、`eco py uninstall pylsp`）；快照把后者翻译回包。版本在卸载语义里没有位置：各渠道都是覆盖式安装，同一工具只保留一个版本。

`rust` 渠道在 `eco.conf` 里没有登记项：`eco rust list` / `update` 仍按已装 crate 工作；只有 `eco rust install`（清单模式）会直接说明无登记项。

失败隔离：任一行失败只警告并继续其余，退出码非零聚合；查询失败报错退出，不伪装「全部最新」。`--outdated` 仍保留给 `list` 使用（唯一需要最新版本的动词）。

### 判定原则：结论属实

eco 的每个状态判断都以「用户看到的结论是否属实」为准，而不是「底层机制是否如实传递」。前者才是用户能据以行动的东西。

| 底层实际说了什么 | 真相 | eco 的结论 |
| --- | --- | --- |
| `npm uninstall` 对不存在的包退出 0 | 什么都没删 | 失败 |
| `npm ls` 在全新机器上报 ENOENT | 什么都没装 | 空列表，成功 |
| `cargo install --list` 失败 | 状态未知 | 报错，不是「全部最新」 |
| `go version -m` 无输出且工具链坏 | 状态未知 | 报错，不是「没装东西」 |
| `install` 退出 0 但磁盘上没有该包的任何可执行文件 | 什么都没装成 | 失败 |
| `update` / `uninstall` 的动手后快照读不出来 | 状态未知 | 失败并提示手工核对 |
| `update` 前后读到的版本相同 | 没有变化 | `already up to date` |

同一条原则管两个方向：把失败说成成功是失真，把空环境说成故障也是失真。中间那一档（「状态未知」）才是报错的场合。

### 退出码约定

渠道脚本（`install-by-*.sh`）：`0` 成功、`1` 失败、`2` 用法错误、`3` 运行时不可用且未执行任何动作（仅 one-shot 动词）。`eco` 据此把「跳过」和「完成」区分开：缺运行时不阻塞 bootstrap，但显式的 `eco <ch> install <pkg>` 不会被报告为已安装。

清单模式（`install` 不带包名）是唯一把「运行时缺失」当干净跳过的地方（退出 0），因为 bootstrap 会在每台机器上跑它，包括没装某个工具链的机器。这个不对称是有意的。

### 只读动词不产生副作用

`list` 和 `--installed` / `--outdated`（内部机器动词）不会准备运行时（不跑 `fnm install`、不写 `go env -w`），只做探测。

- **列不出已装工具**时（运行时缺失、渠道查询失败）**报错退出**：显式的只读请求不该静默返回空表。空列表只在渠道确实报告「没有已装工具」时输出。
- **查不到最新版本**时 `list` 只把那一列降级为 `?` 并告警，仍返回 0 —— 已装信息本身是有效的，不该因为一次网络失败就丢掉整张表。

## go 布局

`install-by-go.sh` 额外把 `GOBIN`（产物）定到 `~/.local/bin`、`GOMODCACHE`（模块缓存）定到 `~/.cache/go-mod`，经 `go env -w` 写入 Go 用户配置，对所有 `go` 命令生效（`GOPATH` 不设）。

- 覆盖已有值前先提示，不静默改写。
- `go env -w` 写入失败不影响工具安装。

## 升级与卸载

```bash
eco node list                        # 只读：列出已装 + 最新版本
eco node install                     # 清单模式：补装缺失（逐项确认）
eco node install biome codex         # 指定安装（一次批量确认）
eco node install -y biome codex      # 同上，不询问
eco node update                      # 升级全部已装，逐条报告真实版本变化
eco node update wrangler             # 只升级指定工具
eco py update -y                     # 升级 Python 工具，不询问
eco go uninstall gopls               # 卸载（先确认已装，交互确认）
eco rust list                        # 列出 cargo 工具
```

brew 与官方安装器管理的运行时（fnm/rustup/uv）不在本框架内：系统包管理器与各工具自己管升级（如 `brew upgrade`）。

## 框架边界

**eco 管理的是包，不是 bin。** 包管理器收到的一律是包名（npm 包、uv tool、go 模块路径、cargo crate）；bin 只是磁盘上的影子——检测看它、消息用它、go 卸载删它。用户也可以输入该包声明过的任一 bin（`cf-wrangler`、`rg`、`pylsp`），快照负责翻译；翻译时 pkg 与 flag 以 `eco.conf` 为准。

快照统一为 `<key> <version> <package> [aliases…]`：key 是用户敲的名字，package 是包管理器要的安装目标，aliases 是磁盘上可能出现的可执行文件（npm 看 package.json 的 bin，cargo 看 `install --list`，uv 看 `tool list` 的 `- <exec>`，go 用包路径最后一段）。因此 `eco.conf` 一行只登记一个**代表 bin**，同包其它 bin 无需重复登记。

本框架只建模「单一包源 → `~/.local/bin`」；经官方安装器的运行时（fnm/rustup/uv）不在内。

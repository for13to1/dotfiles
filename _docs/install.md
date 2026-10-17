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
eco <node|py|go|rust> <list|install|update|uninstall> [-y] [pkg…]
```

| 动词 | 行为 |
| --- | --- |
| `list` | 只读：列出该渠道已装工具的当前版本与最新版本 |
| `install [pkg…]` | 补装缺失工具；带包名 = 确认后安装指定工具（已装的幂等跳过）；不带包名 = 清单模式（逐项确认，按 `eco.conf` 的 y/n 默认值预选） |
| `update [-y] [pkg…]` | 升级已装工具；不带包名 = 升级该渠道全部已装工具。确认前先列出要动的每个工具及其**当前版本**；执行后逐条报告**实际观测到**的变化（`ruff updated (0.16.5 → 0.17.1)`），没有变化则说 `already up to date` |
| `uninstall [-y] <pkg…>` | 卸载（必须指定包名，一律确认） |

`-y` / `--yes` 卸载、安装、升级时跳过确认；`list` 不接受它（用法错误）。非交互环境（无 TTY / CI）下不加 `-y` 就什么都不做，避免脚本无意改动机器。

**观测，而不是预测。** `update` 不预先查询「最新版本是多少」，而是在动作前后各读一次本地已装状态（`--installed`，纯本地、零网络），把两次读数之差作为结果。确认前的预览只有「当前版本」一列——那是本地已知的事实；右边的新版本等执行后才写得出，所以不猜。

代价是确认前看不到「有哪些可升级」。换来的是：报告不会撒谎、省掉一次网络往返、带不带包名走同一条路径。

**先确认存在，再动手。** 各包管理器对「目标不存在」态度不一致（npm 退出 0 且什么都不做，uv 退出 2，cargo 退出 101），返回值不足以判断结果。`update` 和 `uninstall` 都用已装快照决定目标是否存在：不存在就说 `not installed` 且不进入动作（`update` 会提示改用 `install`）。删除后再读一次快照核对，仍在就判失败。

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

校验规则（加载时响亮失败）：渠道白名单、重复 bin、重复 pkg、bin 含 `/`、flag 含空格。

新增工具 = 在 `eco.conf` 加一行，零函数改动。

### 检测策略

npm 只查 `~/.local/bin/<bin>`（canonical，避免旧 fnm 前缀里的同名 CLI 被误判为已装）；uv/go/cargo 先查 PATH 再查该路径（尊重组文件之外的既有安装，不重复安装）。

### 授权

只有一个开关：`-y` / `--yes`。

- 不带 `-y`：清单模式逐项 `[Y/n]`/`[y/N]`（按 `eco.conf` 默认值预选）；带包名时一次性批量确认（默认 N）。
- 带 `-y`：清单模式跳过所有提问、每个缺失项都装（不看 y/n 默认值，因为 `-y` 就是"全都同意"）；带包名时直接执行。
- 非交互模式（`DOTFILES_NON_INTERACTIVE=1` 或无 TTY）且没有 `-y`：清单模式按 `eco.conf` 默认值执行（y 装、n 跳），带包名则什么都不做（exit 0）。

`DOTFILES_ACCEPT_TOOLS` / `DOTFILES_ACCEPT_INSTALLS` 已被删除。它们把「装哪些」和「确认什么」混成同一个开关，并与 `eco.conf` 形成两份平行真相。

### 各渠道实现

| 渠道 | 已装快照（本地） | 最新版本（`list` 用） | 升级 | 卸载 |
| --- | --- | --- | --- | --- |
| node (npm) | `npm ls -g --prefix ~/.local --json` | `npm outdated -g … --json` | `npm install -g <pkg>@latest` | `npm uninstall -g --prefix ~/.local <bin>` |
| py (uv) | `uv tool list` | `uv tool list --outdated` | `uv tool upgrade` | `uv tool uninstall` |
| go | `go version -m <prefix>/*`（一次批量调用） | 批量 `go list -m` | `go install <pkg>@latest` | 校验是 Go 产物后 `rm ~/.local/bin/<bin>` |
| rust (cargo) | `cargo install --list --root ~/.local` | 逐 crate `cargo search` | `cargo install --force --root ~/.local` | `cargo uninstall --root ~/.local` |

go 的卸载会先用 `go version -m` 确认目标确实带 Go 模块元数据：`~/.local/bin` 是所有渠道共用的前缀，裸 `rm` 会把 npm/uv 装的工具一起删掉。

卸载也只接受包名：同一工具在各渠道只保留一个版本（npm global prefix、uv tool、cargo `--root`、`GOBIN` 都是覆盖式安装），版本在卸载语义里没有位置。

`rust` 渠道当前在 `eco.conf` 里没有登记任何工具，`eco rust list` 会列出 cargo 侧已装的 crate，`eco rust update` 也仍按已装 crate 查询并升级。只有 `eco rust install`（清单模式）会直接说明该渠道无登记项——install 装的是清单，update 升的是已装的东西，两者依据不同。

失败隔离：任一行失败只警告并继续其余，退出码非零聚合；查询失败报错退出，不伪装「全部最新」。`--outdated` 仍保留给 `list` 使用（唯一需要最新版本的动词）。

### 判定原则：结论属实

eco 的每个状态判断都以「用户看到的结论是否属实」为准，而不是「底层机制是否如实传递」。前者才是用户能据以行动的东西。

| 底层实际说了什么 | 真相 | eco 的结论 |
| --- | --- | --- |
| `npm uninstall` 对不存在的包退出 0 | 什么都没删 | 失败 |
| `npm ls` 在全新机器上报 ENOENT | 什么都没装 | 空列表，成功 |
| `cargo install --list` 失败 | 状态未知 | 报错，不是「全部最新」 |
| `go version -m` 无输出且工具链坏 | 状态未知 | 报错，不是「没装东西」 |
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

本框架只建模「单一包源 → 单个 bin → `~/.local/bin`」的生态 CLI。一包多 bin（如多二进制 crate）、或经官方安装器安装的运行时（fnm/rustup/uv，走 `install-by-curl.sh`）不在本框架内，各走各的形态。

# Dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

我的跨平台开发环境配置，使用 [GNU Stow](https://www.gnu.org/software/stow/) 管理软链接。

## 📂 目录结构

以下划线（`_`）开头的目录是项目骨架部分；其他目录是由 GNU Stow 管理、部署到用户环境中的配置包。

```text
dotfiles/
├── agents/                     # Stow 包：通用 AI Agent 能力
│   └── .agents/
│       ├── AGENTS.md           # Agent 通用原则
│       └── skills/             # AI agent skills
├── zsh/                        # Stow 包：Zsh 配置
│   ├── .zshrc
│   └── .zsh.d/
│       ├── brew_mirror.sh      # Homebrew 镜像源切换
│       └── net_proxy.sh        # 网络代理设置
├── git/                        # Stow 包：Git 全局配置
│   ├── .gitconfig
│   └── .config/git/ignore      # 用户级 Git excludes（CodeGraph 等本地索引）
├── vim/                        # Stow 包：Vim 配置
│   └── .vimrc
├── nvim/                       # Stow 包：Neovim 配置
│   └── .config/nvim/
│       └── init.lua
├── tmux/                       # Stow 包：tmux 配置
│   └── .tmux.conf
├── ripgrep/                    # Stow 包：ripgrep 配置
│   └── .ripgreprc
├── vscode/                     # VSCode 配置备份
│   └── settings.json
├── proj-setup/                 # 项目配置工具及模板
│   ├── bin/
│   ├── templates/
│   └── README.md
├── _install/                   # 软件安装：.group 文件 + 安装工具
│   ├── install                 # 安装入口
│   ├── install-by-curl.sh      # 官方安装器途径的工具管理器安装
│   ├── install-by-npm.sh       # npm 途径的 Node.js CLI 安装
│   ├── install-by-uv.sh        # uv tool 途径的 Python CLI 安装
│   ├── install-by-cargo.sh     # Cargo 途径的 Rust CLI 安装（备用渠道，暂不启用）
│   ├── apt/                    # Debian 系平台的 .group 文件
│   ├── pacman/                 # Arch Linux 平台 .group 文件
│   └── brew/                   # macOS 平台 .group 文件
├── _bootstrap/                 # 环境部署脚本（SSH/Git/Shell/编辑器/工具）
│   ├── pkg-mac.sh              # macOS 包管理与环境前置
│   ├── pkg-linux.sh            # Linux (apt/pacman) 包管理前置
│   ├── ssh.sh                  # SSH 密钥引导
│   ├── git.sh                  # Git 全局与局部配置
│   ├── shell.sh                # Shell 与 OMZ 插件部署
│   ├── editors.sh              # 编辑器 (Neovim/Vim) 插件同步
│   └── tools.sh                # 本地 CLI 工具软链接
├── _docs/                      # 组件使用文档（Git/SSH/网络代理/AI skills/软件安装）
├── _vendor/                    # 外部 Skills Vendor 子模块（可插拔）
│   └── mattpocock/             # 社区第三方 Agent Skills
├── _setup/                     # 操作系统级设置
│   └── mac/
│       └── setup.sh            # macOS 系统设置
├── _scripts/                   # shell 基础设施
│   ├── common.sh               # 常用颜色定义、函数定义等
│   ├── modules.conf            # Stow 模块列表（单一真值源）
│   ├── list-modules.sh         # Stow 模块列表解析
│   ├── stow-sync.sh            # Stow 统一同步入口
│   ├── check-links.sh          # Stow 挂载前检查与挂载后校验
│   ├── skills-vendor.sh        # 多 Vendor 外部技能插拔管理器
│   ├── tmux-plugins.sh         # tpm 插件同步
│   ├── doctor.sh               # 环境健康诊断
│   └── hooks/
│       └── pre-push            # Git 钩子：push 前自动运行 make test
├── _tests/                     # 行为测试（make test 自动发现 test-*.sh）
│   ├── helpers.sh              # 共享断言库（fail/assert_*）
│   ├── README.md               # 测试分工与约定
│   ├── test-bootstrap.sh       # _bootstrap/* 组件行为测试
│   ├── test-check-links.sh     # check-links 行为测试
│   ├── test-doctor.sh          # doctor 退出码契约测试
│   ├── test-proj-setup.sh      # proj-setup 行为测试
│   ├── test-skills-vendor.sh   # 多 Vendor 技能插拔与冲突消解测试
│   ├── test-stow-sync.sh       # stow-sync 集成测试
│   ├── test-net-proxy.sh       # net_proxy 行为测试
│   ├── test-install.sh         # _install/install 行为测试
│   ├── test-tmux-plugins.sh    # tmux 插件同步行为测试
│   └── test-zsh-benchmark.sh   # Zsh 启动性能与正确性基准测试
├── Makefile                    # 多平台模块管理、外部技能插拔与同步
├── bootstrap.sh                # 一键部署脚本
├── opencode.json               # OpenCode 权限配置（本仓库）
├── .editorconfig               # 仓库代码风格配置（链接到 proj-setup 基础模板）
├── .gitattributes
├── .gitignore
├── LICENSE                     # MIT
└── README.md
```

## 🚀 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/for13to1/dotfiles.git ~/dotfiles

# 2. 一键安装
cd ~/dotfiles && bash bootstrap.sh
```

`bootstrap.sh` 会自动引导并处理以下流程：

1. **环境检测**：自动安装 Xcode CLT (macOS) 与 Homebrew，校验核心依赖。
2. **软件安装**：按组安装系统软件（brew/apt/pacman），macOS 应用系统设置；apt 缺失的 fnm/rustup/uv 由官方安装器补齐。
3. **生态工具**：通过 npm/uv 统一安装 CLI（pi、codex、opencode、codegraph、wrangler、biome、stylua、ruff、yt-dlp），三平台一致。
4. **SSH 基础设施**：交互式生成/检测 SSH 密钥，加固目录权限。
5. **Git 身份配置**：交互式创建本地身份配置，启用 pre-push 钩子。
6. **Shell 环境**：部署 Oh My Zsh 及其插件生态；交互模式下自动切换默认 Shell。
7. **配置挂载**：使用 `stow` 构建全局符号链接，自动备份文件冲突。
8. **tmux 插件**：同步 tpm 插件（见 `_scripts/tmux-plugins.sh`）。
9. **编辑器插件**：交互式同步 Neovim/Vim 的扩展插件。
10. **自定义工具**：部署 proj-setup 等自定义工具到 `~/.local/bin`。
11. **引导完成**：重启终端或 `source ~/.zshrc` 使配置生效。

### 非交互模式（CI / 容器 / 无 TTY）

```bash
cd ~/dotfiles && DOTFILES_NON_INTERACTIVE=1 bash bootstrap.sh
```

该模式使用默认选项：镜像源默认 TUNA，不自动生成 SSH 密钥或 Git 本地配置，跳过编辑器插件同步与默认 Shell 切换；各平台仍按其既定安装路径完成默认软件包、系统设置和开发工具链部署。

## 🖥️ 本地配置

每台机器独有的私密信息放在本地文件中，**不纳入版本控制**。

### 1. `~/.zshrc.local` 示例

```bash
# Homebrew 镜像源切换 (函数定义见 ~/.zsh.d/brew_mirror.sh)
brew_mirror -q ustc
# 可选值: tuna | ustc | ali | reset
# Linux 用户无需此段

# API Keys
export OPENAI_API_KEY="sk-..."
export OPENAI_BASE_URL="https://api.openai.com/v1"

export ANTHROPIC_API_KEY="sk-ant-..."
export ANTHROPIC_BASE_URL="https://api.anthropic.com"

export DEEPSEEK_API_KEY="your-api-key"
export DEEPSEEK_BASE_URL="https://api.deepseek.com"
```

### 2. `~/.gitconfig.local` 示例

```ini
[user]
    name = for13to1
    email = for13to1@outlook.com
```

## 🔄 日常维护

### 模块管理

Stow 包由 `_scripts/modules.conf` 统一登记。使用 `make sync` 同步配置，使用 `make check`
检查链接；新增或调整配置包时，同时更新模块目录和这份清单。

若要将新配置纳入管理：

```bash
mkdir -p ~/dotfiles/tmux
mv ~/.tmux.conf ~/dotfiles/tmux/.tmux.conf
cd ~/dotfiles && stow tmux
```

然后将模块名 `tmux` 加入 `_scripts/modules.conf`，使其在 `bootstrap.sh` 和 `make sync` 中持续生效。

当配置在远程或其他设备上发生变化时，拉取更新后重新同步：

```bash
cd ~/dotfiles
git pull
make sync
```

`make sync` 只同步 `_scripts/modules.conf` 中登记的核心 Stow 包。

### 🧩 Git 全局配置

用户级 excludes 的说明见 [`_docs/git.md`](_docs/git.md)。

### 🌐 网络代理

详细用法见 [`_docs/network-proxy.md`](_docs/network-proxy.md)。

### 🔑 SSH 密钥管理

详细操作见 [`_docs/ssh.md`](_docs/ssh.md)。

### 🤖 AI Agents 配置

详细说明见 [`_docs/ai-agents.md`](_docs/ai-agents.md)。

### 软件安装

软件按平台分组安装，`_install/<platform>/<group>.group` 是组文件，`_install/install` 是统一安装入口
（预览合并安装、多选组安装、途径边界与 `.group` 文件编辑方式见 [`_docs/install.md`](_docs/install.md)）。

### 镜像管理

仓库内置了 `brew_mirror` 工具函数（定义于 `zsh/.zsh.d/brew_mirror.sh`），方便在不同镜像源之间快速切换：

```bash
brew_mirror              # 查看当前 Homebrew 镜像源状态
brew_mirror tuna         # 切换至 清华大学 (TUNA) 镜像源
brew_mirror ustc         # 切换至 中国科大 (USTC) 镜像源
brew_mirror ali          # 切换至 阿里巴巴 (Aliyun) 镜像源
brew_mirror reset        # 重置为官方源
```

### 框架自检

```bash
make test   # ShellCheck、bash 语法检查、Stow 行为测试、Skills 测试与 Zsh 性能基准
make lint-shell  # 仅运行 ShellCheck
make test-shell  # bash 语法检查与全部 shell 行为测试（含 Zsh 性能基准）
make test-skills # 全部 Skill Python 测试
make check  # 验证当前 HOME 下的 Stow 链接状态
make doctor # 诊断本机核心工具、本地配置与 Stow 同步状态
```

`make test` 要求 `shellcheck`，并要求 `pytest` 或 `uv` 可用；缺少检查依赖时会失败，
避免 pre-push 在跳过部分检查后继续放行。

`bootstrap.sh` 会将本仓库的 `core.hooksPath` 指向 `_scripts/hooks`，
使 `pre-push` 钩子在每次 `git push` 前自动运行 `make test` 拦截回归。

### 增加工具环境依赖

新增工具 PATH 时，使用条件判断包裹，如：

```bash
# >>> postgresql@18 loading >>>
[[ -d "/opt/homebrew/opt/postgresql@18/bin" ]] && export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"
# <<< postgresql@18 loading <<<
```

## 💡 最佳实践记录

- **Git**: 始终优先通过 Homebrew 安装 Git，以解决 macOS 自带版本在某些网络环境下的 SSL 报错问题。
- **Rust (rustup)**: 安装时建议使用静默模式并禁止修改系统 PATH（因为本项目已接管）：`rustup-init -y --no-modify-path`
- **Conda (Miniforge)**: **不用**运行 `conda init`，直接依赖 `lazy loading` 实现加速启动。
- **Formatter**: Vim 和 Neovim 从 `PATH` 或项目本地环境解析 formatter，不自行下载。

## 📄 许可证

[MIT](LICENSE)

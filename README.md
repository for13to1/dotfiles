# Dotfiles

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

我的跨平台 (macOS, arch Linux, Debian-like) 开发环境配置，使用 [GNU Stow](https://www.gnu.org/software/stow/) 管理软链接。

## 🧭 核心概念

- **基础设施**（`_` 前缀：`_install`/`_bootstrap`/`_scripts`/`_docs`/`_setup`/`_tests`/`_vendor`）：安装、部署、测试与文档，只存在于仓库内，不部署到用户环境。
- **本地配置**（`~/.zshrc.local`、`~/.gitconfig.local`）：每台机器独有，不纳入版本控制。
- **配置包**（`agents`/`zsh`/`git`/`vim`/`nvim`/`tmux`/`ripgrep`）：由 GNU Stow 软链接部署到 `~`；模块清单见 `_scripts/modules.conf`（单一真值源，`bootstrap.sh` 与 `make sync` 共同读取）。

`vscode/` 暂为配置备份，`proj-setup/` 是项目工具与模板，均不参与 Stow 部署。

## 📂 目录结构

```text
dotfiles/
├── agents/                     # Stow 包：通用 AI Agent 能力
├── zsh/                        # Stow 包：Zsh 配置
├── git/                        # Stow 包：Git 全局配置
├── vim/                        # Stow 包：Vim 配置
├── nvim/                       # Stow 包：Neovim 配置
├── tmux/                       # Stow 包：tmux 配置
├── ripgrep/                    # Stow 包：ripgrep 配置
├── vscode/                     # VSCode 配置备份
├── proj-setup/                 # 项目配置工具及模板
├── _install/                   # 软件安装：按分组安装+npm/uv 生态安装
├── _bootstrap/                 # 环境部署脚本（SSH/Git/Shell/编辑器/工具）
├── _docs/                      # 使用文档说明
├── _vendor/                    # Vendor Skills
├── _setup/                     # 操作系统级设置
├── _scripts/                   # shell 基础设施
├── _tests/                     # 行为测试（make test 自动发现 test-*.sh）
├── Makefile                    # 多平台模块管理、外部技能插拔与同步
├── bootstrap.sh                # 一键部署脚本
├── opencode.json               # OpenCode 权限配置（本仓库）
├── .github/                    # CI：make test 流水线
├── .editorconfig               # 仓库代码风格配置（链接到 proj-setup 基础模板）
├── .gitattributes
├── .gitignore
├── .gitmodules                 # _vendor 外部技能子模块
├── LICENSE                     # MIT
└── README.md
```

## 🚀 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/for13to1/dotfiles.git ~/dotfiles

# 2. 一键部署
cd ~/dotfiles && bash bootstrap.sh
```

`bootstrap.sh` 会自动引导并处理以下流程：

1. **环境检测**：识别操作系统并准备核心依赖——macOS 校验 Xcode CLT（缺失时触发安装引导，需在系统对话框确认后重跑）并自动安装 Homebrew；Linux 确保 zsh、stow、make 可用。
2. **软件安装**：按默认组安装系统软件（brew/apt/pacman），macOS 应用系统设置；apt 缺失的 fnm/rustup/uv 由官方安装器补齐。
3. **生态工具**：通过 npm/uv 统一安装 CLI（pi、codex、opencode、codegraph、wrangler 为交互式询问，biome、stylua、ruff、yt-dlp 自动安装），三平台一致。
4. **SSH 设施**：交互式生成/检测 SSH 密钥，加固目录权限。
5. **Git 配置**：交互式创建本地身份配置，启用 pre-push 钩子。
6. **Shell 环境**：部署 Oh My Zsh 及其插件生态；交互模式下自动切换默认 Shell。
7. **Stow 挂载**：使用 `stow` 构建全局符号链接，自动备份文件冲突。
8. **tmux 插件**：同步 tpm 插件（见 `_scripts/tmux-plugins.sh`）。
9. **编辑器插件**：交互式同步 Neovim/Vim 的扩展插件。
10. **自定义工具**：部署 proj-setup 等自定义工具到 `~/.local/bin`。
11. **引导完成**：重启终端或 `source ~/.zshrc` 使配置生效。

### 非交互模式（CI / 容器 / 无 TTY）

```bash
cd ~/dotfiles && DOTFILES_NON_INTERACTIVE=1 bash bootstrap.sh
```

该模式使用默认选项：镜像源默认 TUNA，不自动生成 SSH 密钥或 Git 本地配置，跳过编辑器插件同步与默认 Shell 切换；交互式询问的 CLI（pi、codex、opencode、codegraph、wrangler）会全部跳过，生态工具仅自动安装 biome、stylua（npm）与 ruff、yt-dlp（uv）；各平台仍按其既定安装路径完成默认软件包、系统设置和开发工具链部署。

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

### 核心操作

#### 模块管理

Stow 包由 `_scripts/modules.conf` 统一登记，`make sync` 与 `bootstrap.sh` 共同读取该清单。

##### 新增配置包

以 `example` 模块为例

```bash
mkdir -p ~/dotfiles/example
mv ~/.example.conf ~/dotfiles/example/.example.conf
```

在 `_scripts/modules.conf` 中登记模块名 `example`，然后挂载：

```bash
make sync
```

##### 拉取远程更新

```bash
cd ~/dotfiles
git pull
make sync
```

#### 框架自检

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

#### 环境注入

新增工具 PATH 时，使用条件判断包裹，如：

```bash
# >>> postgresql@18 loading >>>
[[ -d "/opt/homebrew/opt/postgresql@18/bin" ]] && export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"
# <<< postgresql@18 loading <<<
```

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

### 组件文档

| 组件 | 文档 |
| --- | --- |
| Git 配置 | [`_docs/git.md`](_docs/git.md) |
| 网络代理 | [`_docs/net-proxy.md`](_docs/net-proxy.md) |
| SSH 管理 | [`_docs/ssh.md`](_docs/ssh.md) |
| AI Agents | [`_docs/ai-agents.md`](_docs/ai-agents.md) |

## 💡 最佳实践记录

- **Git**: 始终优先通过 Homebrew 安装 Git，以解决 macOS 自带版本在某些网络环境下的 SSL 报错问题。
- **Rust (rustup)**: 安装时建议使用静默模式并禁止修改系统 PATH（因为本项目已接管）：`rustup-init -y --no-modify-path`
- **Conda (Miniforge)**: **不用**运行 `conda init`，直接依赖 `lazy loading` 实现加速启动。
- **Formatter**: Vim 和 Neovim 从 `PATH` 或项目本地环境解析 formatter，不自行下载。

## 📄 许可证

[MIT](LICENSE)

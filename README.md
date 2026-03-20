# Dotfiles

我的跨平台开发环境配置，使用 [GNU Stow](https://www.gnu.org/software/stow/) 管理软链接。

## 📂 目录结构

```text
dotfiles/
├── agents/                     # Stow 包：通用 AI Agent 能力
│   └── .agents/
│       ├── skills/             # 专家技能
│       └── workflows/          # 自动化流程
├── codestyle/                  # Stow 包：代码风格规范
│   ├── .clang-format
│   └── .editorconfig
├── zsh/                        # Stow 包：Zsh 配置
│   └── .zshrc
├── git/                        # Stow 包：Git 全局配置
│   └── .gitconfig
├── nvim/                       # Stow 包：Neovim 深度定制
│   └── .config/nvim/
│       ├── init.lua
│       └── lazy-lock.json
├── vim/                        # Stow 包：经典 Vim 基础配置
│   └── .vimrc
├── vscode/                     # VSCode 配置备份
│   └── settings.json
├── _install/                   # 平台预装与初始化脚本
│   ├── mac/
│   │   ├── Brewfile            # Homebrew 完整软件清单
│   │   ├── Brewfile.essential  # Homebrew 必备软件清单
│   │   └── setup.sh            # macOS 系统环境设置
│   └── linux/
│       ├── apt-list.txt        # Debian/Ubuntu 软件包清单
│       ├── pacman-list.txt     # Arch Linux 软件包清单
│       └── setup.sh            # Linux 系统环境设置
├── Makefile                    # 多平台模块管理与同步
├── bootstrap.sh                # 一键部署脚本
├── .gitignore
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
2. **软件安装**：按清单安装必备工具，应用 macOS/Linux 系统设置。
3. **SSH 基础设施**：交互式生成/检测 SSH 密钥，加固目录权限。
4. **Git 身份配置**：初始化 Git LFS，交互式创建本地身份配置。
5. **Shell 环境**：部署 Oh My Zsh 及其插件生态，自动切换默认 Shell。
6. **配置挂载**：使用 `stow` 构建全局符号链接，原子化处理文件冲突。
7. **插件同步**：交互式同步开发环境 (Neovim/Vim) 的扩展插件。

## 🖥️ 本地配置

每台机器独有的私密信息放在本地文件中，**不纳入版本控制**。

### 1. `~/.zshrc.local` 示例

```bash
# AI 厂商 API 密钥
export OPENAI_API_KEY="sk-..."
export OPENAI_BASE_URL="https://api.openai.com/v1"

export ANTHROPIC_API_KEY="sk-ant-..."
export ANTHROPIC_BASE_URL="https://api.anthropic.com"

export GEMINI_API_KEY="your-api-key"
export GEMINI_BASE_URL="https://generativelanguage.googleapis.com"

# 代理设置（取消注释前请确保本地代理已启动，否则会导致网络请求失败）
# export proxy_addr="127.0.0.1:7890"
# export http_proxy="http://$proxy_addr"
# export https_proxy="http://$proxy_addr"
# export all_proxy="socks5://$proxy_addr"
## 统一大小写（增强兼容性）
# export HTTP_PROXY=$http_proxy
# export HTTPS_PROXY=$https_proxy
# export ALL_PROXY=$all_proxy
## 必须项：排除本地流量，防止本地服务访问失败
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1"
export NO_PROXY=$no_proxy
```

### 2. `~/.gitconfig.local` 示例

```ini
[user]
    name = for13to1
    email = for13to1@outlook.com
```

## 🔑 SSH 密钥管理

`bootstrap.sh` 已集成 SSH 密钥检测与生成，如需手动维护可参考：

```bash
# 1. 生成现代 Ed25519 密钥
ssh-keygen -t ed25519 -C "for13to1@outlook.com"

# 2. 将私钥加入 SSH Agent (macOS Keychain 会自动处理，Linux 需要手动)
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 3. 复制公钥并粘贴到 GitHub (Settings -> SSH and GPG Keys)
cat ~/.ssh/id_ed25519.pub

# 4. 验证连接
ssh -T git@github.com

# 5. 分发公钥到远程服务器
ssh-copy-id <user>@<host>
```

## 🤖 AI Agents 配置

基于 `.agents` 标准，管理可跨工具复用的 AI 专家技能 (Skills) 与自动化工作流 (Workflows)。

**生态兼容**: 挂载至 `~/.agents` 后，可被 Cursor, Antigravity, Claude Code 等工具自动搜索并启用。

## 🔄 日常维护

### 更新 Brewfile

想要在 macOS 上同步软件安装清单，运行以下指令：

```bash
# 1. 导出当前已安装软件清单
brew bundle dump --file=~/dotfiles/_install/mac/Brewfile --force

# 2. 提交更新
cd ~/dotfiles && git add -A && git commit -m "feat: update brewfile" && git push
```

### 添加新配置模块

若要将系统中现有的配置文件（如 `tmux`）纳入管理：

```bash
# 1. 创建符合 Stow 规范的目录结构
mkdir -p ~/dotfiles/tmux
# 2. 移动配置文件至仓库目录
mv ~/.tmux.conf ~/dotfiles/tmux/.tmux.conf
# 3. 建立软链接映射
cd ~/dotfiles && stow tmux
# 4. 持久化：将 'tmux' 添加到 Makefile 的 MODULES 变量中 (此列表也是 bootstrap.sh 的真值源)
```

### 增量更新 dotfiles

当你在远程或其他设备修改了配置，拉取更新后一键刷新：

```bash
cd ~/dotfiles && git pull
make sync  # 优雅地仅刷新 Makefile 中记录的核心模块
```

### 增加工具环境依赖

新增工具 PATH 时，使用条件判断包裹，如：

```bash
# >>> postgresql@18 loading >>>
[[ -d "/opt/homebrew/opt/postgresql@18/bin" ]] && export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"
# <<< postgresql@18 loading <<<
```

## 💡 最佳实践记录

- **Git**: 始终优先通过 Homebrew 安装 Git，以解决 macOS 自带版本在某些网络环境下的 SSL 报错问题。
- **Rust (rustup)**: 安装时建议使用静默模式并禁止修改系统 PATH（因为 `zsh/.zshrc` 已完全接管）：`rustup-init -y --no-modify-path`
- **Conda (Miniforge)**: **不用**运行 `conda init`，直接依赖 `lazy loading` 实现加速启动。

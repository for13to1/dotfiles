# Dotfiles

我的跨平台开发环境配置，使用 [GNU Stow](https://www.gnu.org/software/stow/) 管理软链接。

## 📂 目录结构

```text
dotfiles/
├── agents/                     # Stow 包：通用 AI Agent 能力
│   └── .agents/
│       ├── AGENTS.md           # Agent 通用原则
│       └── skills/             # 可复用专家技能
├── zsh/                        # Stow 包：Zsh 配置
│   ├── .zshrc
│   └── .zsh.d/
│       └── brew_mirror.sh      # Homebrew 镜像源切换
├── git/                        # Stow 包：Git 全局配置
│   └── .gitconfig
├── nvim/                       # Stow 包：Neovim 配置
│   └── .config/nvim/
│       ├── init.lua
│       └── lazy-lock.json
├── vim/                        # Stow 包：Vim 配置
│   └── .vimrc
├── vscode/                     # VSCode 配置备份
│   └── settings.json
├── proj-setup/                 # 项目配置脚本及模板
│   ├── bin/
│   └── templates/
├── _install/                   # 平台专属软件安装
│   ├── mac/
│   │   ├── Brewfile            # Homebrew 完整软件清单
│   │   └── Brewfile.essential  # Homebrew 必备软件清单
│   └── linux/
│       ├── apt-list.txt        # Debian/Ubuntu 软件包清单
│       ├── pacman-list.txt     # Arch Linux 软件包清单
│       ├── curl-install.sh     # 官方安装器途径的软件安装
│       └── npm-install.sh      # npm 生态软件安装（基于 fnm Node）
├── _setup/                     # 系统底层偏好与权限初始化脚本
│   └── mac/
│       └── setup.sh            # macOS 系统设置
├── _scripts/                   # shell 基础设施
│   ├── common.sh               # 颜色定义、函数定义等
│   ├── check-links.sh          # Stow 挂载前检查与挂载后校验
│   ├── list-modules.sh         # Stow 模块列表解析
│   ├── modules.conf            # Stow 模块列表
│   ├── stow-sync.sh            # Stow 统一同步入口
│   ├── test-check-links.sh     # check-links 行为测试
│   └── test-stow-sync.sh       # stow-sync 集成测试
├── Makefile                    # 多平台模块管理与同步
├── bootstrap.sh                # 一键部署脚本
├── .editorconfig               # 仓库代码风格配置（链接到 proj-setup 基础模板）
├── .gitattributes
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

### 非交互模式（CI / 容器 / 无 TTY）

```bash
cd ~/dotfiles && DOTFILES_NON_INTERACTIVE=1 bash bootstrap.sh
```

该模式使用默认选项：镜像源默认 TUNA，不自动生成 SSH 密钥或 Git 本地配置，跳过编辑器插件同步。

`bootstrap.sh` 会自动引导并处理以下流程：

1. **环境检测**：自动安装 Xcode CLT (macOS) 与 Homebrew，校验核心依赖。
2. **软件安装**：按清单安装必备工具，应用 macOS 系统设置。
3. **SSH 基础设施**：交互式生成/检测 SSH 密钥，加固目录权限。
4. **Git 身份配置**：初始化 Git LFS，交互式创建本地身份配置。
5. **Shell 环境**：部署 Oh My Zsh 及其插件生态，自动切换默认 Shell。
6. **配置挂载**：使用 `stow` 构建全局符号链接，原子化处理文件冲突。
7. **插件同步**：交互式同步开发环境 (Neovim/Vim) 的扩展插件。

## 🖥️ 本地配置

每台机器独有的私密信息放在本地文件中，**不纳入版本控制**。

### 1. `~/.zshrc.local` 示例

```bash
# 代理设置（取消注释前请确保本地代理已启动，否则会导致网络请求失败）
# export proxy_addr="127.0.0.1:7890"
# export http_proxy="http://$proxy_addr"
# export https_proxy="http://$proxy_addr"
# export all_proxy="socks5://$proxy_addr"
# export HTTP_PROXY=$http_proxy
# export HTTPS_PROXY=$https_proxy
# export ALL_PROXY=$all_proxy
## 必须项：排除本地流量，防止本地服务访问失败
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1"
export NO_PROXY=$no_proxy

# Homebrew 镜像源切换 (函数定义见 ~/.zsh.d/brew_mirror.sh)
brew_mirror -q ustc
# 可选值: tuna | ustc | ali | reset
# Linux 用户无需此段

# API Keys
export OPENAI_API_KEY="sk-..."
export OPENAI_BASE_URL="https://api.openai.com/v1"

export ANTHROPIC_API_KEY="sk-ant-..."
export ANTHROPIC_BASE_URL="https://api.anthropic.com"

export GEMINI_API_KEY="your-api-key"
export GEMINI_BASE_URL="https://generativelanguage.googleapis.com"
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

基于 Agent Skills 的目录约定，管理可跨工具复用的 AI 专家技能 (Skills)。

**生态兼容**: 挂载至 `~/.agents/` 后，可被 GitHub Copilot/VS Code、Gemini CLI、OpenCode、Zed、Warp、Codex CLI 等支持该路径的工具发现。

## 🔄 日常维护

### 更新 Brewfile

`_install/mac/Brewfile` 属于按需软件清单，推荐手动维护：

```bash
# 1. 编辑清单
${EDITOR:-vi} ~/dotfiles/_install/mac/Brewfile

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
# 4. 持久化：将 'tmux' 添加到 _scripts/modules.conf 中
```

### Homebrew 镜像管理

仓库内置了 `brew_mirror` 工具函数（定义于 `zsh/.zsh.d/brew_mirror.sh`），方便在不同镜像源之间快速切换：

```bash
brew_mirror              # 查看当前所有 Homebrew 相关的环境变量状态
brew_mirror tuna         # 切换至 清华大学 (TUNA) 镜像源
brew_mirror ustc         # 切换至 中国科大 (USTC) 镜像源
brew_mirror ali          # 切换至 阿里巴巴 (Aliyun) 镜像源
brew_mirror reset        # 重置为官方默认源 (unset 所有相关变量)
brew_mirror -q <source>  # 静默模式（不打印成功提示），适合放在 .zshrc.local 中使用
```

### 增量更新 dotfiles

当你在远程或其他设备修改了配置，拉取更新后一键刷新：

```bash
cd ~/dotfiles && git pull
make sync  # 优雅地仅刷新 _scripts/modules.conf 中记录的核心模块
```

### 运行自检

```bash
make test   # ShellCheck、bash 语法检查与 Stow 行为测试
make check  # 验证当前 HOME 下的 Stow 链接状态
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

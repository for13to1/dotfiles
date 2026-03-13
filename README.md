# Dotfiles

我的跨平台开发环境配置，使用 [GNU Stow](https://www.gnu.org/software/stow/) 管理软链接。

## 仓库结构

```text
dotfiles/
├── zsh/                     Stow 包：Zsh 配置
├── git/                     Stow 包：Git 配置
├── vim/                     Stow 包：Vim 配置
├── nvim/                    Stow 包：Neovim 配置
├── codestyle/               Stow 包：.editorconfig + .clang-format
├── vscode/                  VSCode 配置备份
├── skills/                  AI Agent Skills (Prompt & Workflow)
├── _install/
│   └── mac/
│       ├── Brewfile         Homebrew 软件清单
│       └── setup.sh         macOS 系统偏好设置
├── bootstrap.sh             一键装机脚本
└── README.md
```

## 🚀 新机配置

```bash
# 1. 克隆仓库
git clone https://github.com/for13to1/dotfiles.git ~/dotfiles

# 2. 一键安装
cd ~/dotfiles && bash bootstrap.sh
```

脚本会自动/交互式完成以下工作：

1. **环境检测**：自动安装 Xcode CLT (macOS) 和 Homebrew，并确保硬依赖（zsh、stow）就绪
2. **软件安装**：根据 `Brewfile.essential` 安装必备工具（nvim, git-lfs 等），应用 macOS 系统偏好设置
3. **SSH 基础设施**：检测并交互式生成 SSH 密钥，加固目录/文件权限
4. **Git 身份配置**：初始化 LFS，交互式创建 `~/.gitconfig.local`
5. **Shell 配置**：安装 Oh My Zsh + 常用插件，并自动切换默认 Shell
6. **配置挂载**：使用 `stow` 建立 dotfiles 软链接，并自动处理已有冲突文件
7. **编辑器插件同步**：交互式选择并同步 Neovim/Vim 插件

## 🔑 配置 SSH 密钥

bootstrap 已集成 SSH 密钥检测与生成。如需手动操作，可参考以下命令：

```bash
# 生成密钥（脚本已自动处理，仅供参考）
ssh-keygen -t ed25519 -C "for13to1@outlook.com"

# 将私钥加入 SSH Agent（macOS Keychain 会自动处理，Linux 环境需要手动执行）
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 复制公钥，粘贴到 GitHub → Settings → SSH and GPG Keys
cat ~/.ssh/id_ed25519.pub

# 验证连接
ssh -T git@github.com

# 分发公钥到远程机器
ssh-copy-id <user>@<host>
```

## 🔄 日常维护

### 更新 Brewfile（安装了新软件后）

```bash
brew bundle dump --file=~/dotfiles/_install/mac/Brewfile --force
cd ~/dotfiles && git add -A && git commit -m "Update Brewfile" && git push
```

### 添加新的配置文件包

以 tmux 为例：

```bash
mkdir -p ~/dotfiles/tmux
mv ~/.tmux.conf ~/dotfiles/tmux/.tmux.conf
cd ~/dotfiles && stow tmux
# 然后更新 bootstrap.sh 中的 stow 命令
```

## 🖥️ 本地配置

每台机器独有的私密信息放在本地文件中，**不纳入版本控制**

### `~/.zshrc.local`

```bash
export OPENAI_API_KEY="sk-..."
export OPENAI_BASE_URL="https://api.openai.com/v1"

export ANTHROPIC_API_KEY="sk-ant-..."
export ANTHROPIC_BASE_URL="https://api.anthropic.com"

export GEMINI_API_KEY="your-api-key"
export GEMINI_BASE_URL="https://generativelanguage.googleapis.com"

# 代理设置（取消注释前请确保本地代理已启动，否则会导致网络请求失败）
export proxy_addr="127.0.0.1:7890"
export http_proxy="http://$proxy_addr"
export https_proxy="http://$proxy_addr"
export all_proxy="socks5://$proxy_addr"
## 统一大小写（增强兼容性）
export HTTP_PROXY=$http_proxy
export HTTPS_PROXY=$https_proxy
export ALL_PROXY=$all_proxy
## 必须项：排除本地流量，防止本地服务访问失败
export no_proxy="localhost,127.0.0.1,0.0.0.0,::1"
export NO_PROXY=$no_proxy
```

### `~/.gitconfig.local`

```ini
[user]
    name = for13to1
    email = for13to1@outlook.com
```

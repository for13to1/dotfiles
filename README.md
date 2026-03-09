# Dotfiles

我的跨平台开发环境配置，使用 [GNU Stow](https://www.gnu.org/software/stow/) 管理软链接。

## 仓库结构

```text
dotfiles/
├── zsh/                     Stow 包：Zsh 配置
├── git/                     Stow 包：Git 配置
├── vim/                     Stow 包：Vim 配置
├── codestyle/               Stow 包：.editorconfig + .clang-format
├── _install/
│   └── mac/
│       ├── Brewfile         Homebrew 软件清单
│       └── setup.sh         macOS 系统偏好设置
├── bootstrap.sh             一键装机脚本
└── README.md
```

## 🚀 新机器配置

```bash
# 1. 安装 Xcode Command Line Tools
xcode-select --install

# 2. 克隆仓库
git clone https://github.com/for13to1/dotfiles.git ~/dotfiles

# 3. 一键安装
cd ~/dotfiles && bash bootstrap.sh
```

脚本会自动完成以下工作：
1. 安装 Homebrew（如果没装过）
2. 根据 `Brewfile` 安装所有命令行工具和应用程序
3. 安装 Oh My Zsh + 第三方插件
4. 使用 `stow` 建立配置文件的软链接
5. 初始化 Git LFS
6. 应用 macOS 系统偏好设置

## 🔑 配置 SSH 密钥

bootstrap 完成后，手动配置 SSH（用于 Git 推送和服务器登录）：

```bash
ssh-keygen -t ed25519 -C "for13to1@outlook.com"
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 复制公钥，粘贴到 GitHub → Settings → SSH and GPG Keys
cat ~/.ssh/id_ed25519.pub

# 验证连接
ssh -T git@github.com
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

## 🖥️ 机器专属配置

每台机器独有的私密信息放在本地文件中，**不纳入版本控制**：

**~/.zshrc.local**
```bash
export OPENAI_API_KEY="sk-..."
export OPENAI_BASE_URL="https://api.openai.com/v1"

export ANTHROPIC_API_KEY="sk-ant-..."
export ANTHROPIC_BASE_URL="https://api.anthropic.com" 

export GEMINI_API_KEY="your-api-key"
export GEMINI_BASE_URL="https://generativelanguage.googleapis.com" 

# 代理设置
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

**~/.gitconfig.local**
```ini
[user]
    name = for13to1
    email = for13to1@outlook.com
```
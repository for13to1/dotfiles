# Dotfiles

我的跨平台开发环境配置，使用 [GNU Stow](https://www.gnu.org/software/stow/) 管理软链接。

## 仓库结构

```text
dotfiles/
├── zsh/                     Stow 包：Zsh 配置
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
3. 安装 Oh My Zsh
4. 使用 `stow` 建立配置文件的软链接
5. 应用 macOS 系统偏好设置

## 🔄 日常维护

### 更新 Brewfile（安装了新软件后）

```bash
brew bundle dump --file=~/dotfiles/_install/mac/Brewfile --force
cd ~/dotfiles && git add -A && git commit -m "Update Brewfile" && git push
```

### 添加新的配置文件包

以 Git 为例：
```bash
# 1. 在仓库中创建对应的 stow 包目录
mkdir -p ~/dotfiles/git

# 2. 把配置移入仓库（注意保持 home 目录下的相对路径）
mv ~/.gitconfig ~/dotfiles/git/.gitconfig

# 3. 用 stow 建立软链接
cd ~/dotfiles && stow git
```

## 🖥️ 机器专属配置

每台机器的私密信息（API Key、代理地址等）放在 `~/.zshrc.local`，该文件**不纳入版本控制**。

```bash
# ~/.zshrc.local 示例
export OPENAI_API_KEY="sk-..."
export HTTP_PROXY="http://127.0.0.1:7890"
```
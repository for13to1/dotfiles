# =============================================================================
# 1. Foundation Framework
# =============================================================================

# Homebrew (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi

    if command -v brew &>/dev/null; then
        export HOMEBREW_NO_AUTO_UPDATE=1
    fi
    # 加载 ~/.zsh.d/ 下的所有函数片段（stow 挂载自 zsh/.zsh.d/）
    for _f in ~/.zsh.d/*.sh; do [[ -f "$_f" ]] && source "$_f"; done
    unset _f
fi

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
CASE_SENSITIVE="true"
ZSH_THEME="robbyrussell"

# 动态构建插件列表：第三方插件需要检查是否存在
plugins=(
    git
    sudo
    z
    fzf
    brew
    conda
    vscode
    copypath
    copybuffer
)

# 第三方插件：检查是否存在再添加
local missing_plugins=()
if [[ -d "$ZSH/custom/plugins/zsh-autosuggestions" ]]; then
    plugins+=(zsh-autosuggestions)
else
    missing_plugins+=("zsh-autosuggestions")
fi

if [[ -d "$ZSH/custom/plugins/zsh-syntax-highlighting" ]]; then
    plugins+=(zsh-syntax-highlighting)
else
    missing_plugins+=("zsh-syntax-highlighting")
fi

if (( ${#missing_plugins[@]} > 0 )); then
    echo -e "\033[1;33m⚠️  提醒: 发现缺失插件 ${missing_plugins[*]}，请运行 bootstrap.sh 进行补全\033[0m"
fi

source "$ZSH/oh-my-zsh.sh"

# =============================================================================
# 2. Environment Variables
# =============================================================================

export LANG=en_US.UTF-8
if command -v nvim &>/dev/null; then
    export EDITOR="nvim"
else
    export EDITOR="vim"
fi
export VISUAL="$EDITOR"
# export LD_LIBRARY_PATH="$OpenCV_DIR/lib/:$LD_LIBRARY_PATH"
export PATH="$HOME/.local/bin:$PATH"
# PATH 列表中，靠前的路径优先级最高
# https://www.gnu.org/software/bash/manual/bash.html#Command-Search-and-Execution

# =============================================================================
# 3. Local Config
# =============================================================================

# API Key 等私密信息统统放在 ~/.zshrc.local 里，不纳入版本控制
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# =============================================================================
# 4. Runtime Managers
# =============================================================================

# >>> lazy conda loading >>>
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (Miniforge via Homebrew)
    export CONDA_ROOT="/opt/homebrew/Caskroom/miniforge/base"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux (Miniforge)
    if [[ -d "$HOME/miniforge3" ]]; then
        export CONDA_ROOT="$HOME/miniforge3"
    elif [[ -d "/opt/miniforge3" ]]; then
        export CONDA_ROOT="/opt/miniforge3"
    fi
fi

if [[ -d "$CONDA_ROOT" ]]; then
    conda() {
        unset -f conda
        source "$CONDA_ROOT/etc/profile.d/conda.sh"
        conda "$@"
    }
fi
# <<< lazy conda loading <<<

# >>> fnm loading >>>
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi
# <<< fnm loading <<<

# >>> rustup (cargo) loading >>>
# 只有当安装了 rustup 时才添加 bin 目录到 PATH
[[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"
# <<< rustup loading <<<

# >>> postgresql@18 loading >>>
[[ -d "/opt/homebrew/opt/postgresql@18/bin" ]] && export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"
# <<< postgresql@18 loading <<<

# >>> opencode loading >>>
# 安装时使用 --no-modify-path 避免脚本自动修改 .zshrc
# curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"
# <<< opencode loading <<<

# >>> zoxide (better cd) loading >>>
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi
# <<< zoxide loading <<<

# =============================================================================
# 5. Aliases
# =============================================================================

alias vi="vim"

# command -v 是 shell built-in，不 fork 进程，性能无忧
if command -v eza &>/dev/null; then
    alias ll="eza -al --icons --group-directories-first"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    alias ll="ls -alGF"
else
    alias ll="ls -alF --color=auto"
fi

function grn() {
    if grep --help 2>/dev/null | grep -q -- '--color'; then
        grep --color=auto -rnw "$@"
    else
        grep -rnw "$@"
    fi
}

# 以下 git 别名已由 OMZ git 插件提供，保留 gl1g（OMZ 无对应）
alias gl1g='git log --oneline --graph --decorate --all'

# =============================================================================
# 6. Functions
# =============================================================================

# sudo apt install qrencode
# sudo pacman -S qrencode
function qrc() { qrencode -m 2 -t utf8 <<< "$1"; }
# conda install -c conda-forge qrcode
function qrp() { qr "$1"; }

# conda install -c conda-forge yt-dlp
function ytdf() { yt-dlp -f bestvideo+bestaudio --write-subs --cookies-from-browser firefox "$1"; }
function ytds() { yt-dlp -f bestvideo+bestaudio --write-subs --cookies-from-browser safari "$1"; }

function grnh() {
    if grep --help 2>/dev/null | grep -q -- '--color'; then
        grep --color=auto -rnw "$1" /usr/include/*.h
    else
        grep -rnw "$1" /usr/include/*.h
    fi
}

function base64_encode() { echo -n "$1" | base64; }

function base64_decode() { echo -n "$1" | base64 -d; }

function csv_shape() {
    if [ "$#" -ne 1 ]; then echo "Usage: csv_shape <csv_file>"; return 1; fi
    python3 -c "import sys, numpy as np; d=np.loadtxt(sys.argv[1], delimiter=','); print(d.shape)" "$1"
}

function csv_create() {
    if [ "$#" -ne 3 ]; then echo "Usage: csv_create <rows> <cols> <filename>"; return 1; fi
    python3 -c "import sys, numpy as np; np.random.seed(0); data = np.random.rand(int(sys.argv[1]), int(sys.argv[2])); np.savetxt(sys.argv[3], data, delimiter=',', fmt='%0.6f')" "$1" "$2" "$3"
    echo "CSV file '$3' created with $1 rows and $2 columns."
}

# =============================================================================
# 7. Editor Integrations
# =============================================================================

# >>> vscode python
# version: 0.1.0
if [ -n "$VSCODE_ZSH_ACTIVATE" ] && [ "$TERM_PROGRAM" = "vscode" ]; then
    eval "$VSCODE_ZSH_ACTIVATE" || true
fi
# <<< vscode python

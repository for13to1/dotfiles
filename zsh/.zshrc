# =============================================================================
# 0. Shell Framework
# =============================================================================

export ZSH="$HOME/.oh-my-zsh"
export LANG=en_US.UTF-8
CASE_SENSITIVE="true"
ZSH_THEME="robbyrussell"
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
    zsh-autosuggestions
    zsh-syntax-highlighting
)
source $ZSH/oh-my-zsh.sh


# =============================================================================
# 1. Environment Variables
# =============================================================================

export EDITOR=vim
# export LD_LIBRARY_PATH="$OpenCV_DIR/lib/:$LD_LIBRARY_PATH"
export PATH="$HOME/.local/bin:$PATH"
# PATH 列表中，靠前的路径优先级最高
# https://www.gnu.org/software/bash/manual/bash.html#Command-Search-and-Execution

# =============================================================================
# 2. Local Config
# =============================================================================

# API Key 等私密信息统统放在 ~/.zshrc.local 里，不纳入版本控制
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# =============================================================================
# 3. Runtime Managers
# =============================================================================

# >>> lazy conda loading >>>
export CONDA_ROOT="/opt/homebrew/Caskroom/miniforge/base"
conda() {
    unset -f conda
    source "$CONDA_ROOT/etc/profile.d/conda.sh"
    conda "$@"
}
# <<< lazy conda loading <<<

# >>> fnm loading >>>
eval "$(fnm env --use-on-cd --shell zsh)"
# <<< fnm loading <<<

# =============================================================================
# 4. Aliases
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

alias grn="grep --color=auto -rnw"

# 以下 git 别名已由 OMZ git 插件提供，保留 gl1g（OMZ 无对应）
alias gl1g='git log --oneline --graph --decorate --all'

# =============================================================================
# 5. Functions
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
    grep --color=auto -rnw "$1" /usr/include/*.h
}
[[ -n "$BASH" ]] && export -f grnh

function base64_encode() { echo -n "$1" | base64; }
[[ -n "$BASH" ]] && export -f base64_encode

function base64_decode() { echo -n "$1" | base64 -d; }
[[ -n "$BASH" ]] && export -f base64_decode

function csv_shape() {
    if [ "$#" -ne 1 ]; then echo "Usage: csv_shape <csv_file>"; return 1; fi
    python -c "import sys, numpy as np; d=np.loadtxt(sys.argv[1], delimiter=','); print(d.shape)" "$1"
}
[[ -n "$BASH" ]] && export -f csv_shape

function csv_create() {
    if [ "$#" -ne 3 ]; then echo "Usage: csv_create <rows> <cols> <filename>"; return 1; fi
    python -c "import sys, numpy as np; np.random.seed(0); data = np.random.rand(int(sys.argv[1]), int(sys.argv[2])); np.savetxt(sys.argv[3], data, delimiter=',', fmt='%0.6f')" "$1" "$2" "$3"
    echo "CSV file '$3' created with $1 rows and $2 columns."
}
[[ -n "$BASH" ]] && export -f csv_create

# =============================================================================
# 6. Editor Integrations
# =============================================================================

# >>> vscode python
# version: 0.1.0
if [ -n "$VSCODE_ZSH_ACTIVATE" ] && [ "$TERM_PROGRAM" = "vscode" ]; then
    eval "$VSCODE_ZSH_ACTIVATE" || true
fi
# <<< vscode python

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
fi

# Source every function snippet under ~/.zsh.d/ (loaded on both macOS and Linux).
# Examples: brew_mirror (Homebrew mirror), net_proxy (proxy on/off).
for _f in ~/.zsh.d/*.sh; do [[ -f "$_f" ]] && source "$_f"; done
unset _f

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
CASE_SENSITIVE="true"
ZSH_THEME="robbyrussell"

# Build the plugin list dynamically: third-party plugins must be checked for existence.
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

# Third-party plugins: add only if present.
missing_plugins=()
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
    echo -e "\033[1;33m⚠️  Notice: Oh My Zsh is missing plugins ${missing_plugins[*]}; install them and reload the shell\033[0m"
fi

if [[ -r "$ZSH/oh-my-zsh.sh" ]]; then
    source "$ZSH/oh-my-zsh.sh"
else
    echo -e "\033[1;33m⚠️  Notice: Oh My Zsh not found; skipped framework loading\033[0m"
fi

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
# Earlier PATH entries win.
# https://www.gnu.org/software/bash/manual/bash.html#Command-Search-and-Execution

# =============================================================================
# 3. Local Config
# =============================================================================

# Keep private data (API keys, etc.) in ~/.zshrc.local, out of version control.
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
if [[ "$OSTYPE" == linux* ]] && ! command -v fnm &>/dev/null; then
    [[ -x "${XDG_DATA_HOME:-$HOME/.local/share}/fnm/fnm" ]] \
        && export PATH="${XDG_DATA_HOME:-$HOME/.local/share}/fnm:$PATH"
fi
if command -v fnm &>/dev/null; then
    eval "$(fnm env --use-on-cd --shell zsh)"
fi
# <<< fnm loading <<<

# >>> rustup (cargo) loading >>>
# rustup's proxy location differs by platform:
#   - macOS: Homebrew's rustup is keg-only; the proxy lives in brew's opt dir (no ~/.cargo/bin).
#   - Linux: Debian official installer / Arch pacman; the proxy is always in ~/.cargo/bin.
case "$OSTYPE" in
    darwin*)
        [[ -d "/opt/homebrew/opt/rustup/bin" ]] && export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
        ;;
    *)
        [[ -d "$HOME/.cargo/bin" ]] && export PATH="$HOME/.cargo/bin:$PATH"
        ;;
esac
# <<< rustup loading <<<

# >>> postgresql loading >>>
for _pg_dir in /opt/homebrew/opt/postgresql*(-/N); do
    [[ -d "$_pg_dir/bin" ]] && export PATH="$_pg_dir/bin:$PATH"
done
unset _pg_dir
# <<< postgresql loading <<<

# >>> zoxide (better cd) loading >>>
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init zsh)"
fi
# <<< zoxide loading <<<

# >>> ripgrep loading >>>
if command -v rg &>/dev/null; then
    export RIPGREP_CONFIG_PATH="$HOME/.ripgreprc"
fi
# <<< ripgrep loading <<<

# >>> opencode loading >>>
# Install with --no-modify-path so the script never rewrites .zshrc.
# curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"
# <<< opencode loading <<<

# >>> mimocode loading >>>
# Install with --no-modify-path so the script never rewrites .zshrc.
# curl -fsSL https://mimo.xiaomi.com/install | bash -s -- --no-modify-path
[[ -d "$HOME/.mimocode/bin" ]] && export PATH="$HOME/.mimocode/bin:$PATH"
# <<< mimocode loading <<<

# =============================================================================
# 5. Aliases
# =============================================================================

alias vi="vim"

# command -v is a shell builtin; it does not fork, so it is cheap.
if command -v eza &>/dev/null; then
    alias ll="eza -al --icons --group-directories-first"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    alias ll="ls -alGF"
else
    alias ll="ls -alF --color=auto"
fi

function grn() {
    if command -v rg &>/dev/null; then
        rg -n -w "$@"
    elif grep --help 2>/dev/null | grep -q -- '--color'; then
        grep --color=auto -rnw "$@"
    else
        grep -rnw "$@"
    fi
}

# These git aliases are already provided by the OMZ git plugin; keep gl1g (OMZ has none).
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
    local inc_dir="/usr/include"
    if [[ "$OSTYPE" == "darwin"* ]] && command -v xcrun &>/dev/null; then
        local sdk_path
        sdk_path="$(xcrun --show-sdk-path 2>/dev/null)"
        [[ -n "$sdk_path" && -d "$sdk_path/usr/include" ]] && inc_dir="$sdk_path/usr/include"
    fi

    if [[ ! -d "$inc_dir" ]]; then
        echo "Error: include directory not found: $inc_dir" >&2
        return 1
    fi

    if command -v rg &>/dev/null; then
        rg --max-depth 1 -n -w -g '*.h' "$1" "$inc_dir"
    elif grep --help 2>/dev/null | grep -q -- '--color'; then
        find "$inc_dir" -maxdepth 1 -name '*.h' -exec grep --color=auto -nw "$1" {} + 2>/dev/null
    else
        find "$inc_dir" -maxdepth 1 -name '*.h' -exec grep -nw "$1" {} + 2>/dev/null
    fi
}

function base64_encode() { echo -n "$1" | base64; }

function base64_decode() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo -n "$1" | base64 -D
    else
        echo -n "$1" | base64 -d
    fi
}

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

# =============================================================================
# 8. Terminal Key Mode Safety Net
# =============================================================================

# The terminal's extended key mode (modifyOtherKeys/CSI-u) can leak when tmux/nvim exits
# abnormally, making plain zsh render Ctrl+A's ESC[27;5;97~ as ";5;97~".
# Provide a manual reset alias and auto-clean on new shells outside tmux.
# The reset covers both xterm-style (CSI > 4;0m / CSI > 4n) and kitty-style (CSI < 1 u).

alias fix-kb='printf "\033[>4;0m" && printf "\033[>4n" && printf "\033[<1u"'

if [[ -z "$TMUX" ]]; then
    printf '\033[>4;0m'
    printf '\033[<1u'
fi

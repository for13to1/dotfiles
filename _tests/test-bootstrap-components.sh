#!/usr/bin/env bash
# test-bootstrap-components.sh — behavior tests for _bootstrap/*.sh components
# Usage: bash _tests/test-bootstrap-components.sh

set -euo pipefail
# shellcheck disable=SC1091  # helpers.sh is sourced via a dynamic path
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-components.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

TEST_HOME="$TMP/home"
mkdir -p "$TEST_HOME"

for component in "$ROOT"/_bootstrap/*.sh; do
    [[ -x "$component" ]] || fail "$component must be executable"
done

MOCK_BIN="$TMP/mock-bin"
MOCK_LOG="$TMP/mock-log"
mkdir -p "$MOCK_BIN" "$MOCK_LOG"
cat > "$MOCK_BIN/nvim" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG/nvim"
EOF
cat > "$MOCK_BIN/vim" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG/vim"
if [[ -n "${MOCK_VIM_PROBE_FAIL:-}" && "$*" == *'exists(":PlugInstall")'* ]]; then
    exit 2
fi
if [[ -n "${MOCK_VIM_UPDATE_FAIL:-}" && "$*" == *'PlugUpdate --sync'* ]]; then
    exit 1
fi
EOF
cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG/curl"
if [[ "${1:-}" == "-fLo" ]]; then
    mkdir -p "$(dirname "$2")"
    touch "$2"
fi
EOF
for command_name in zsh sudo chsh; do
    cat > "$MOCK_BIN/$command_name" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG/$(basename "$0")"
EOF
done
chmod +x "$MOCK_BIN"/*

# SSH: non-interactive mode creates infrastructure without generating a key.
HOME="$TEST_HOME" DOTFILES_NON_INTERACTIVE=1 bash "$ROOT/_bootstrap/ssh.sh" >/dev/null
HOME="$TEST_HOME" DOTFILES_NON_INTERACTIVE=1 bash "$ROOT/_bootstrap/ssh.sh" >/dev/null
[[ -f "$TEST_HOME/.ssh/config" ]] || fail "SSH component must create ~/.ssh/config"
[[ ! -e "$TEST_HOME/.ssh/id_ed25519" ]] || fail "SSH component must not generate a key non-interactively"

# Shell: existing OMZ/plugin directories isolate the test from network access.
mkdir -p \
    "$TEST_HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" \
    "$TEST_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
HOME="$TEST_HOME" SHELL=/bin/zsh ZSH_CUSTOM="$TEST_HOME/.oh-my-zsh/custom" DOTFILES_NON_INTERACTIVE=1 \
    bash "$ROOT/_bootstrap/shell.sh" Linux >/dev/null
[[ -f "$TEST_HOME/.zshrc.local" ]] || fail "Shell component must create ~/.zshrc.local"
grep -q 'OPENAI_API_KEY' "$TEST_HOME/.zshrc.local" || fail "Local shell template must include API key examples"
grep -q 'brew_mirror' "$TEST_HOME/.zshrc.local" && fail "Linux local shell template must not configure brew mirrors"

rm -f "$TEST_HOME/.zshrc.local"
HOME="$TEST_HOME" SHELL=/bin/zsh ZSH_CUSTOM="$TEST_HOME/.oh-my-zsh/custom" DOTFILES_NON_INTERACTIVE=1 \
    bash "$ROOT/_bootstrap/shell.sh" Darwin tuna >/dev/null
grep -qx 'brew_mirror -q tuna' "$TEST_HOME/.zshrc.local" || fail "macOS local shell template must persist the selected mirror"

# Non-interactive shell setup must not invoke sudo/chsh even when zsh is available.
HOME="$TEST_HOME" SHELL=/bin/bash ZSH_CUSTOM="$TEST_HOME/.oh-my-zsh/custom" \
    DOTFILES_NON_INTERACTIVE=1 MOCK_LOG="$MOCK_LOG" PATH="$MOCK_BIN:$PATH" \
    bash "$ROOT/_bootstrap/shell.sh" Linux > "$TMP/shell-non-interactive.out"
grep -q 'Skipping the default shell switch' "$TMP/shell-non-interactive.out" \
    || fail "Non-interactive shell setup must explain that default shell switching is skipped"
[[ ! -e "$MOCK_LOG/sudo" && ! -e "$MOCK_LOG/chsh" ]] \
    || fail "Non-interactive shell setup must not invoke sudo or chsh"

# Git: configure hooks in an isolated repository and skip identity interactively.
mkdir -p "$TMP/repo/_scripts/hooks"
git -C "$TMP/repo" init -q
HOME="$TEST_HOME" DOTFILES_NON_INTERACTIVE=1 \
    bash "$ROOT/_bootstrap/git.sh" "$TMP/repo" >/dev/null
HOME="$TEST_HOME" DOTFILES_NON_INTERACTIVE=1 \
    bash "$ROOT/_bootstrap/git.sh" "$TMP/repo" >/dev/null
expected_hooks="$(cd -P "$TMP/repo" && pwd)/_scripts/hooks"
actual_hooks="$(git -C "$TMP/repo" config --get core.hooksPath)"
[[ "$actual_hooks" == "$expected_hooks" ]] || fail "Git component must configure the repository hooks path"

# Invalid explicit repository paths must survive resolution in error messages.
missing_repo="$TMP/missing-repo"
if HOME="$TEST_HOME" DOTFILES_NON_INTERACTIVE=1 \
    bash "$ROOT/_bootstrap/git.sh" "$missing_repo" > "$TMP/git-error.out" 2>&1; then
    fail "Git component must reject an inaccessible repository path"
fi
grep -q "$missing_repo" "$TMP/git-error.out" || fail "Git component error must retain the original path"

if HOME="$TEST_HOME" bash "$ROOT/_bootstrap/tools.sh" "$missing_repo" > "$TMP/tools-error.out" 2>&1; then
    fail "Tools component must reject an inaccessible repository path"
fi
grep -q "$missing_repo" "$TMP/tools-error.out" || fail "Tools component error must retain the original path"

if HOME="$TEST_HOME" bash "$ROOT/_bootstrap/pkg-mac.sh" "$missing_repo" > "$TMP/pkg-mac-error.out" 2>&1; then
    fail "Pkg Mac component must reject an inaccessible repository path"
fi
grep -q "$missing_repo" "$TMP/pkg-mac-error.out" || fail "Pkg Mac component error must retain the original path"

# Pkg-mac: when Xcode/CLT is missing, it must trigger installer and exit non-zero (must not exit 0).
MOCK_CLT_BIN="$TMP/mock-clt-bin"
mkdir -p "$MOCK_CLT_BIN"
cat > "$MOCK_CLT_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "-p" ]]; then
    exit 1
fi
if [[ "$*" == "--install" ]]; then
    exit 0
fi
EOF
chmod +x "$MOCK_CLT_BIN/xcode-select"

if XCODE_APP_DIR="$TMP/no-xcode" PATH="$MOCK_CLT_BIN:$PATH" HOME="$TEST_HOME" \
    bash "$ROOT/_bootstrap/pkg-mac.sh" "$ROOT" > "$TMP/pkg-mac-clt-fail.out" 2>&1; then
    fail "Pkg Mac component must exit non-zero when Xcode CLT is missing"
fi
grep -q "installing Command Line Tools" "$TMP/pkg-mac-clt-fail.out" || fail "Pkg Mac must report CLT installation"
[[ ! -f "$ROOT/_bootstrap/.last_brew_mirror" ]] || fail "Pkg Mac must not leave temporary .last_brew_mirror file"

# Pkg-mac: stdout must contain ONLY the clean mirror name, untouched by subcommand stdout pollution
MOCK_MAC_BIN="$TMP/mock-mac-bin"
mkdir -p "$MOCK_MAC_BIN"
cat > "$MOCK_MAC_BIN/xcode-select" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$MOCK_MAC_BIN/brew" <<'EOF'
#!/usr/bin/env bash
echo "Already up-to-date."
EOF
chmod +x "$MOCK_MAC_BIN"/*

captured_mirror="$(PATH="$MOCK_MAC_BIN:$PATH" HOME="$TEST_HOME" DOTFILES_NON_INTERACTIVE=1 \
    bash "$ROOT/_bootstrap/pkg-mac.sh" "$ROOT" "ustc" 2>/dev/null)"
[[ "$captured_mirror" == "ustc" ]] || fail "Pkg Mac must output only the mirror name on stdout, got: '$captured_mirror'"

if HOME="$TEST_HOME" bash "$ROOT/_bootstrap/pkg-linux.sh" "$missing_repo" > "$TMP/pkg-linux-error.out" 2>&1; then
    fail "Pkg Linux component must reject an inaccessible repository path"
fi
grep -q "$missing_repo" "$TMP/pkg-linux-error.out" || fail "Pkg Linux component error must retain the original path"

# Editors: non-interactive mode skips silently actionable UI and all commands.
EDITOR_HOME="$TMP/editor-home"
mkdir -p "$EDITOR_HOME"
HOME="$EDITOR_HOME" DOTFILES_NON_INTERACTIVE=1 MOCK_LOG="$MOCK_LOG" PATH="$MOCK_BIN:$PATH" \
    bash "$ROOT/_bootstrap/editors.sh" > "$TMP/editors-skip.out"
grep -q 'skipping editor plugin sync' "$TMP/editors-skip.out" || fail "Non-interactive editor setup must report the skip"
grep -q 'Select the editor plugins' "$TMP/editors-skip.out" && fail "Non-interactive editor setup must not print an interactive menu"
[[ ! -e "$EDITOR_HOME/.vim/autoload/plug.vim" ]] || fail "Non-interactive editor setup must not install vim-plug"
[[ ! -e "$MOCK_LOG/nvim" && ! -e "$MOCK_LOG/vim" && ! -e "$MOCK_LOG/curl" ]] \
    || fail "Non-interactive editor setup must not invoke editor or download commands"

# Choice 1 synchronizes only Neovim.
printf '1\n' | HOME="$EDITOR_HOME" MOCK_LOG="$MOCK_LOG" PATH="$MOCK_BIN:$PATH" \
    bash "$ROOT/_bootstrap/editors.sh" >/dev/null
grep -qx -- '--headless +Lazy! sync +qa' "$MOCK_LOG/nvim" || fail "Choice 1 must synchronize Neovim"
[[ ! -e "$MOCK_LOG/vim" && ! -e "$MOCK_LOG/curl" ]] || fail "Choice 1 must not invoke Vim setup"

# Choice 2 installs vim-plug, probes it, and updates plugins.
printf '2\n' | HOME="$EDITOR_HOME" MOCK_LOG="$MOCK_LOG" PATH="$MOCK_BIN:$PATH" \
    bash "$ROOT/_bootstrap/editors.sh" >/dev/null
[[ -f "$EDITOR_HOME/.vim/autoload/plug.vim" ]] || fail "Choice 2 must install vim-plug when missing"
grep -q 'junegunn/vim-plug' "$MOCK_LOG/curl" || fail "Choice 2 must download vim-plug"
[[ "$(wc -l < "$MOCK_LOG/vim" | tr -d ' ')" == 2 ]] || fail "Choice 2 must probe and update Vim plugins"
grep -q 'PlugUpdate --sync' "$MOCK_LOG/vim" || fail "Choice 2 must update Vim plugins"

# A failed vim-plug probe reports the load failure and does not update.
: > "$MOCK_LOG/vim"
printf '2\n' | HOME="$EDITOR_HOME" MOCK_LOG="$MOCK_LOG" MOCK_VIM_PROBE_FAIL=1 PATH="$MOCK_BIN:$PATH" \
    bash "$ROOT/_bootstrap/editors.sh" > "$TMP/editors-probe-fail.out"
grep -q 'vim-plug failed to load' "$TMP/editors-probe-fail.out" || fail "Vim probe failure must be reported"
[[ "$(wc -l < "$MOCK_LOG/vim" | tr -d ' ')" == 1 ]] || fail "Failed Vim probe must skip plugin update"

# Choice 3 composes both editor workflows.
rm -f "$MOCK_LOG/nvim" "$MOCK_LOG/vim"
printf '3\n' | HOME="$EDITOR_HOME" MOCK_LOG="$MOCK_LOG" PATH="$MOCK_BIN:$PATH" \
    bash "$ROOT/_bootstrap/editors.sh" >/dev/null
[[ -s "$MOCK_LOG/nvim" ]] || fail "Choice 3 must synchronize Neovim"
grep -q 'PlugUpdate --sync' "$MOCK_LOG/vim" || fail "Choice 3 must synchronize Vim"

# Tools: deploy repository-owned commands into the isolated HOME.
HOME="$TEST_HOME" bash "$ROOT/_bootstrap/tools.sh" "$ROOT" >/dev/null
HOME="$TEST_HOME" bash "$ROOT/_bootstrap/tools.sh" "$ROOT" >/dev/null
[[ -L "$TEST_HOME/.local/bin/proj-setup" ]] || fail "Tools component must deploy proj-setup as a symlink"
[[ "$(readlink "$TEST_HOME/.local/bin/proj-setup")" == "$ROOT/proj-setup/bin/proj-setup.sh" ]] \
    || fail "proj-setup symlink must target the repository command"

echo "PASS bootstrap component tests"

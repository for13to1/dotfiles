#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/_scripts/tmux-plugins.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tmux-plugins-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fake_bin="$TMP/bin"
mkdir -p "$fake_bin"
home="$TMP/home"
mkdir -p "$home"

fail() {
    echo "FAIL $*" >&2
    exit 1
}

# 模拟 clone 后的 tpm 命令。
cat > "$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
target="${@: -1}"
mkdir -p "$target/bin"
cat > "$target/bin/install_plugins" <<'PLUGIN'
#!/usr/bin/env bash
[[ "${TMUX_PLUGIN_MANAGER_PATH:-}" == "$HOME/.tmux/plugins" ]] || exit 1
echo "install_plugins called" >> "$FAKE_MARKER"
exit "${FAKE_INSTALL_EXIT:-0}"
PLUGIN
echo "git clone -> $target" >> "$FAKE_MARKER"
exit 0
EOF
chmod +x "$fake_bin/git"

# 记录 tmux server 环境设置；FAKE_NO_SERVER=1 模拟无 server 时 set-environment 失败。
cat > "$fake_bin/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "set-environment" ]]; then
    echo "$*" >> "$FAKE_MARKER"
    [[ -n "${FAKE_NO_SERVER:-}" ]] && exit 1
fi
exit 0
EOF
chmod +x "$fake_bin/tmux"

run_script() {
    : > "$TMP/marker"
    HOME="$home" PATH="$fake_bin:/usr/bin:/bin" \
        FAKE_MARKER="$TMP/marker" \
        FAKE_INSTALL_EXIT="${FAKE_INSTALL_EXIT:-0}" \
        FAKE_NO_SERVER="${FAKE_NO_SERVER:-}" \
        DOTFILES_TMUX_NO_SYSTEM_TPM=1 \
        bash "$SCRIPT"
}

if run_script >/dev/null 2>&1; then
    fail "tmux-plugins should fail when ~/.tmux.conf is missing"
fi

touch "$home/.tmux.conf"
mkdir -p "$home/.tmux/plugins/tpm"
if run_script >/dev/null 2>&1; then
    fail "tmux-plugins should fail on an incomplete TPM directory"
fi

rm -rf "$home/.tmux/plugins/tpm"
run_script >/dev/null 2>&1
[[ -f "$home/.tmux/plugins/tpm/bin/install_plugins" ]] \
    || fail "TPM not cloned to default dir"
grep -q "set-environment -g TMUX_PLUGIN_MANAGER_PATH $home/.tmux/plugins" "$TMP/marker" \
    || fail "set-environment not called with default path"
grep -q "^install_plugins called" "$TMP/marker" \
    || fail "install_plugins not invoked"

rm -rf "$home/.tmux/plugins/tpm"
if FAKE_INSTALL_EXIT=1 run_script >/dev/null 2>&1; then
    fail "tmux-plugins should fail when install_plugins fails"
fi

# 5) 无 server 场景：set-environment 失败（模拟 "no server running"）但脚本应继续并成功
rm -rf "$home/.tmux/plugins/tpm"
if ! FAKE_NO_SERVER=1 run_script >/dev/null 2>&1; then
    fail "tmux-plugins should succeed even when set-environment fails (no server)"
fi

echo "PASS tmux-plugins tests"

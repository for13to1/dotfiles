#!/usr/bin/env bash
#
# test-stow-sync.sh — stow-sync.sh 集成测试
# 用法: bash _scripts/test-stow-sync.sh
#

set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/stow-sync.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mkdir -p "$TMP/bin" "$TMP/dotfiles/git/.venv/bin" "$TMP/home"
printf 'new\n' > "$TMP/dotfiles/git/.gitconfig"
printf 'old\n' > "$TMP/home/.gitconfig"
printf 'fake\n' > "$TMP/dotfiles/git/.venv/bin/python"

cat > "$TMP/bin/stow" <<'FAKE_STOW'
#!/usr/bin/env bash
set -euo pipefail

target=""
modules=()
ignores=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t)
            target="$2"
            shift 2
            ;;
        -R)
            shift
            ;;
        --ignore=*)
            ignores+=("${1#--ignore=}")
            shift
            ;;
        *)
            modules+=("$1")
            shift
            ;;
    esac
done

for mod in "${modules[@]}"; do
    while IFS= read -r -d '' entry; do
        rel="${entry#"$mod"/}"
        skip=false
        for ignore in "${ignores[@]}"; do
            if [[ "$rel" == "$ignore" || "$rel" == "$ignore"/* ]]; then
                skip=true
                break
            fi
        done
        [[ "$skip" == false ]] || continue
        ln -sfn "../dotfiles/$mod/$rel" "$target/$rel"
    done < <(find "$mod" -mindepth 1 -maxdepth 1 \( -type f -o -type d -o -type l \) -print0)
done
FAKE_STOW
chmod +x "$TMP/bin/stow"

PATH="$TMP/bin:$PATH" bash "$ROOT/_scripts/stow-sync.sh" \
    "$TMP/dotfiles" "$TMP/home" git >/dev/null

[[ -L "$TMP/home/.gitconfig" ]] || fail "expected .gitconfig to be a symlink"
[[ "$(cat "$TMP/home/.gitconfig")" == "new" ]] || fail "symlink did not point to source file"
find "$TMP/home" -maxdepth 1 -name '.gitconfig.bak.*' -print -quit | grep -q . \
    || fail "expected existing file to be backed up"
[[ ! -e "$TMP/home/.venv" ]] || fail "ignored .venv should not be stowed"

echo "PASS stow-sync tests"

#!/usr/bin/env bash
# test-skills-vendor.sh — integration tests for _scripts/skills-vendor.sh
# Usage: bash _tests/test-skills-vendor.sh

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/skills-vendor.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Prepare sandbox layout
mkdir -p "$TMP/bin" "$TMP/dotfiles/_scripts" "$TMP/dotfiles/_vendor" "$TMP/dotfiles/agents/.agents/skills/native-skill" "$TMP/home/.agents/skills"

# Copy common.sh and skills-vendor.sh into test dotfiles
cp "$ROOT/_scripts/common.sh" "$TMP/dotfiles/_scripts/"
cp "$ROOT/_scripts/skills-vendor.sh" "$TMP/dotfiles/_scripts/"
chmod +x "$TMP/dotfiles/_scripts/skills-vendor.sh"

# Create fake stow-sync.sh to bypass system stow during tests
cat > "$TMP/dotfiles/_scripts/stow-sync.sh" <<'FAKE_STOW_SYNC'
#!/usr/bin/env bash
exit 0
FAKE_STOW_SYNC
chmod +x "$TMP/dotfiles/_scripts/stow-sync.sh"

# 1. Setup native skill
printf -- "---\nname: native-skill\n---\n" > "$TMP/dotfiles/agents/.agents/skills/native-skill/SKILL.md"

# 2. Setup mock vendors
# Vendor A (matt)
mkdir -p "$TMP/dotfiles/_vendor/matt/cat/skill-one" "$TMP/dotfiles/_vendor/matt/cat/native-skill" "$TMP/dotfiles/_vendor/matt/cat/common-skill"
printf -- "---\nname: skill-one\n---\n" > "$TMP/dotfiles/_vendor/matt/cat/skill-one/SKILL.md"
printf -- "---\nname: native-skill\n---\n" > "$TMP/dotfiles/_vendor/matt/cat/native-skill/SKILL.md"
printf -- "---\nname: common-skill\n---\n" > "$TMP/dotfiles/_vendor/matt/cat/common-skill/SKILL.md"

# Vendor B (mattpocock)
mkdir -p "$TMP/dotfiles/_vendor/mattpocock/cat/skill-two" "$TMP/dotfiles/_vendor/mattpocock/cat/common-skill"
printf -- "---\nname: skill-two\n---\n" > "$TMP/dotfiles/_vendor/mattpocock/cat/skill-two/SKILL.md"
printf -- "---\nname: common-skill\n---\n" > "$TMP/dotfiles/_vendor/mattpocock/cat/common-skill/SKILL.md"

# Mock git submodule command so update --init does not fail in sandbox
cat > "$TMP/bin/git" <<'FAKE_GIT'
#!/usr/bin/env bash
if [[ "$*" == *"submodule"* ]]; then
    exit 0
fi
exec /usr/bin/git "$@"
FAKE_GIT
chmod +x "$TMP/bin/git"

RUN() {
    PATH="$TMP/bin:$PATH" DOTFILES_DIR="$TMP/dotfiles" bash "$TMP/dotfiles/_scripts/skills-vendor.sh" "$@"
}

# Test 1: list when nothing attached
output="$(RUN list)"
echo "$output" | grep -q "native-skill" || fail "expected native-skill in list output"
echo "$output" | grep -q "none active" || fail "expected none active in list output"

# Test 2: attach vendor matt
RUN attach matt >/dev/null

[[ -L "$TMP/dotfiles/agents/.agents/skills/skill-one" ]] || fail "expected skill-one to be symlinked"
[[ -d "$TMP/dotfiles/agents/.agents/skills/native-skill" ]] || fail "native-skill must remain a directory"
[[ ! -L "$TMP/dotfiles/agents/.agents/skills/native-skill" ]] || fail "native-skill must not be overwritten by symlink"
[[ -L "$TMP/dotfiles/agents/.agents/skills/common-skill" ]] || fail "expected common-skill to be symlinked"

# Test 3: attach vendor mattpocock (tests collision resolution)
RUN attach mattpocock >/dev/null

[[ -L "$TMP/dotfiles/agents/.agents/skills/skill-two" ]] || fail "expected skill-two to be symlinked"
[[ -L "$TMP/dotfiles/agents/.agents/skills/common-skill" ]] || fail "expected common-skill from first vendor"
[[ -L "$TMP/dotfiles/agents/.agents/skills/mattpocock-common-skill" ]] || fail "expected colliding common-skill to be prefixed as mattpocock-common-skill"

# Test 4: detach single vendor with prefix match boundary safety (matt vs mattpocock)
RUN detach matt >/dev/null

[[ ! -e "$TMP/dotfiles/agents/.agents/skills/skill-one" ]] || fail "skill-one should be detached"
[[ -L "$TMP/dotfiles/agents/.agents/skills/skill-two" ]] || fail "skill-two from mattpocock should NOT be detached when detaching matt"
[[ -L "$TMP/dotfiles/agents/.agents/skills/mattpocock-common-skill" ]] || fail "mattpocock-common-skill should remain after detaching matt"

# Test 5: detach all
RUN detach >/dev/null

[[ ! -e "$TMP/dotfiles/agents/.agents/skills/skill-two" ]] || fail "skill-two should be detached"
[[ ! -e "$TMP/dotfiles/agents/.agents/skills/mattpocock-common-skill" ]] || fail "mattpocock-common-skill should be detached"
[[ -d "$TMP/dotfiles/agents/.agents/skills/native-skill" ]] || fail "native-skill should still exist"

echo "PASS skills-vendor tests"

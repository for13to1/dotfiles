#!/usr/bin/env bash
# test-eco.sh — behavior tests for the eco CLI lifecycle
# Usage: bash _tests/test-eco.sh

set -euo pipefail
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/eco-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# ── eco.conf validation ─────────────────────────────────────────
# The real eco.conf must load and validate cleanly.
# shellcheck disable=SC1091
source "$ROOT/_scripts/cli-lifecycle.sh"
eco_conf_load || fail "the real eco.conf must load and validate"
(( ${#ECO_CONF_BINS[@]} >= 14 )) || fail "eco.conf must have at least 14 rows"

# A fixture with a bad channel must fail validation.
BAD_CONF="$TMP/bad-channel.conf"
cat > "$BAD_CONF" <<'EOF'
node y biome @biomejs/biome
bad-channel y foo foo-pkg
EOF
if ECO_CONF="$BAD_CONF" bash -c 'source "$1"; eco_conf_load' _ "$ROOT/_scripts/cli-lifecycle.sh" 2>/dev/null; then
    fail "an unknown channel must fail eco.conf validation"
fi

# A duplicate bin must fail.
BAD_CONF="$TMP/dup-bin.conf"
cat > "$BAD_CONF" <<'EOF'
node y biome @biomejs/biome
node y biome other-pkg
EOF
if ECO_CONF="$BAD_CONF" bash -c 'source "$1"; eco_conf_load' _ "$ROOT/_scripts/cli-lifecycle.sh" 2>/dev/null; then
    fail "a duplicate bin must fail eco.conf validation"
fi

# A duplicate pkg must fail.
BAD_CONF="$TMP/dup-pkg.conf"
cat > "$BAD_CONF" <<'EOF'
node y biome @biomejs/biome
node y other @biomejs/biome
EOF
if ECO_CONF="$BAD_CONF" bash -c 'source "$1"; eco_conf_load' _ "$ROOT/_scripts/cli-lifecycle.sh" 2>/dev/null; then
    fail "a duplicate pkg must fail eco.conf validation"
fi

# A flag with a space must fail.
BAD_CONF="$TMP/space-flag.conf"
cat > "$BAD_CONF" <<'EOF'
node y wrangler wrangler "--allow-scripts=esbuild workerd"
EOF
if ECO_CONF="$BAD_CONF" bash -c 'source "$1"; eco_conf_load' _ "$ROOT/_scripts/cli-lifecycle.sh" 2>/dev/null; then
    fail "a flag containing spaces must fail eco.conf validation"
fi

# A bad default (not y/n) must fail.
BAD_CONF="$TMP/bad-default.conf"
cat > "$BAD_CONF" <<'EOF'
node x biome @biomejs/biome
EOF
if ECO_CONF="$BAD_CONF" bash -c 'source "$1"; eco_conf_load' _ "$ROOT/_scripts/cli-lifecycle.sh" 2>/dev/null; then
    fail "a default other than y/n must fail eco.conf validation"
fi

# ── eco.sh syntax ───────────────────────────────────────────────
ECO="$ROOT/_install/eco.sh"

# Missing channel and verb → exit 2.
if bash "$ECO" >/dev/null 2>&1; then
    fail "eco with no args must fail"
fi
if bash "$ECO" node >/dev/null 2>&1; then
    fail "eco with only a channel must fail"
fi

# Unknown channel → exit 2.
if bash "$ECO" bad-ch list >/dev/null 2>&1; then
    fail "an unknown channel must fail"
fi

# Unknown verb → exit 2.
if bash "$ECO" node bad-verb >/dev/null 2>&1; then
    fail "an unknown verb must fail"
fi

# uninstall without pkgs → exit 2.
if bash "$ECO" node uninstall >/dev/null 2>&1; then
    fail "uninstall without packages must fail"
fi

# Option-like arg → exit 2.
if bash "$ECO" node install --bogus >/dev/null 2>&1; then
    fail "an option-like arg must fail"
fi

# list with args → exit 2.
if bash "$ECO" node list biome >/dev/null 2>&1; then
    fail "list with arguments must fail"
fi

# --help succeeds.
bash "$ECO" --help >/dev/null || fail "eco --help must succeed"
bash "$ECO" node --help >/dev/null || fail "eco node --help must succeed"

# ── npm channel (mock fnm) ──────────────────────────────────────
NPM_HOME="$TMP/npm-home"
NPM_BIN="$TMP/npm-bin"
FNM_PREFIX="$TMP/fnm-prefix"
mkdir -p "$NPM_HOME/.local/bin" "$NPM_BIN" "$FNM_PREFIX/bin"
export FNM_LOG="$TMP/fnm.log"
export FNM_PREFIX

cat > "$NPM_BIN/fnm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FNM_LOG"
if [[ "$*" == *'node --version'* ]]; then
    printf '%s\n' 'v24.0.0'
elif [[ "$*" == *'npm --version'* ]]; then
    printf '%s\n' '11.9.0'
elif [[ "$*" == *'npm install --help'* ]]; then
    if [[ "${MOCK_ALLOW_SCRIPTS:-1}" == "1" ]]; then
        printf '%s\n' '    [--allow-scripts <package-list>]'
    fi
elif [[ "$*" == *'npm prefix -g'* ]]; then
    printf '%s\n' "$FNM_PREFIX"
elif [[ "$*" == *'npm outdated'* ]]; then
    if [[ -n "${MOCK_OUTDATED_JSON:-}" ]]; then
        printf '%s' "$MOCK_OUTDATED_JSON"
    else
        printf '{}'
    fi
    exit "${MOCK_OUTDATED_EXIT:-0}"
elif [[ "$*" == *'npm ls'* ]]; then
    if [[ -n "${MOCK_LS_JSON:-}" ]]; then
        printf '%s' "$MOCK_LS_JSON"
    else
        printf '{}'
    fi
elif [[ "$*" == *'node -e'* ]]; then
    if [[ -n "${MOCK_HOST_NODE:-}" ]]; then
        # fnm exec: --using lts-latest -- node -e <script> <args...>
        # argv: $6=script $7=arg1 $8=arg2 $9=arg3
        "$MOCK_HOST_NODE" "$6" "$7" "$8" "$9" 2>/dev/null || "$MOCK_HOST_NODE" "$6" "$7" "$8" 2>/dev/null || true
    else
        printf '%s' "${MOCK_OUTDATED_LINES:-}"
    fi
fi
EOF
chmod +x "$NPM_BIN/fnm"
if MOCK_HOST_NODE="$(command -v node)"; then
    export MOCK_HOST_NODE
fi

# Manifest mode (non-interactive): y-rows install, n-rows skip.
# Seat the y-rows so they're detected as installed.
touch "$NPM_HOME/.local/bin/biome" "$NPM_HOME/.local/bin/stylua"
chmod +x "$NPM_HOME/.local/bin/biome" "$NPM_HOME/.local/bin/stylua"
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --install-manifest >"$TMP/npm-manifest.out" 2>&1 \
    || fail "npm manifest install must not fail"
# n-rows (pi, codex, etc.) must not install in non-interactive mode.
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "non-interactive manifest must not install n-rows"

# Pre-approved n-row installs even in non-interactive mode.
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=codex \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --install-manifest >/dev/null 2>&1 \
    || fail "a pre-approved manifest install must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "a pre-approved n-row must install in non-interactive mode"
grep -q '@openai/codex' "$FNM_LOG" \
    || fail "the pre-approved row must install its own package"

# Seat all conf bins to prevent manifest installs from triggering in later tests.
# shellcheck disable=SC1091
source "$ROOT/_install/install-by-npm.sh"
for bin in "${ECO_CONF_BINS[@]}"; do
    touch "$NPM_HOME/.local/bin/$bin" 2>/dev/null || true
    chmod +x "$NPM_HOME/.local/bin/$bin" 2>/dev/null || true
done

# --install-one: dumb exec, no confirm, carries flag.
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --install-one wrangler wrangler "--allow-scripts=esbuild,workerd" \
    >/dev/null 2>&1 || fail "--install-one must not fail"
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=esbuild,workerd wrangler$' "$FNM_LOG" \
    || fail "--install-one must carry the flag"

# --install-one with a missing runtime skips cleanly (exit 0).
FNM_PREFIX="" HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --install-one foo foo-pkg >/dev/null 2>&1 \
    || fail "a missing runtime must skip --install-one cleanly"

# --update-one: upgrades with @latest.
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --update-one wrangler wrangler "--allow-scripts=esbuild,workerd" \
    >/dev/null 2>&1 || fail "--update-one must not fail"
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=esbuild,workerd wrangler@latest' "$FNM_LOG" \
    || fail "--update-one must upgrade with @latest and carry the flag"

# --uninstall-one: removes via npm.
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --uninstall-one wrangler wrangler "" \
    >/dev/null 2>&1 || fail "--uninstall-one must not fail"
grep -qE -- 'npm uninstall -g --prefix [^ ]+ wrangler$' "$FNM_LOG" \
    || fail "--uninstall-one must uninstall the package"

# --outdated: machine rows, query failure → rc 1.
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --outdated >"$TMP/npm-outdated.out" 2>/dev/null \
    || fail "--outdated must not fail for a healthy query"
grep -q 'wrangler 3.0.0 4.0.0' "$TMP/npm-outdated.out" \
    || fail "--outdated must emit pkg cur latest rows"

if HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_OUTDATED_JSON='{"error":{"code":"ENETUNREACH"}}' MOCK_OUTDATED_EXIT=254 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --outdated >/dev/null 2>&1; then
    fail "a failed outdated query must propagate as failure"
fi

# --list: installed + latest merged; query failure → latest = ?.
MOCK_LS='{"dependencies":{"@biomejs/biome":{"version":"1.9.4"},"wrangler":{"version":"3.0.0"}}}'
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_JSON="$MOCK_LS" \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --list >"$TMP/npm-list.out" 2>/dev/null \
    || fail "--list must not fail"
grep -q '@biomejs/biome 1.9.4 1.9.4' "$TMP/npm-list.out" \
    || fail "--list must show an up-to-date package"
grep -q 'wrangler 3.0.0 4.0.0' "$TMP/npm-list.out" \
    || fail "--list must show an outdated package"

# --list with a failed outdated query → latest = ?.
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_JSON="$MOCK_LS" \
    MOCK_OUTDATED_JSON='{"error":{"code":"ENETUNREACH"}}' MOCK_OUTDATED_EXIT=254 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --list >"$TMP/npm-list-qfail.out" 2>/dev/null \
    || fail "--list must exit 0 even when the outdated query fails"
grep -q '@biomejs/biome 1.9.4 ?' "$TMP/npm-list-qfail.out" \
    || fail "--list must degrade latest to ? on query failure"

# --allow-scripts quirk: old npm drops the flag loudly.
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 MOCK_ALLOW_SCRIPTS=0 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --install-one opencode opencode-ai "--allow-scripts=opencode-ai" \
    >"$TMP/npm-quirk.out" 2>&1 || fail "installing without --allow-scripts support must not fail"
grep -q 'does not support --allow-scripts' "$TMP/npm-quirk.out" \
    || fail "a dropped --allow-scripts must be reported"
grep -qE -- 'npm install -g --prefix [^ ]+ opencode-ai$' "$FNM_LOG" \
    || fail "the package must still install without the flag"
! grep -q -- '--allow-scripts' "$FNM_LOG" \
    || fail "the unsupported flag must actually be dropped"

# Canonical detection: an fnm PATH install must not satisfy the ~/.local check.
cat > "$NPM_BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$NPM_BIN/codex"
ln -sf "$TMP/missing-codex" "$NPM_HOME/.local/bin/codex"
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --install-manifest >"$TMP/npm-migration.out" 2>&1
grep -q 'removed stale install entry' "$TMP/npm-migration.out" \
    || fail "the npm migration must clean stale canonical entries"
[[ ! -L "$NPM_HOME/.local/bin/codex" ]] \
    || fail "the stale canonical codex entry must be removed"
rm -f "$NPM_BIN/codex"

# ── uv channel (mock uv) ────────────────────────────────────────
UV_HOME="$TMP/uv-home"
MOCK_UV="$TMP/mock-uv"
mkdir -p "$UV_HOME" "$MOCK_UV"
export UV_LOG="$TMP/uv.log"

cat > "$MOCK_UV/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UV_LOG"
if [[ "$1 $2" == "tool list" && "$*" == *--outdated* ]]; then
    if [[ -n "${MOCK_UV_OUTDATED:-}" ]]; then
        printf '%s\n' "$MOCK_UV_OUTDATED"
    fi
    exit "${MOCK_UV_OUTDATED_EXIT:-0}"
elif [[ "$1 $2" == "tool list" ]]; then
    if [[ -n "${MOCK_UV_LIST:-}" ]]; then
        printf '%s\n' "$MOCK_UV_LIST"
    fi
fi
EOF
chmod +x "$MOCK_UV/uv"

# Missing uv → clean skip.
NOUV_BIN="$TMP/nouv-bin"
mkdir -p "$NOUV_BIN"
for cmd in env dirname bash; do
    ln -sf "$(command -v "$cmd")" "$NOUV_BIN/$cmd"
done
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NOUV_BIN:/nonexistent" \
    bash "$ROOT/_install/install-by-uv.sh" --install-manifest >"$TMP/uv-missing.out" 2>&1 \
    || fail "missing uv must skip cleanly"
grep -q 'skipping Python CLI lifecycle' "$TMP/uv-missing.out" \
    || fail "missing uv must warn and skip"

# Manifest install: non-interactive installs y-rows.
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --install-manifest >"$TMP/uv-manifest.out" 2>&1 \
    || fail "uv manifest install must not fail"
grep -q 'tool install ruff' "$UV_LOG" \
    || fail "ruff should install via uv tool"
grep -q 'tool install yt-dlp' "$UV_LOG" \
    || fail "yt-dlp should install via uv tool"
[[ "$(grep -c 'tool install ' "$UV_LOG" || true)" == 2 ]] \
    || fail "exactly ruff and yt-dlp should be installed"

# PATH detection: a tool already on PATH must not be reinstalled.
mkdir -p "$TMP/uv-elsewhere"
touch "$TMP/uv-elsewhere/ruff" "$TMP/uv-elsewhere/yt-dlp"
chmod +x "$TMP/uv-elsewhere/ruff" "$TMP/uv-elsewhere/yt-dlp"
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$TMP/uv-elsewhere:$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --install-manifest >"$TMP/uv-path.out" 2>&1
[[ ! -s "$UV_LOG" ]] \
    || fail "a uv CLI already on PATH must not be reinstalled"

# --update-one: goes through uv tool upgrade.
mkdir -p "$UV_HOME/.local/bin"
touch "$UV_HOME/.local/bin/ruff" "$UV_HOME/.local/bin/yt-dlp"
chmod +x "$UV_HOME/.local/bin/ruff" "$UV_HOME/.local/bin/yt-dlp"
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --update-one ruff ruff "" >/dev/null 2>&1 \
    || fail "--update-one must not fail"
grep -q '^tool upgrade ruff$' "$UV_LOG" \
    || fail "the ruff upgrade must go through uv tool upgrade"

# --uninstall-one: goes through uv tool uninstall.
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --uninstall-one ruff ruff "" >/dev/null 2>&1 \
    || fail "--uninstall-one must not fail"
grep -q '^tool uninstall ruff$' "$UV_LOG" \
    || fail "the ruff removal must go through uv tool uninstall"

# --uninstall-one is a dumb exec: it always calls the uninstaller.
# The "PATH-only is not a candidate" guard lives in eco.sh's confirmation
# flow and in go's prefix check — uv's native uninstall handles missing
# tools by failing, which is honest.
: > "$UV_LOG"
rm -f "$UV_HOME/.local/bin/yt-dlp"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$TMP/uv-elsewhere:$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --uninstall-one yt-dlp yt-dlp "" >/dev/null 2>&1 \
    || fail "a uv uninstall-one must not fail"
grep -q '^tool uninstall yt-dlp$' "$UV_LOG" \
    || fail "uninstall-one must dispatch to uv tool uninstall"
[[ -x "$TMP/uv-elsewhere/yt-dlp" ]] \
    || fail "a PATH-only yt-dlp must stay untouched"
touch "$UV_HOME/.local/bin/yt-dlp"
chmod +x "$UV_HOME/.local/bin/yt-dlp"

# Drift guard: unparseable outdated format → failure.
if HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_UV_OUTDATED='ruff v0.16.5 [latest: 0.17.0' MOCK_UV_OUTDATED_EXIT=0 \
    PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --outdated >/dev/null 2>&1; then
    fail "an unparseable uv outdated format must fail"
fi

# Field-shifted drift → failure.
if HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_UV_OUTDATED='ruff python [latest: 0.17.0] v0.16.5' MOCK_UV_OUTDATED_EXIT=0 \
    PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --outdated >/dev/null 2>&1; then
    fail "a field-shifted uv format must fail"
fi

# Marker-gone drift → failure.
if HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_UV_OUTDATED='ruff v0.16.5 -> 0.17.0
- ruff' MOCK_UV_OUTDATED_EXIT=0 \
    PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --outdated >/dev/null 2>&1; then
    fail "a marker-less uv format must fail"
fi

# ── go channel (mock go) ────────────────────────────────────────
GO_HOME="$TMP/go-home"
MOCK_GO="$TMP/mock-go"
mkdir -p "$GO_HOME" "$MOCK_GO"
export GO_LOG="$TMP/go.log" GO_WRITE_LOG="$TMP/go-write.log"
: > "$GO_LOG"
: > "$GO_WRITE_LOG"
unset GOBIN GOMODCACHE

cat > "$MOCK_GO/go" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == install ]]; then
    printf 'GOBIN=%s tool=%s\n' "${GOBIN:-<unset>}" "$2" >> "$GO_LOG"
elif [[ "$1" == env && "$2" == -w ]]; then
    shift 2
    printf '%s\n' "$@" >> "$GO_WRITE_LOG"
elif [[ "$1" == env && "$2" == GOENV ]]; then
    printf '%s\n' "${GO_ENV_FILE:-}"
elif [[ "$1" == version && "$2" == -m ]]; then
    name="$(basename "$3")"
    eval "pkg=\${MOCK_GO_PKG_$name:-}; cur=\${MOCK_GO_CUR_$name:-}"
    if [[ -n "$pkg" ]]; then
        eval "path=\${MOCK_GO_PATH_$name:-\$pkg}"
        printf 'path\t%s\n' "$path"
        printf 'mod\t%s\t%s\n' "$pkg" "$cur"
    else
        exit 1
    fi
elif [[ "$1" == list && "$2" == -m ]]; then
    if [[ -n "${MOCK_GO_LIST_FAIL:-}" ]]; then
        printf '%s\n' 'proxy unreachable' >&2
        exit "${MOCK_GO_LIST_FAIL}"
    fi
    printf 'list %s\n' "$*" >> "$GO_LOG"
    shift 4
    for spec in "$@"; do
        pkg="${spec%@latest}"
        key="${pkg//[^a-zA-Z0-9]/_}"
        eval "lat=\${MOCK_GO_LAT_$key:-}"
        printf '%s %s\n' "$pkg" "$lat"
    done
fi
EOF
chmod +x "$MOCK_GO/go"

# Missing go → clean skip.
NOGO_BIN="$TMP/nogo-bin"
mkdir -p "$NOGO_BIN"
for cmd in env dirname bash; do
    ln -sf "$(command -v "$cmd")" "$NOGO_BIN/$cmd"
done
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NOGO_BIN:/nonexistent" \
    bash "$ROOT/_install/install-by-go.sh" --install-manifest >"$TMP/go-missing.out" 2>&1 \
    || fail "missing go must skip cleanly"
grep -q 'skipping Go CLI lifecycle' "$TMP/go-missing.out" \
    || fail "missing go must warn and skip"

# Manifest install: non-interactive installs y-rows (gopls, gofumpt).
: > "$GO_LOG"
: > "$GO_WRITE_LOG"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --install-manifest >"$TMP/go-manifest.out" 2>&1 \
    || fail "go manifest install must not fail"
grep -q 'tool=golang.org/x/tools/gopls@latest' "$GO_LOG" \
    || fail "gopls should install into ~/.local/bin via go install"
grep -q 'tool=mvdan.cc/gofumpt@latest' "$GO_LOG" \
    || fail "gofumpt should install into ~/.local/bin via go install"
grep -q '^GOBIN=.*\.local/bin$' "$GO_WRITE_LOG" \
    || fail "the layout write must persist GOBIN"
grep -q '^GOMODCACHE=.*\.cache/go-mod$' "$GO_WRITE_LOG" \
    || fail "the layout write must persist GOMODCACHE"
! grep -q '^GOPATH=' "$GO_WRITE_LOG" \
    || fail "GOPATH must be left untouched"

# Layout warnings: persisted and exported values are reported.
printf 'GOMODCACHE=%s\n' "$TMP/old-mod" > "$TMP/goenv"
: > "$GO_LOG"
HOME="$GO_HOME" PATH="$MOCK_GO:/usr/bin:/bin" GO_LOG="$GO_LOG" \
    GO_ENV_FILE="$TMP/goenv" \
    bash "$ROOT/_install/install-by-go.sh" --install-manifest >"$TMP/go-file.out" 2>&1 \
    || fail "a value persisted in GOENV must not fail the channel"
grep -q "GOMODCACHE=$TMP/old-mod in $TMP/goenv; replacing it with" "$TMP/go-file.out" \
    || fail "a value persisted in GOENV must be reported before being replaced"

# Idempotent: already-seated CLIs are skipped.
mkdir -p "$GO_HOME/.local/bin"
touch "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
chmod +x "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
: > "$GO_LOG"
HOME="$GO_HOME" PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --install-manifest >"$TMP/go-idempotent.out" 2>&1
[[ ! -s "$GO_LOG" ]] \
    || fail "existing gopls/gofumpt must not be reinstalled"

# PATH detection: a tool already on PATH must not be reinstalled.
rm -f "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
mkdir -p "$TMP/elsewhere"
touch "$TMP/elsewhere/gopls" "$TMP/elsewhere/gofumpt"
chmod +x "$TMP/elsewhere/gopls" "$TMP/elsewhere/gofumpt"
: > "$GO_LOG"
HOME="$GO_HOME" PATH="$TMP/elsewhere:$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --install-manifest >"$TMP/go-path.out" 2>&1
[[ ! -s "$GO_LOG" ]] \
    || fail "a CLI already on PATH must not be reinstalled into ~/.local/bin"

# --update-one: reinstalls at @latest.
mkdir -p "$GO_HOME/.local/bin"
touch "$GO_HOME/.local/bin/gopls"
chmod +x "$GO_HOME/.local/bin/gopls"
: > "$GO_LOG"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --update-one gopls golang.org/x/tools/gopls "" \
    >/dev/null 2>&1 || fail "--update-one must not fail"
grep -q 'tool=golang.org/x/tools/gopls@latest' "$GO_LOG" \
    || fail "the gopls upgrade must reinstall its own module at @latest"

# --outdated: domain-wide scan with embedded metadata.
mkdir -p "$GO_HOME/.local/bin"
touch "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
chmod +x "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
: > "$GO_LOG"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
    MOCK_GO_LAT_golang_org_x_tools_gopls=v0.19.0 \
    MOCK_GO_PKG_gofumpt=mvdan.cc/gofumpt MOCK_GO_CUR_gofumpt=v0.8.0 \
    MOCK_GO_LAT_mvdan_cc_gofumpt=v0.8.0 \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --outdated >"$TMP/go-outdated.out" 2>/dev/null \
    || fail "--outdated must not fail"
grep -q 'golang.org/x/tools/gopls v0.18.0 v0.19.0' "$TMP/go-outdated.out" \
    || fail "--outdated must emit the outdated gopls row"
! grep -q 'gofumpt' "$TMP/go-outdated.out" \
    || fail "an up-to-date go tool must not appear in --outdated"

# A failed module-proxy query is an error.
: > "$GO_LOG"
if HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
    MOCK_GO_LIST_FAIL=1 \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --outdated >/dev/null 2>&1; then
    fail "a failed go list -m must propagate as failure"
fi

# --uninstall-one: removes the binary via rm.
mkdir -p "$GO_HOME/.local/bin"
touch "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
chmod +x "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --uninstall-one gopls golang.org/x/tools/gopls "" \
    >/dev/null 2>&1 || fail "--uninstall-one must not fail"
[[ ! -e "$GO_HOME/.local/bin/gopls" ]] \
    || fail "the gopls binary must be removed"
[[ -x "$GO_HOME/.local/bin/gofumpt" ]] \
    || fail "an unnamed go tool must stay"

# P0 regression: a PATH-only go binary is not in the canonical prefix —
# the guard must skip the rm (which would silently "succeed" and lie).
rm -f "$GO_HOME/.local/bin/gofumpt"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$TMP/elsewhere:$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --uninstall-one gofumpt mvdan.cc/gofumpt "" \
    >"$TMP/go-p0.out" 2>&1 || fail "a PATH-only go uninstall must not fail"
grep -q 'not found in' "$TMP/go-p0.out" \
    || fail "a PATH-only go binary must be reported as not in the prefix"
[[ -x "$TMP/elsewhere/gofumpt" ]] \
    || fail "a PATH-only gofumpt must stay untouched"

# ── cargo channel (mock cargo) ──────────────────────────────────
CARGO_HOME="$TMP/cargo-home"
MOCK_CARGO="$TMP/mock-cargo"
mkdir -p "$CARGO_HOME" "$MOCK_CARGO"
export CARGO_LOG="$TMP/cargo.log"

cat > "$MOCK_CARGO/cargo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CARGO_LOG"
if [[ "$1 $2" == "install --list" ]]; then
    if [[ -n "${MOCK_CARGO_LIST:-}" ]]; then
        printf '%s\n' "$MOCK_CARGO_LIST"
    fi
elif [[ "$1" == search ]]; then
    crate="$2"
    key="${crate//[^a-zA-Z0-9]/_}"
    eval "lat=\${MOCK_CARGO_LAT_$key:-}"
    if [[ -n "$lat" ]]; then
        printf '%s = "%s"  # description\n' "$crate" "$lat"
    else
        exit 1
    fi
fi
EOF
chmod +x "$MOCK_CARGO/cargo"

# Missing cargo → clean skip.
NOCARGO_BIN="$TMP/nocargo-bin"
mkdir -p "$NOCARGO_BIN"
for cmd in env dirname bash; do
    ln -sf "$(command -v "$cmd")" "$NOCARGO_BIN/$cmd"
done
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NOCARGO_BIN:/nonexistent" \
    bash "$ROOT/_install/install-by-cargo.sh" --install-manifest >"$TMP/cargo-missing.out" 2>&1 \
    || fail "missing cargo must skip cleanly"
grep -q 'skipping Rust CLI lifecycle' "$TMP/cargo-missing.out" \
    || fail "missing cargo must warn and skip"

# Manifest install: rust channel has no conf rows → nothing to do.
: > "$CARGO_LOG"
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --install-manifest >"$TMP/cargo-manifest.out" 2>&1 \
    || fail "cargo manifest install must not fail"
grep -q 'no missing rust CLIs selected' "$TMP/cargo-manifest.out" \
    || fail "an empty rust manifest must report nothing to install"
[[ ! -s "$CARGO_LOG" ]] \
    || fail "an empty rust manifest must not run any cargo command"

# --install-one: installs with --root ~/.local.
: > "$CARGO_LOG"
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --install-one ripgrep ripgrep "" >/dev/null 2>&1 \
    || fail "cargo --install-one must not fail"
grep -q 'install --root' "$CARGO_LOG" \
    || fail "cargo install must use --root"
grep -q 'ripgrep' "$CARGO_LOG" \
    || fail "cargo install must name the crate"

# --update-one: --force with --root.
: > "$CARGO_LOG"
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --update-one ripgrep ripgrep "" >/dev/null 2>&1 \
    || fail "cargo --update-one must not fail"
grep -q 'install --force --root' "$CARGO_LOG" \
    || fail "cargo update must use --force --root"

# --uninstall-one: cargo uninstall --root.
: > "$CARGO_LOG"
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --uninstall-one ripgrep ripgrep "" >/dev/null 2>&1 \
    || fail "cargo --uninstall-one must not fail"
grep -q 'uninstall --root' "$CARGO_LOG" \
    || fail "cargo uninstall must use --root"

# --outdated: installed crates × cargo search.
: > "$CARGO_LOG"
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_CARGO_LIST='ripgrep v14.1.0:
    rg' \
    MOCK_CARGO_LAT_ripgrep=14.1.1 \
    PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --outdated >"$TMP/cargo-outdated.out" 2>/dev/null \
    || fail "cargo --outdated must not fail"
grep -q 'ripgrep 14.1.0 14.1.1' "$TMP/cargo-outdated.out" \
    || fail "cargo --outdated must emit the outdated crate"

# --outdated: a failed search is an error.
: > "$CARGO_LOG"
if HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_CARGO_LIST='ripgrep v14.1.0:
    rg' \
    PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --outdated >/dev/null 2>&1; then
    fail "a failed cargo search must propagate as failure"
fi

# --list: installed crates with latest (or ? on search failure).
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_CARGO_LIST='ripgrep v14.1.0:
    rg' \
    MOCK_CARGO_LAT_ripgrep=14.1.1 \
    PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --list >"$TMP/cargo-list.out" 2>/dev/null \
    || fail "cargo --list must not fail"
grep -q 'ripgrep 14.1.0 14.1.1' "$TMP/cargo-list.out" \
    || fail "cargo --list must show the crate with its latest version"

# ── eco.sh integration ──────────────────────────────────────────
ECO_OUT="$TMP/eco.out"

# Batch confirm: one 'y' on stdin approves all pending targets.
ECO_HOME="$TMP/eco-home"
mkdir -p "$ECO_HOME/.local/bin"
for b in biome stylua wrangler; do
    touch "$ECO_HOME/.local/bin/$b"
    chmod +x "$ECO_HOME/.local/bin/$b"
done
: > "$FNM_LOG"
printf 'y\n' | HOME="$ECO_HOME" \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update >"$ECO_OUT" 2>&1 \
    || fail "an approved eco update must not fail"
grep -q 'update available: wrangler' "$ECO_OUT" \
    || fail "eco update must list the outdated row"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "an approved eco update must run exactly one upgrade"
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=esbuild,workerd wrangler@latest' "$FNM_LOG" \
    || fail "the eco update must carry wrangler's flag"

# Non-interactive without pre-approval: nothing upgrades.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update >"$ECO_OUT" 2>&1 \
    || fail "a declined eco update must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "without pre-approval a non-interactive eco update must install nothing"
grep -q 'no npm CLIs approved' "$ECO_OUT" \
    || fail "a fully declined eco update must say so"

# Pre-approved update skips the question.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=wrangler \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update >"$ECO_OUT" 2>&1 \
    || fail "a pre-approved eco update must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "a pre-approved eco update must upgrade"

# Named update: direct upgrade, no outdated query.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=wrangler \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update wrangler >"$ECO_OUT" 2>&1 \
    || fail "a named eco update must not fail"
! grep -q 'npm outdated' "$FNM_LOG" \
    || fail "a named eco update must skip the outdated query"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "a named eco update must run exactly one upgrade"

# Named install with a raw pkg (not in conf).
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=cowsay \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node install cowsay >"$ECO_OUT" 2>&1 \
    || fail "a raw-pkg eco install must not fail"
grep -qE -- 'npm install -g --prefix [^ ]+ cowsay$' "$FNM_LOG" \
    || fail "a raw pkg must install by its own name"

# Uninstall with conf bin resolution.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=wrangler \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node uninstall wrangler >"$ECO_OUT" 2>&1 \
    || fail "an eco uninstall must not fail"
grep -qE -- 'npm uninstall -g --prefix [^ ]+ wrangler$' "$FNM_LOG" \
    || fail "the eco uninstall must remove the package"

# eco list: renders a table with conf bin mapping.
MOCK_LS_ECO='{"dependencies":{"@biomejs/biome":{"version":"1.9.4"},"wrangler":{"version":"3.0.0"}}}'
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_JSON="$MOCK_LS_ECO" \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' MOCK_OUTDATED_EXIT=1 \
    MOCK_HOST_NODE="$(command -v node)" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node list >"$ECO_OUT" 2>/dev/null \
    || fail "eco list must not fail"
grep -q 'biome' "$ECO_OUT" \
    || fail "eco list must map @biomejs/biome to its bin name 'biome'"
grep -qE 'wrangler[[:space:]]+3\.0\.0[[:space:]]+4\.0\.0' "$ECO_OUT" \
    || fail "eco list must show wrangler's versions"

# DOTFILES_SKIP_ECOSYSTEM_TOOLS gates manifest install only.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_SKIP_ECOSYSTEM_TOOLS=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node install >"$ECO_OUT" 2>&1 \
    || fail "a skipped manifest install must not fail"
grep -q 'DOTFILES_SKIP_ECOSYSTEM_TOOLS' "$ECO_OUT" \
    || fail "the skip gate must be reported"
[[ ! -s "$FNM_LOG" ]] \
    || fail "a skipped manifest install must not run any npm command"

# DOTFILES_SKIP_ECOSYSTEM_TOOLS does not gate a named install.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_SKIP_ECOSYSTEM_TOOLS=1 \
    DOTFILES_ACCEPT_TOOLS=biome \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node install biome >"$ECO_OUT" 2>&1 \
    || fail "a named install must not be skipped by the gate"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "a named install must run despite the skip gate"

# Failed query propagates.
if HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_OUTDATED_JSON='{"error":{"code":"ENETUNREACH"}}' MOCK_OUTDATED_EXIT=254 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update >/dev/null 2>&1; then
    fail "a failed eco outdated query must propagate as failure"
fi

# Legacy var fallback: DOTFILES_ACCEPT_INSTALLS still pre-approves.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_INSTALLS=wrangler \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update >"$ECO_OUT" 2>&1 \
    || fail "the legacy accept var must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "the legacy accept var must pre-approve"
grep -q 'DOTFILES_ACCEPT_INSTALLS is deprecated' "$ECO_OUT" \
    || fail "the legacy accept var must warn about deprecation"

# ── curl channel (preserved) ────────────────────────────────────
MOCK_CURL_BIN="$TMP/mock-curl-bin"
mkdir -p "$MOCK_CURL_BIN"
cat > "$MOCK_CURL_BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0'
EOF
chmod +x "$MOCK_CURL_BIN/curl"
export CURL_LOG="$TMP/curl.log"
: > "$CURL_LOG"

HOME="$TMP/curl-home" PATH="$MOCK_CURL_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-curl.sh" >/dev/null
[[ "$(wc -l < "$CURL_LOG" | tr -d ' ')" == 3 ]] \
    || fail "default tools should download all three official installers without prompting"
while IFS= read -r args; do
    [[ "$args" == *"--proto =https"* ]] || fail "curl must require HTTPS"
    [[ "$args" == *"--tlsv1.2"* ]] || fail "curl must require TLS 1.2 or newer"
    [[ "$args" == *"--fail"* && "$args" == *"--show-error"* && "$args" == *"--location"* ]] \
        || fail "curl must use hardened failure and redirect handling"
done < "$CURL_LOG"

echo "PASS eco lifecycle tests"

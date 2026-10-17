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
    # A real install changes what `npm ls` reports. The mock writes the post
    # install state to MOCK_LS_FILE so update can observe a real transition.
    if [[ -n "${MOCK_LS_FILE:-}" && -f "$MOCK_LS_FILE" ]]; then
        printf '%s' "$(cat "$MOCK_LS_FILE")"
    elif [[ -n "${MOCK_LS_JSON:-}" ]]; then
        printf '%s' "$MOCK_LS_JSON"
    else
        printf '{}'
    fi
elif [[ "$*" == *'npm install -g'* || "$*" == *'npm uninstall -g'* ]]; then
    # A real mutation changes what `npm ls` reports afterwards.
    if [[ -n "${MOCK_LS_FILE:-}" && -n "${MOCK_LS_AFTER:-}" ]]; then
        printf '%s' "$MOCK_LS_AFTER" > "$MOCK_LS_FILE"
    fi
    exit 0
elif [[ "$*" == *'node -e'* ]]; then
    if [[ -n "${MOCK_HOST_NODE:-}" ]]; then
        # fnm exec: --using lts-latest -- node -e <script> <args...>
        # argv: $6=script $7=arg1 $8=arg2 $9=arg3. The exit status must
        # survive: a script that rejects its input is how npm's error payload
        # is detected, and swallowing it hides a broken latest query.
        "$MOCK_HOST_NODE" "$6" "$7" "$8" "$9"
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

# -y overrides the manifest's y/n column: every missing row installs.
: > "$FNM_LOG"
HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 ECO_ASSUME_YES=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --install-manifest >/dev/null 2>&1 \
    || fail "a -y manifest install must not fail"
grep -q '@openai/codex' "$FNM_LOG" \
    || fail "-y must install n-rows too, not only the y-rows"
# Every n-row is a distinct package, so the count is the n-row count.
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 8 ]] \
    || fail "-y must install all eight n-rows, got $(grep -c 'npm install -g ' "$FNM_LOG" || true)"

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

# --install-one with a missing runtime skips with the dedicated "nothing done"
# code (3), so the caller can tell a skip from a completed install.
rc=0
FNM_PREFIX="" HOME="$NPM_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --install-one foo foo-pkg >/dev/null 2>&1 || rc=$?
[[ "$rc" == 3 ]] \
    || fail "a missing runtime must signal 'nothing done' (exit 3), got $rc"

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
    # Real `go version -m` accepts several files and prefixes each section
    # with "<path>: go1.x". eco passes the whole prefix in one call, so the
    # mock must support the multi-file form too.
    rc=0
    for f in "${@:3}"; do
        name="$(basename "$f")"
        eval "pkg=\${MOCK_GO_PKG_$name:-}; cur=\${MOCK_GO_CUR_$name:-}"
        if [[ -n "$pkg" ]]; then
            eval "path=\${MOCK_GO_PATH_$name:-\$pkg}"
            printf '%s: go1.27.1\n' "$f"
            printf '\tpath\t%s\n' "$path"
            printf '\tmod\t%s\t%s\n' "$pkg" "$cur"
        else
            rc=1
        fi
    done
    exit "$rc"
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

# A failed `go env -w` is best effort, not fatal: the tools must still install
# into ~/.local/bin. A fresh HOME: earlier cases seat gopls/gofumpt, and manifest install is
# idempotent, so a shared HOME would skip the installs under test.
GOLAYOUT_HOME="$TMP/go-layout-home"
mkdir -p "$GOLAYOUT_HOME"
BAD_GO_BIN="$TMP/bad-go-bin"
mkdir -p "$BAD_GO_BIN"
cat > "$BAD_GO_BIN/go" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == env && "$2" == -w ]]; then
    printf '%s\n' 'go env is disabled' >&2
    exit 1
fi
if [[ "$1" == install ]]; then
    printf 'GOBIN=%s tool=%s\n' "${GOBIN:-<unset>}" "$2" >> "$GO_LOG"
fi
if [[ "$1" == env && "$2" == GOENV ]]; then
    printf '%s\n' "${GO_ENV_FILE:-}"
fi
EOF
chmod +x "$BAD_GO_BIN/go"
: > "$GO_LOG"
HOME="$GOLAYOUT_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$BAD_GO_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --install-manifest >"$TMP/go-bad.out" 2>&1 \
    || fail "a failed go env -w must not fail the Go channel"
grep -q 'go env -w failed' "$TMP/go-bad.out" \
    || fail "a failed go env -w must be reported"
[[ "$(grep -c 'tool=' "$GO_LOG" || true)" == 2 ]] \
    || fail "tools must still install after a failed go env -w"

# An exported Go value is reported as winning over GOENV.
rm -rf "$GOLAYOUT_HOME/.local"
: > "$GO_LOG"
HOME="$GOLAYOUT_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_GO:/usr/bin:/bin" \
    GOMODCACHE="$TMP/exported-mod" \
    bash "$ROOT/_install/install-by-go.sh" --install-manifest >"$TMP/go-export.out" 2>&1 \
    || fail "an exported Go value must not fail the channel"
grep -q "GOMODCACHE=$TMP/exported-mod is exported in this shell" "$TMP/go-export.out" \
    || fail "an exported Go value must be reported as winning over GOENV"

# Go's built-in defaults must never be reported as user config.
rm -rf "$GOLAYOUT_HOME/.local"
: > "$GO_LOG"
HOME="$GOLAYOUT_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --install-manifest >"$TMP/go-defaults.out" 2>&1 \
    || fail "a clean Go environment must not fail"
! grep -qE 'replacing it with|is exported in this shell' "$TMP/go-defaults.out" \
    || fail "Go's built-in defaults must not be reported as user config"

# A failed module-proxy query is an error.
: > "$GO_LOG"
if HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
    MOCK_GO_LIST_FAIL=1 \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --outdated >/dev/null 2>&1; then
    fail "a failed go list -m must propagate as failure"
fi

# --uninstall-one: removes the binary via rm. The fixture must carry Go module
# metadata: the removal path refuses to delete a file that is not a Go binary
# (CLI_BIN_DIR is shared with npm/uv, so a blind rm would delete their tool).
mkdir -p "$GO_HOME/.local/bin"
touch "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
chmod +x "$GO_HOME/.local/bin/gopls" "$GO_HOME/.local/bin/gofumpt"
HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_GO_PKG_gopls=golang.org/x/tools/gopls MOCK_GO_CUR_gopls=v0.18.0 \
    PATH="$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --uninstall-one gopls golang.org/x/tools/gopls "" \
    >/dev/null 2>&1 || fail "--uninstall-one must not fail"
[[ ! -e "$GO_HOME/.local/bin/gopls" ]] \
    || fail "the gopls binary must be removed"
[[ -x "$GO_HOME/.local/bin/gofumpt" ]] \
    || fail "an unnamed go tool must stay"

# A PATH-only go binary is not in the canonical prefix —
# the guard must skip the rm (which would silently "succeed" and lie), and it
# must not report success for work it did not do.
rm -f "$GO_HOME/.local/bin/gofumpt"
if HOME="$GO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$TMP/elsewhere:$MOCK_GO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --uninstall-one gofumpt mvdan.cc/gofumpt "" \
    >"$TMP/go-p0.out" 2>&1; then
    fail "a PATH-only go uninstall must report that nothing was removed"
fi
grep -q 'not managed by eco' "$TMP/go-p0.out" \
    || fail "a PATH-only go binary must be reported as unmanaged, not merely missing"
grep -q "$TMP/elsewhere/gofumpt" "$TMP/go-p0.out" \
    || fail "a PATH-only go uninstall must say where the binary actually lives"
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
# update now runs from the installed snapshot (no network pre-query), so the
# fixture is "what npm ls reports" — and the mock rewrites that snapshot when
# an install runs, which is how a real package manager behaves.
ECO_HOME="$TMP/eco-home"
mkdir -p "$ECO_HOME/.local/bin"
for b in biome stylua wrangler; do
    touch "$ECO_HOME/.local/bin/$b"
    chmod +x "$ECO_HOME/.local/bin/$b"
done
: > "$FNM_LOG"
UPD_LS="$TMP/upd-ls.json"
printf '%s' '{"dependencies":{"wrangler":{"version":"3.0.0"}}}' > "$UPD_LS"
printf 'y\n' | HOME="$ECO_HOME" \
    MOCK_LS_FILE="$UPD_LS" \
    MOCK_LS_AFTER='{"dependencies":{"wrangler":{"version":"4.0.0"}}}' \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update >"$ECO_OUT" 2>&1 \
    || fail "an approved eco update must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "an approved eco update must run exactly one upgrade"
grep -qE -- 'npm install -g --prefix [^ ]+ --allow-scripts=esbuild,workerd wrangler@latest' "$FNM_LOG" \
    || fail "the eco update must carry wrangler's flag"
# The transition is reported from the reads around the action.
grep -qE 'wrangler updated \(3\.0\.0 → 4\.0\.0\)' "$ECO_OUT" \
    || fail "eco update must report the observed version transition"
! grep -q 'npm outdated' "$FNM_LOG" \
    || fail "update must not run an outdated pre-query any more"

# Non-interactive without -y: declines, and says so.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_JSON='{"dependencies":{"wrangler":{"version":"3.0.0"}}}' \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update >"$ECO_OUT" 2>&1 \
    || fail "a declined eco update must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "without -y a non-interactive eco update must install nothing"
grep -q 'nothing was updated' "$ECO_OUT" \
    || fail "a declined eco update must say nothing was done"

# -y update skips the question and reports the transition.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_JSON='{"dependencies":{"wrangler":{"version":"3.0.0"}}}' \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update -y >"$ECO_OUT" 2>&1 \
    || fail "a -y eco update must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "-y must upgrade without asking"

# Named update: direct upgrade, no outdated query.
: > "$FNM_LOG"
UP_LS="$TMP/up-ls.json"
printf '%s' '{"dependencies":{"wrangler":{"version":"3.0.0"}}}' > "$UP_LS"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_FILE="$UP_LS" MOCK_LS_AFTER='{"dependencies":{"wrangler":{"version":"4.0.0"}}}' \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update -y wrangler >"$ECO_OUT" 2>&1 \
    || fail "a named eco update must not fail"
! grep -q 'npm outdated' "$FNM_LOG" \
    || fail "a named eco update must skip the outdated query"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "a named eco update must run exactly one upgrade"
# A target the channel does not report is refused rather than "updated".
: > "$FNM_LOG"
printf '%s' '{"dependencies":{}}' > "$UP_LS"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_FILE="$UP_LS" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update -y wrangler >"$ECO_OUT" 2>&1 \
    || fail "updating an absent package must not fail the run"
! grep -q 'npm install -g ' "$FNM_LOG" \
    || fail "updating an absent package must not run an upgrade"
grep -q 'is not installed via npm; nothing to update' "$ECO_OUT" \
    || fail "updating an absent package must say it is not installed"

# Named install with a raw pkg (not in conf).
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node install -y cowsay >"$ECO_OUT" 2>&1 \
    || fail "a raw-pkg eco install must not fail"
grep -qE -- 'npm install -g --prefix [^ ]+ cowsay$' "$FNM_LOG" \
    || fail "a raw pkg must install by its own name"

# Uninstall with conf bin resolution. Removal asks; this run answers the prompt.
# The fixture must report the bin as installed: eco decides existence from its
# own snapshot, never from a package manager's exit code.
UN_LS="$TMP/un-ls.json"
printf '%s' '{"dependencies":{"wrangler":{"version":"3.0.0"}}}' > "$UN_LS"
: > "$FNM_LOG"
printf 'y\n' | env -u DOTFILES_NON_INTERACTIVE HOME="$ECO_HOME" \
    MOCK_LS_FILE="$UN_LS" MOCK_LS_AFTER='{"dependencies":{}}' \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node uninstall wrangler >"$ECO_OUT" 2>&1 \
    || fail "an approved eco uninstall must not fail"
grep -qE -- 'npm uninstall -g --prefix [^ ]+ wrangler$' "$FNM_LOG" \
    || fail "the eco uninstall must remove the package"
grep -q 'wrangler uninstalled' "$ECO_OUT" \
    || fail "a verified removal must be reported as done"

# A removal that the package manager claims but did not perform is a failure:
# npm exits 0 for a package that is still there.
printf '%s' '{"dependencies":{"wrangler":{"version":"3.0.0"}}}' > "$UN_LS"
: > "$FNM_LOG"
rc=0
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_FILE="$UN_LS" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node uninstall -y wrangler >"$ECO_OUT" 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail "an unverified removal must fail, got $rc"
grep -q 'was not removed' "$ECO_OUT" \
    || fail "an unverified removal must say the bin is still installed"

# A target that is not installed is refused before npm is asked: npm would
# exit 0 and eco would otherwise report a success that never happened.
: > "$FNM_LOG"
rc=0
printf '%s' '{"dependencies":{}}' > "$UN_LS"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_FILE="$UN_LS" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node uninstall -y ghost-pkg >"$ECO_OUT" 2>&1 || rc=$?
[[ "$rc" == 0 ]] || fail "removing an absent package must not fail, got $rc"
# `npm ls` is how the snapshot is read, so the log is not empty; what must be
# absent is the removal call itself.
! grep -q 'npm uninstall' "$FNM_LOG" \
    || fail "an absent package must never reach npm uninstall"
grep -q 'is not installed via npm' "$ECO_OUT" \
    || fail "an absent package must be reported as not installed"

# Removal always asks unless -y is given.
printf '%s' '{"dependencies":{"wrangler":{"version":"3.0.0"}}}' > "$UN_LS"
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_FILE="$UN_LS" MOCK_LS_AFTER='{"dependencies":{}}' \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node uninstall wrangler >"$ECO_OUT" 2>&1 \
    || fail "a declined eco uninstall must not fail"
! grep -q 'npm uninstall' "$FNM_LOG" \
    || fail "a non-interactive uninstall without -y must not remove anything"
grep -q 'nothing was uninstalled' "$ECO_OUT" \
    || fail "a declined uninstall must say nothing was removed"

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

# DOTFILES_SKIP_ECOSYSTEM_TOOLS does not gate a named install. The target must
# not already be seated: a named install is idempotent, so an installed bin is
# reported and skipped before the gate would even matter.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_SKIP_ECOSYSTEM_TOOLS=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node install -y codex >"$ECO_OUT" 2>&1 \
    || fail "a named install must not be skipped by the gate"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "a named install must run despite the skip gate"

# A failed outdated query is still an error at the channel level. `list`
# degrades the latest column to "?" instead of failing (it still has data to
# show), so the failure is pinned where it is actionable: --outdated.
if HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_JSON='{"dependencies":{"wrangler":{"version":"3.0.0"}}}' \
    MOCK_OUTDATED_JSON='{"error":{"code":"ENETUNREACH"}}' MOCK_OUTDATED_EXIT=254 \
    MOCK_HOST_NODE="$(command -v node)" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-npm.sh" --outdated >/dev/null 2>&1; then
    fail "a failed outdated query must propagate as failure"
fi

# The old pre-approval variables are gone: setting them must have no effect.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_INSTALLS=wrangler \
    DOTFILES_ACCEPT_TOOLS=wrangler \
    MOCK_OUTDATED_JSON='{"wrangler":{"current":"3.0.0","latest":"4.0.0"}}' MOCK_OUTDATED_EXIT=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update >"$ECO_OUT" 2>&1 \
    || fail "a removed accept var must not fail the run"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 0 ]] \
    || fail "DOTFILES_ACCEPT_TOOLS must no longer pre-approve anything"

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

# ── cargo channel honesty ───────────────────────────
# A broken cargo (install --list fails) must not read as "nothing installed":
# that used to report "all installed cargo CLIs are up to date" with exit 0.
BROKEN_CARGO="$TMP/broken-cargo"
mkdir -p "$BROKEN_CARGO"
cat > "$BROKEN_CARGO/cargo" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "install --list" ]]; then
    printf '%s\n' 'error: failed to read the crate registry' >&2
    exit 1
fi
exit 0
EOF
chmod +x "$BROKEN_CARGO/cargo"

if HOME="$CARGO_HOME" PATH="$BROKEN_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --list >"$TMP/cargo-broken-list.out" 2>&1; then
    fail "a failed cargo install --list must not report an empty list as success"
fi
grep -q 'cannot list Rust CLIs' "$TMP/cargo-broken-list.out" \
    || fail "a failed cargo listing must be reported"
if HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 PATH="$BROKEN_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --outdated >/dev/null 2>&1; then
    fail "a failed cargo listing must not pass as 'up to date'"
fi

# Machine output: --list/--outdated must keep stdout data-only. Without
# CLI_MACHINE_OUTPUT the channel's own warnings land in the table.
CARGO_NOPATH="$TMP/nocargo-path"
mkdir -p "$CARGO_NOPATH"
for cmd in env dirname bash; do
    ln -sf "$(command -v "$cmd")" "$CARGO_NOPATH/$cmd"
done
HOME="$CARGO_HOME" PATH="$CARGO_NOPATH:/nonexistent" \
    bash "$ROOT/_install/install-by-cargo.sh" --list >"$TMP/cargo-stdout.out" 2>"$TMP/cargo-stderr.out" || true
[[ ! -s "$TMP/cargo-stdout.out" ]] \
    || fail "a cargo --list warning must not pollute stdout"
grep -q 'skipping Rust CLI lifecycle' "$TMP/cargo-stderr.out" \
    || fail "the cargo warning must still reach stderr"
HOME="$CARGO_HOME" PATH="$CARGO_NOPATH:/nonexistent" \
    bash "$ROOT/_install/install-by-cargo.sh" --outdated >"$TMP/cargo-stdout2.out" 2>/dev/null || true
[[ ! -s "$TMP/cargo-stdout2.out" ]] \
    || fail "a cargo --outdated warning must not pollute stdout"

# A pre-release latest is a legal version, not a parse failure.
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_CARGO_LIST='ripgrep v14.1.0:
    rg' \
    MOCK_CARGO_LAT_ripgrep=14.1.1-rc.1 \
    PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-cargo.sh" --outdated >"$TMP/cargo-pre.out" 2>/dev/null \
    || fail "a pre-release cargo version must not fail the outdated query"
grep -q 'ripgrep 14.1.0 14.1.1-rc.1' "$TMP/cargo-pre.out" \
    || fail "a pre-release cargo latest must be reported"

# A channel with no manifest rows is not invoked at all (no stray runtime warning).
HOME="$CARGO_HOME" PATH="$CARGO_NOPATH:/nonexistent" \
    bash "$ECO" rust install >"$TMP/rust-empty.out" 2>&1 \
    || fail "a channel with no rows must install nothing, cleanly"
grep -q 'nothing to install' "$TMP/rust-empty.out" \
    || fail "an empty channel must say there is nothing to install"
! grep -q 'cargo not found' "$TMP/rust-empty.out" \
    || fail "an empty channel must not warn about a runtime it never needed"

# install is manifest-driven; update is not. A channel with no conf rows must
# still upgrade what its package manager reports — the row count says nothing
# about what is installed.
: > "$CARGO_LOG"
HOME="$CARGO_HOME" DOTFILES_NON_INTERACTIVE=1 ECO_ASSUME_YES=1 \
    MOCK_CARGO_LIST='ripgrep v14.1.0:
    rg' MOCK_CARGO_LAT_ripgrep=14.1.1 \
    PATH="$MOCK_CARGO:/usr/bin:/bin" \
    bash "$ECO" rust update -y >"$TMP/rust-update.out" 2>&1 \
    || fail "eco rust update must upgrade installed crates"
grep -q 'install --force --root' "$CARGO_LOG" \
    || fail "a rowless channel must still run the upgrade"
! grep -q 'nothing to update' "$TMP/rust-update.out" \
    || fail "update must not be gated on the manifest row count"

# ── uv version shapes ───────────────────────────────
# Pre-release / post / dev latest versions are legal and must not abort the
# whole update path (they used to fail the version shape check). The fixture
# mirrors real uv output: the [latest: …] marker sits on the tool's own line.
for ver in 0.18.0rc1 v0.18.0rc1 1.2.3.post1 0.9.0.dev0 0.17.1; do
    HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 \
        MOCK_UV_OUTDATED="ruff v0.17.0 [latest: $ver]
- ruff" \
        PATH="$MOCK_UV:/usr/bin:/bin" \
        bash "$ROOT/_install/install-by-uv.sh" --outdated >"$TMP/uv-ver.out" 2>/dev/null \
        || fail "uv latest '$ver' must be accepted"
    grep -q "ruff 0.17.0 $ver" "$TMP/uv-ver.out" \
        || fail "uv latest '$ver' must be reported"
done

# A garbage latest is still rejected.
if HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_UV_OUTDATED='ruff v0.17.0 [latest: not-a-version]
- ruff' \
    PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-uv.sh" --outdated >/dev/null 2>&1; then
    fail "a non-version uv latest must still fail the shape check"
fi

# ── one-shot verb arg guards ────────────────────────
# --uninstall-one needs both <bin> and <pkg>; a one-arg call used to die on
# an unbound $2 instead of printing usage.
for ch_script in install-by-npm.sh install-by-uv.sh install-by-go.sh install-by-cargo.sh; do
    HOME="$TMP/guard-home" PATH="$NPM_BIN:$MOCK_UV:$MOCK_GO:$MOCK_CARGO:/usr/bin:/bin" \
        bash "$ROOT/_install/$ch_script" --uninstall-one only-bin \
        >"$TMP/guard.out" 2>&1 && fail "$ch_script --uninstall-one with one arg must fail"
    grep -q 'usage:.*--uninstall-one <bin> <pkg>' "$TMP/guard.out" \
        || fail "$ch_script must print the --uninstall-one usage on a missing arg"
    ! grep -q 'unbound variable' "$TMP/guard.out" \
        || fail "$ch_script must not die on an unbound variable"

    # An unknown verb is a plain failure (1) for every channel. go has a
    # channel-private verb hook, and a bare call there would trip `set -e`
    # before the status could be read — the hook must report "not mine"
    # (127) internally without leaking it to the caller.
    rc=0
    HOME="$TMP/guard-home" PATH="$NPM_BIN:$MOCK_UV:$MOCK_GO:$MOCK_CARGO:/usr/bin:/bin" \
        bash "$ROOT/_install/$ch_script" --no-such-verb >"$TMP/guard.out" 2>&1 || rc=$?
    [[ "$rc" == 1 ]] || fail "$ch_script --no-such-verb must exit 1, got $rc"
    grep -q 'unknown option' "$TMP/guard.out" \
        || fail "$ch_script must report an unknown verb"
done

# ── version selectors are refused ───────────────────
# eco does not pin versions: the package managers disagree on what `pkg@ver`
# means, so it is rejected once instead of being reinterpreted per channel.
for spec in 'wrangler@3' '@biomejs/biome@2.0.0' 'gopls@v0.18.0'; do
    : > "$FNM_LOG"
    : > "$GO_LOG"
    rc=0
    HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
        PATH="$NPM_BIN:$MOCK_GO:/usr/bin:/bin" \
        bash "$ECO" node install -y "$spec" >"$ECO_OUT" 2>&1 || rc=$?
    [[ "$rc" == 1 ]] || fail "'$spec' must be refused with exit 1, got $rc"
    grep -q 'version selectors are not supported' "$ECO_OUT" \
        || fail "'$spec' must be refused with an explanation"
    [[ ! -s "$FNM_LOG" ]] \
        || fail "'$spec' must never reach npm"
done

# A scoped name is not a version selector: @scope/name must still work.
# A fresh HOME: ECO_HOME already has biome seated, and a named install of an
# installed bin is skipped before npm is ever called.
mkdir -p "$TMP/scoped-home"
: > "$FNM_LOG"
HOME="$TMP/scoped-home" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node install -y '@biomejs/biome' >"$ECO_OUT" 2>&1 \
    || fail "a scoped package name must still be installable"
grep -q '@biomejs/biome' "$FNM_LOG" \
    || fail "a scoped package must reach npm untouched"

# ── update reports the real transition ──────────────
# No network pre-query: eco reads the installed version, runs the update, reads
# again, and reports what actually happened.
TR_LS="$TMP/tr-ls.json"
printf '%s' '{"dependencies":{"wrangler":{"version":"3.0.0"}}}' > "$TR_LS"
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_FILE="$TR_LS" MOCK_LS_AFTER='{"dependencies":{"wrangler":{"version":"4.0.0"}}}' \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update -y wrangler >"$ECO_OUT" 2>&1 \
    || fail "a named update must not fail"
grep -q 'wrangler updated (3.0.0 → 4.0.0)' "$ECO_OUT" \
    || fail "a named update must report from-version → to-version"
! grep -q 'npm outdated' "$FNM_LOG" \
    || fail "update must not need an outdated pre-query"

# Nothing changed: say so instead of claiming an update.
printf '%s' '{"dependencies":{"wrangler":{"version":"4.0.0"}}}' > "$TR_LS"
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_FILE="$TR_LS" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update -y wrangler >"$ECO_OUT" 2>&1 \
    || fail "an up-to-date update must not fail"
grep -q 'already up to date (4.0.0)' "$ECO_OUT" \
    || fail "an unchanged version must be reported as up to date"
! grep -q 'wrangler updated' "$ECO_OUT" \
    || fail "an unchanged version must not be reported as updated"

# ── -y belongs to the verb ──────────────────────────
# `list` never prompts, so -y there is a usage error rather than a no-op.
rc=0
bash "$ECO" node list -y >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail "-y on list must be a usage error, got $rc"
# Anything after the channel that looks like an option is a usage error, and
# must never be silently ignored with exit 0.
for bad in '-y' '--yes'; do
    rc=0
    bash "$ECO" "$bad" node list >/dev/null 2>&1 || rc=$?
    [[ "$rc" == 2 ]] || fail "'$bad' before the channel must be a usage error, got $rc"
done
# -y after the verb is accepted and skipped confirmation.
: > "$FNM_LOG"
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_FILE="$TR_LS" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node update -y >"$ECO_OUT" 2>&1 \
    || fail "-y after the verb must be accepted"
! grep -q 'declined' "$ECO_OUT" \
    || fail "-y must skip the confirmation"

# ── duplicate targets are collapsed ─────────────────
: > "$FNM_LOG"
HOME="$TMP/dup-home" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node install -y cowsay cowsay >"$ECO_OUT" 2>&1 \
    || fail "duplicate install targets must not fail"
[[ "$(grep -c 'npm install -g ' "$FNM_LOG" || true)" == 1 ]] \
    || fail "a repeated package must install exactly once"

# ── help works without a valid manifest ─────────────
BAD_MANIFEST="$TMP/help-bad.conf"
printf 'bogus x y\n' > "$BAD_MANIFEST"
for args in '--help' 'node --help'; do
    # shellcheck disable=SC2086  # word splitting is the point
    ECO_CONF="$BAD_MANIFEST" bash "$ECO" $args >/dev/null 2>&1 \
        || fail "eco $args must work even when eco.conf is broken"
done
if ECO_CONF="$BAD_MANIFEST" bash "$ECO" node list >/dev/null 2>&1; then
    fail "a broken eco.conf must still fail a real command"
fi

# ── named install is idempotent ─────────────────────
mkdir -p "$TMP/idem-home/.local/bin"
touch "$TMP/idem-home/.local/bin/biome"
chmod +x "$TMP/idem-home/.local/bin/biome"
: > "$FNM_LOG"
HOME="$TMP/idem-home" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=biome \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node install biome >"$ECO_OUT" 2>&1 \
    || fail "a redundant named install must not fail"
[[ ! -s "$FNM_LOG" ]] \
    || fail "an already-installed bin must not be reinstalled by name"
grep -q 'already installed' "$ECO_OUT" \
    || fail "a redundant named install must say it was skipped"

# ── list failures surface instead of reading as empty ──
BROKEN_UV="$TMP/broken-uv"
mkdir -p "$BROKEN_UV"
cat > "$BROKEN_UV/uv" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == 'tool list' ]]; then
    printf '%s\n' 'error: cannot read tool state' >&2
    exit 2
fi
exit 0
EOF
chmod +x "$BROKEN_UV/uv"
if HOME="$UV_HOME" PATH="$BROKEN_UV:/usr/bin:/bin" \
    bash "$ECO" py list >"$TMP/eco-list-fail.out" 2>&1; then
    fail "a failed channel listing must not read as 'nothing installed'"
fi
grep -q 'listing uv CLIs failed' "$TMP/eco-list-fail.out" \
    || fail "a failed channel listing must be reported"

# ── bin names cannot escape the prefix ──────────────
SLASH_CONF="$TMP/slash-bin.conf"
printf 'node y ../../evil example.com/evil\n' > "$SLASH_CONF"
if ECO_CONF="$SLASH_CONF" bash -c 'source "$1"; eco_conf_load' _ "$ROOT/_scripts/cli-lifecycle.sh" 2>/dev/null; then
    fail "a bin containing a path separator must fail validation"
fi

# ── version-suffix detection ────────────────────────
# One predicate decides whether a package argument carries a version selector.
# Everything with a selector is refused; scoped names keep working because a
# single leading '@' is npm scope syntax, not a selector.
suffix_case() {
    local spec="$1" want="$2" got
    if bash -c 'source "$1"; pkg_has_selector "$2"' \
        _ "$ROOT/_scripts/cli-lifecycle.sh" "$spec"; then
        got=reject
    else
        got=accept
    fi
    [[ "$got" == "$want" ]] || fail "pkg_has_selector '$spec' gave '$got', wanted '$want'"
}
suffix_case 'wrangler'                  accept
suffix_case '@biomejs/biome'            accept
suffix_case '@scope/name'               accept
suffix_case 'golang.org/x/tools/gopls'  accept
suffix_case 'mvdan.cc/gofumpt'          accept
suffix_case 'wrangler@3'                reject
suffix_case '@scope/name@1.2.3'         reject
suffix_case 'gopls@v0.18.0'             reject
suffix_case 'foo@1.0.0'                 reject
suffix_case 'cowsay2@npm:cowsay@1.5.0'  reject

# ── a stale placeholder blocks a named install too ───
# The manifest path clears a non-executable placeholder before installing; the
# named path must do the same, or one entry point succeeds where the other
# fails with "executable already exists".
STALE_UV="$TMP/stale-uv"
STALE_HOME="$TMP/stale-home"
mkdir -p "$STALE_UV" "$STALE_HOME/.local/bin"
cat > "$STALE_UV/uv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == "tool install" ]]; then
    name="${3%%[=@]*}"
    if [[ -e "$HOME/.local/bin/$name" ]]; then
        printf 'error: Executable already exists: %s\n' "$name" >&2
        exit 1
    fi
fi
exit 0
EOF
chmod +x "$STALE_UV/uv"
: > "$STALE_HOME/.local/bin/ruff"
HOME="$STALE_HOME" DOTFILES_NON_INTERACTIVE=1 DOTFILES_ACCEPT_TOOLS=ruff \
    PATH="$STALE_UV:/usr/bin:/bin" \
    bash "$ECO" py install ruff >"$STALE_HOME/out.txt" 2>&1 \
    || fail "a named install must clear a stale placeholder first"
grep -q 'removed stale install entry' "$STALE_HOME/out.txt" \
    || fail "a cleared placeholder must be reported"

# ── a failed npm latest query is not 'current' ──────
# npm prints an error object with exit 1 when the query fails; the list must
# degrade that column to '?', not render the current version as latest.
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_JSON='{"dependencies":{"wrangler":{"version":"3.0.0"}}}' \
    MOCK_OUTDATED_JSON='{"error":{"code":"EAI_AGAIN","summary":"getaddrinfo"}}' \
    MOCK_OUTDATED_EXIT=1 \
    MOCK_HOST_NODE="$(command -v node)" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node list >"$TMP/npm-err-list.out" 2>/dev/null \
    || fail "eco list must survive a failed npm outdated query"
grep -qE 'wrangler[[:space:]]+3\.0\.0[[:space:]]+\?' "$TMP/npm-err-list.out" \
    || fail "a failed npm latest query must degrade to '?', not repeat the current version"

# ── a failed snapshot is reported, not swallowed ─────
# channel_installed returns rows on stdout, which every caller captures into a
# variable. Its failure warning therefore has to go to stderr, or the user sees
# a bare non-zero exit with no reason.
BROKEN_LS_BIN="$TMP/broken-ls-bin"
mkdir -p "$BROKEN_LS_BIN"
cat > "$BROKEN_LS_BIN/fnm" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *'node --version'*) printf '%s\n' v24.0.0 ;;
    *'npm prefix -g'*) printf '%s\n' /tmp/broken-ls-prefix ;;
    *'npm ls'*) printf '%s\n' 'registry unreachable' >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$BROKEN_LS_BIN/fnm"
rc=0
HOME="$TMP/broken-ls-home" PATH="$BROKEN_LS_BIN:/usr/bin:/bin" \
    bash "$ECO" node uninstall -y wrangler >"$TMP/snap-fail.out" 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail "an unreadable snapshot must fail the uninstall, got $rc"
grep -q 'cannot read installed npm CLIs' "$TMP/snap-fail.out" \
    || fail "an unreadable snapshot must say so on stderr"

# ── a fresh machine is empty, not broken ────────────
# npm exits 254 with an ENOENT error object when its global root does not exist
# yet. That is "nothing installed", and must read that way — a false alarm on a
# machine that has simply never installed an npm CLI is the same kind of lie as
# reporting a success that did not happen.
FRESH_BIN="$TMP/fresh-bin"
FRESH_HOME="$TMP/fresh-home"
mkdir -p "$FRESH_BIN" "$FRESH_HOME/.local"
cat > "$FRESH_BIN/fnm" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *'node --version'*) printf '%s\n' v24.0.0 ;;
    *'npm prefix -g'*) printf '%s\n' "$FRESH_PREFIX" ;;
    *'npm ls'*)
        printf '{"error":{"code":"ENOENT","summary":"ENOENT: no such file or directory, lstat '"'"'%s/lib'"'"'"}}' "$FRESH_PREFIX"
        exit 254
        ;;
esac
exit 0
EOF
chmod +x "$FRESH_BIN/fnm"
export FRESH_PREFIX="$FRESH_HOME/.local"
HOME="$FRESH_HOME" PATH="$FRESH_BIN:/usr/bin:/bin" \
    bash "$ECO" node list >"$TMP/fresh.out" 2>&1 \
    || fail "an empty npm root must not fail list"
grep -q 'no npm CLIs found' "$TMP/fresh.out" \
    || fail "an empty npm root must be reported as no CLIs"
HOME="$FRESH_HOME" PATH="$FRESH_BIN:/usr/bin:/bin" DOTFILES_NON_INTERACTIVE=1 \
    bash "$ECO" node update >"$TMP/fresh2.out" 2>&1 \
    || fail "an empty npm root must not fail update"
grep -q 'nothing to update' "$TMP/fresh2.out" \
    || fail "an empty npm root must read as nothing to update"
! grep -q 'cannot read installed' "$TMP/fresh2.out" \
    || fail "an empty npm root must not be reported as unreadable"
unset FRESH_PREFIX

# ── a broken toolchain is not "nothing installed" ────
# No Go metadata in the shared prefix is normal (npm/uv put scripts there), so a
# scan that finds nothing must stay a success. A toolchain that cannot answer at
# all is a different thing, and must not be reported as an empty channel.
BROKEN_GO_BIN="$TMP/broken-go-bin"
mkdir -p "$BROKEN_GO_BIN" "$TMP/broken-go-home/.local/bin"
printf '#!/bin/sh\n' > "$TMP/broken-go-home/.local/bin/foo"
chmod +x "$TMP/broken-go-home/.local/bin/foo"
cat > "$BROKEN_GO_BIN/go" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == env && "$2" == GOENV ]]; then printf '\n'; exit 0; fi
if [[ "$1" == version ]]; then exit 2; fi
exit 0
EOF
chmod +x "$BROKEN_GO_BIN/go"
rc=0
HOME="$TMP/broken-go-home" PATH="$BROKEN_GO_BIN:/usr/bin:/bin" \
    bash "$ROOT/_install/install-by-go.sh" --installed >"$TMP/gone.out" 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail "a broken go toolchain must fail --installed, got $rc"
grep -q 'go is not working' "$TMP/gone.out" \
    || fail "a broken go toolchain must be reported"

# ── a failed channel install propagates ─────────────
# bootstrap.sh step 3 loops the four channels and warns per channel; that only
# works if a failing manifest install returns non-zero (and does not abort the
# loop). A channel whose runtime is broken must fail, not report success.
BROKEN_INSTALL_UV="$TMP/broken-install-uv"
mkdir -p "$BROKEN_INSTALL_UV"
cat > "$BROKEN_INSTALL_UV/uv" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2" == 'tool install' ]]; then
    printf '%s\n' 'error: no network' >&2
    exit 1
fi
exit 0
EOF
chmod +x "$BROKEN_INSTALL_UV/uv"
if HOME="$TMP/broken-install-home" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$BROKEN_INSTALL_UV:/usr/bin:/bin" \
    bash "$ECO" py install >"$TMP/eco-install-fail.out" 2>&1; then
    fail "a failed channel install must propagate so bootstrap can warn"
fi
grep -q 'install failed' "$TMP/eco-install-fail.out" \
    || fail "a failed channel install must name the failing tool"

# The loop's failure isolation: one broken channel must not stop the next.
# A channel whose runtime is present but whose install fails must return
# non-zero, so bootstrap's per-channel warn is reached.
BROKEN_NODE_BIN="$TMP/broken-node-bin"
mkdir -p "$BROKEN_NODE_BIN"
cat > "$BROKEN_NODE_BIN/fnm" <<'EOF'
#!/usr/bin/env bash
# fnm exec --using lts-latest -- <cmd...>
shift 4
cmd="$1"; shift
case "$cmd" in
  node) if [[ "$1" == '--version' ]]; then printf '%s\n' v24.0.0; else exec "$MOCK_NODE" "$@"; fi ;;
  npm) case "$*" in
          'prefix -g') printf '%s\n' /tmp/loop-prefix ;;
          'install --help') printf '%s\n' '--allow-scripts' ;;
          'install -g'*) printf '%s\n' 'npm ERR! network' >&2; exit 1 ;;
       esac
esac
EOF
chmod +x "$BROKEN_NODE_BIN/fnm"
loop_ran="$TMP/loop-ran.log"
: > "$loop_ran"
for _ch in node py; do
    HOME="$TMP/loop-home" DOTFILES_NON_INTERACTIVE=1 ECO_ASSUME_YES=1 \
        MOCK_NODE="$(command -v node)" \
        PATH="$BROKEN_NODE_BIN:$MOCK_UV:/usr/bin:/bin" \
        bash "$ECO" "$_ch" install -y codex ruff >/dev/null 2>&1 \
        || printf '%s\n' "$_ch" >> "$loop_ran"
    # Keep the py run independent of whatever the node run left behind.
    rm -rf "$TMP/loop-home/.local"
done
grep -q '^node$' "$loop_ran" \
    || fail "a broken node channel must report failure"
! grep -q '^py$' "$loop_ran" \
    || fail "a broken node channel must not prevent the py channel from succeeding"

# uv is never handed a selector: eco refuses it before the channel runs, so no
# `ruff@0.14` (which uv would read as a local path) can reach `uv tool`.
: > "$UV_LOG"
HOME="$UV_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$MOCK_UV:/usr/bin:/bin" \
    bash "$ECO" py update -y 'ruff@0.14' >"$TMP/uv-pin.out" 2>&1 \
    && fail "a versioned uv update must be refused"
grep -q 'version selectors are not supported' "$TMP/uv-pin.out" \
    || fail "a versioned uv update must explain why it was refused"
[[ ! -s "$UV_LOG" ]] \
    || fail "a versioned spec must never reach uv"

# ── removal takes a name, and only a name ───────────
# There is no version to strip any more: a versioned uninstall is refused up
# front instead of being silently rewritten.
: > "$FNM_LOG"
rc=0
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node uninstall -y 'wrangler@3' >"$ECO_OUT" 2>&1 || rc=$?
[[ "$rc" == 1 ]] || fail "a versioned uninstall must be refused, got $rc"
grep -q 'version selectors are not supported' "$ECO_OUT" \
    || fail "a versioned uninstall must explain why it was refused"
[[ ! -s "$FNM_LOG" ]] \
    || fail "a versioned uninstall must never reach npm"

# A scoped package keeps its scope when removed.
SCOPED_LS="$TMP/scoped-ls.json"
printf '%s' '{"dependencies":{"@biomejs/biome":{"version":"2.0.0"}}}' > "$SCOPED_LS"
: > "$FNM_LOG"
printf 'y\n' | env -u DOTFILES_NON_INTERACTIVE HOME="$ECO_HOME" \
    MOCK_LS_FILE="$SCOPED_LS" MOCK_LS_AFTER='{"dependencies":{}}' \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node uninstall '@biomejs/biome' >"$ECO_OUT" 2>&1 \
    || fail "a scoped uninstall must not fail"
grep -qE -- 'npm uninstall -g --prefix [^ ]+ @biomejs/biome$' "$FNM_LOG" \
    || fail "a scoped name must keep its scope on removal"

# ── npm error reason is surfaced ────────────────────
# The latest column degrades to "?", but the reason (e.g. a DNS failure
# summary from npm's error payload) must be warned, not silently swallowed.
HOME="$ECO_HOME" DOTFILES_NON_INTERACTIVE=1 \
    MOCK_LS_JSON='{"dependencies":{"wrangler":{"version":"3.0.0"}}}' \
    MOCK_OUTDATED_JSON='{"error":{"code":"EAI_AGAIN","summary":"getaddrinfo EAI_AGAIN registry.npmjs.org"}}' \
    MOCK_OUTDATED_EXIT=1 \
    MOCK_HOST_NODE="$(command -v node)" \
    PATH="$NPM_BIN:/usr/bin:/bin" \
    bash "$ECO" node list >"$TMP/npm-err-reason.out" 2>&1 \
    || fail "eco list must survive a failed npm outdated query"
grep -q 'npm outdated query failed: getaddrinfo' "$TMP/npm-err-reason.out" \
    || fail "the npm error summary must be surfaced as a warning"

echo "PASS eco lifecycle tests"

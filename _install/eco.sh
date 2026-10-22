#!/usr/bin/env bash
# _install/eco.sh — unified lifecycle entrypoint for ecosystem CLIs.
#
# Thin proxy over the npm/uv/go/cargo channels: it does syntax checking,
# bin→pkg resolution, confirmation, and rendering — then dispatches dumb
# one-shot commands to the owning channel.
#
#   eco <node|py|go|rust> list
#   eco <node|py|go|rust> install [pkg…]
#   eco <node|py|go|rust> update   [pkg…]
#   eco <node|py|go|rust> uninstall <pkg…>

set -euo pipefail

# Resolve the real script location: it may be invoked through a symlink
# (e.g. ~/.local/bin/eco), and the relative paths below depend on it.
SCRIPT_PATH="${BASH_SOURCE[0]}"
while [[ -L "$SCRIPT_PATH" ]]; do
    SCRIPT_DIR="$(cd -P "$(dirname "$SCRIPT_PATH")" && pwd)"
    SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
    [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
done
SCRIPT_DIR="$(cd -P -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/cli-lifecycle.sh"
# eco_conf_load runs in main() after argument parsing: `eco --help` must work
# even when the manifest is broken (that is exactly when you need the usage).

# ── channel routing ─────────────────────────────────────────────
# User-facing vocabulary (node/py/go/rust) maps to internal scripts
# (npm/uv/go/cargo). The internal name is used in messages.
channel_script() {
    case "$1" in
        node) printf '%s/install-by-npm.sh' "$SCRIPT_DIR" ;;
        py)   printf '%s/install-by-uv.sh' "$SCRIPT_DIR" ;;
        go)   printf '%s/install-by-go.sh' "$SCRIPT_DIR" ;;
        rust) printf '%s/install-by-cargo.sh' "$SCRIPT_DIR" ;;
    esac
}

channel_name() {
    case "$1" in
        node) printf 'npm' ;;
        py)   printf 'uv' ;;
        go)   printf 'go' ;;
        rust) printf 'cargo' ;;
    esac
}

usage() {
    echo "usage: eco <node|py|go|rust> <list|install|update|uninstall> [-y] [-q] [-n] [pkg…]"
    echo ""
    echo "  list                  list installed CLIs with current and latest versions"
    echo "  install [-y] [pkg…]   install missing CLIs; without pkg, manifest mode"
    echo "                        (y rows install unasked, n rows ask [y/N])"
    echo "  update  [-y] [pkg…]   upgrade installed CLIs; without pkg, all of them"
    echo "  uninstall [-y] <pkg…> remove installed CLIs (package names required)"
    echo ""
    echo "  -y, --yes             do not ask for confirmation (not valid for list)"
    echo "  -q, --quiet           drop eco's own progress lines (warnings, errors and"
    echo "                        the package manager's output still show)"
    echo "  -n, --dry-run         print what would run, execute nothing (not valid for list)"
    echo ""
    echo "Packages are bin names from eco.conf, or raw package names for unmanaged tools."
    echo "update and uninstall also accept any executable a package ships (e.g. cf-wrangler)."
    echo "Versions are never pinned here: install and update take whatever the package"
    echo "manager resolves, and 'list' shows what is currently installed."
}

# ── argument resolution ─────────────────────────────────────────
# conf_row_for <channel> <key> — find the conf row whose bin or pkg matches
# <key> within <channel>. Sets CONF_BIN / CONF_PKG / CONF_FLAG on success;
# returns 1 when no row matches (caller falls back to raw-pkg handling).
conf_row_for() {
    local ch="$1" key="$2" i
    CONF_BIN="" CONF_PKG="" CONF_FLAG=""
    for i in "${!ECO_CONF_BINS[@]}"; do
        [[ "${ECO_CONF_CHANNELS[i]}" == "$ch" ]] || continue
        if [[ "${ECO_CONF_BINS[i]}" == "$key" || "${ECO_CONF_PKGS[i]}" == "$key" ]]; then
            CONF_BIN="${ECO_CONF_BINS[i]}"
            CONF_PKG="${ECO_CONF_PKGS[i]}"
            CONF_FLAG="${ECO_CONF_FLAGS[i]}"
            return 0
        fi
    done
    return 1
}

# conf_channel_row_count <channel> — how many manifest rows a channel owns.
# The install path uses it to skip a channel the manifest does not cover, so it
# never warns about a runtime nobody asked for. update and uninstall do not:
# they act on what is installed, not on the manifest.
conf_channel_row_count() {
    local ch="$1" i n=0
    for i in "${!ECO_CONF_BINS[@]}"; do
        [[ "${ECO_CONF_CHANNELS[i]}" == "$ch" ]] && n=$((n + 1))
    done
    printf '%s\n' "$n"
}

# resolve_args <channel> [arg…]
# Fills TARGET_BINS / TARGET_PKGS / TARGET_FLAGS.
# An arg matching a conf bin (or pkg) yields that row's pkg+flag; otherwise the
# arg is a raw pkg (flag empty).
#
# go is the one channel where an unregistered arg has two identities: `go
# install` takes a package path and names the binary after its last segment.
# Split them for every verb — detection keys on the bin.
#
# A bare name is the only accepted form: `pkg@selector` is refused, because eco
# stores no versions (see pkg_has_selector). A refused argument is a usage
# error, so it exits 2 — 1 is reserved for an action that failed.
resolve_args() {
    local ch="$1"
    shift
    TARGET_BINS=()
    TARGET_PKGS=()
    TARGET_FLAGS=()
    local arg
    for arg in "$@"; do
        if pkg_has_selector "$arg"; then
            error_msg "version selectors are not supported: '$arg'"
            info "eco installs and updates whatever the package manager resolves;"
            info "use 'eco <ch> list' to see the installed versions."
            return 2
        fi
        if conf_row_for "$ch" "$arg"; then
            TARGET_BINS+=("$CONF_BIN")
            TARGET_PKGS+=("$CONF_PKG")
            TARGET_FLAGS+=("$CONF_FLAG")
        elif [[ "$ch" == "go" ]]; then
            TARGET_BINS+=("${arg##*/}")
            TARGET_PKGS+=("$arg")
            TARGET_FLAGS+=("")
        else
            TARGET_BINS+=("$arg")
            TARGET_PKGS+=("$arg")
            TARGET_FLAGS+=("")
        fi
    done
}

# prune_installed_targets <channel>
# A named install is idempotent, like the manifest path: a bin that is already
# present is reported and skipped instead of reinstalled. Path-detected
# channels also honor a foreign PATH install; npm keys on the canonical prefix
# only.
prune_installed_targets() {
    local ch="$1" internal detect i path snapshot="" snapshot_ok=0
    internal="$(channel_name "$ch")"
    detect="$(channel_detect "$internal")"
    local -a kb=() kp=() kf=()
    for i in "${!TARGET_BINS[@]}"; do
        path="$ECO_BIN_DIR/${TARGET_BINS[i]}"
        if [[ "$detect" == "path" ]]; then
            if is_installed "${TARGET_BINS[i]}" "$path"; then
                info "${TARGET_BINS[i]} already installed; skipping"
                continue
            fi
        elif [[ -x "$path" ]]; then
            info "${TARGET_BINS[i]} already installed; skipping"
            continue
        fi
        # A package need not land a bin of its own name (typescript → tsc), so
        # the path check above cannot see it. Ask the snapshot; an unreadable
        # one is not evidence of absence — install reports its own failure.
        if (( ! snapshot_ok )); then
            snapshot_ok=1
            # Advisory: install prepares the runtime itself, so a read that
            # cannot run yet must not tell the user to fix it first.
            if ! snapshot="$(channel_installed "$ch" 2>/dev/null)"; then
                snapshot=""
                # A plan must not look certain about a state it could not read.
                if [[ -n "${ECO_DRY_RUN:-}" ]]; then
                    warn "cannot read installed $internal CLIs; the plan assumes the runtime is available"
                fi
            fi
        fi
        if [[ -n "$snapshot" ]] \
           && installed_target_present "$snapshot" "${TARGET_BINS[i]}" "${TARGET_PKGS[i]}"; then
            info "${TARGET_BINS[i]} already installed; skipping"
            continue
        fi
        # A stale placeholder is not "installed" (is_installed says no) yet
        # still blocks a fresh install (EEXIST / "executable already exists"),
        # so clear it the same way the manifest path does. A dry run promises
        # no mutation, so it leaves the placeholder alone.
        if [[ -z "${ECO_DRY_RUN:-}" ]]; then
            clean_stale_installs "$path"
        fi
        kb+=("${TARGET_BINS[i]}")
        kp+=("${TARGET_PKGS[i]}")
        kf+=("${TARGET_FLAGS[i]}")
    done
    # bash 3.2: an empty array expansion under `set -u` is an unbound variable.
    if (( ${#kb[@]} > 0 )); then
        TARGET_BINS=("${kb[@]}")
        TARGET_PKGS=("${kp[@]}")
        TARGET_FLAGS=("${kf[@]}")
    else
        TARGET_BINS=()
        TARGET_PKGS=()
        TARGET_FLAGS=()
    fi
}

# ── installed snapshot ─────────────────────────────────────────
# channel_installed <channel> — local-only rows, no network. Every channel emits
# the shared shape "key version package [aliases…]" (see installed_row_for).
# The single source of truth for what is on the machine: update reads it before
# and after to report a real transition, uninstall uses it to decide whether a
# target exists at all. Package manager exit codes cannot answer that — npm
# returns 0 for a package that was never installed.
#
# stdout is the data channel here, so the failure warning goes to stderr: every
# caller captures this into a variable and would otherwise swallow it.
channel_installed() {
    local ch="$1" script internal
    script="$(channel_script "$ch")"
    internal="$(channel_name "$ch")"
    local out rc=0
    out="$(bash "$script" --installed)" || rc=$?
    if (( rc != 0 )); then
        warn "cannot read installed $internal CLIs (exit $rc)" >&2
        return 1
    fi
    printf '%s\n' "$out"
}

# installed_version_of <snapshot> <key> — one row's version. Rows are
# "key version [package] [aliases…]"; the trailing columns are read and
# dropped so a two-field read cannot glue a package path onto the version.
installed_version_of() {
    local snapshot="$1" want="$2" bin ver _rest
    while read -r bin ver _rest; do
        [[ -n "$bin" ]] || continue
        if [[ "$bin" == "$want" ]]; then
            printf '%s\n' "$ver"
            return 0
        fi
    done <<<"$snapshot"
    return 1
}

# snapshot_row <snapshot> <want…> — the first row matching any want by key,
# package or shipped executable, printed as key<TAB>pkg<TAB>aliases. Rows are
# "key version pkg [aliases…]"; the two identities differ per channel
# (cargo: ripgrep/rg, npm: typescript/tsc, uv: python-lsp-server/pylsp,
# go: staticcheck/honnef.co/…/staticcheck), so every lookup shares this rule.
snapshot_row() {
    local snapshot="$1" want key ver pkg aliases
    shift
    while read -r key ver pkg aliases; do
        [[ -n "$key" ]] || continue
        for want in "$@"; do
            [[ -n "$want" ]] || continue
            if [[ "$key" == "$want" || "${pkg:-}" == "$want" \
                  || " ${aliases:-} " == *" $want "* ]]; then
                printf '%s\t%s\t%s\n' "$key" "${pkg:-}" "${aliases:-}"
                return 0
            fi
        done
    done <<<"$snapshot"
    return 1
}

# row_has_executable <key> <aliases> — is any executable the row names present
# under ECO_BIN_DIR? A key need not be a file (cargo keys on the crate), and a
# multi-bin package stays alive through any one of its executables.
row_has_executable() {
    local key="$1" b
    local -a names=()
    # read -a, not an unquoted expansion: a bin name is data, not a glob.
    [[ -n "$2" ]] && read -r -a names <<<"$2"
    for b in "$key" ${names[@]+"${names[@]}"}; do
        [[ -x "$ECO_BIN_DIR/$b" ]] && return 0
    done
    return 1
}

# installed_row_for <snapshot> <want> — "key pkg" of the matching row. A row
# without a package column cannot be translated, so it fails and the caller
# keeps the identity it already has.
installed_row_for() {
    local row key pkg aliases
    row="$(snapshot_row "$1" "$2")" || return 1
    IFS=$'\t' read -r key pkg aliases <<<"$row"
    [[ -n "$pkg" ]] || return 1
    printf '%s %s\n' "$key" "$pkg"
}

# row_on_disk <snapshot> <want> — is the matching row present on disk?
row_on_disk() {
    local row key pkg aliases
    row="$(snapshot_row "$1" "$2")" || return 1
    IFS=$'\t' read -r key pkg aliases <<<"$row"
    row_has_executable "$key" "$aliases"
}

# installed_target_present <snapshot> <bin> <pkg> — did the package we acted on
# land an executable? Both identities of the request are accepted, since the
# snapshot knows how the package manager names the row.
installed_target_present() {
    local row key pkg aliases
    row="$(snapshot_row "$1" "$2" "$3")" || return 1
    IFS=$'\t' read -r key pkg aliases <<<"$row"
    row_has_executable "$key" "$aliases"
}

# resolved_pkg_flag <channel> <key> <pkg> — "pkg flag" to act on for a
# translated row. The manifest wins for a package it knows, so updating through
# an alias keeps its flag (cf-wrangler → wrangler --allow-scripts). Values
# contain no spaces (validated), so the pair travels as one line.
resolved_pkg_flag() {
    local ch="$1" key="$2" pkg="$3"
    if conf_row_for "$ch" "$key" || conf_row_for "$ch" "$pkg"; then
        printf '%s %s\n' "$CONF_PKG" "$CONF_FLAG"
    else
        printf '%s\n' "$pkg"
    fi
}

# dedupe_targets — drop repeated bins, keeping the first occurrence, so
# `eco node install -y biome biome` installs once.
dedupe_targets() {
    local i j dup
    local -a kb=() kp=() kf=()
    for i in "${!TARGET_BINS[@]}"; do
        dup=0
        for j in "${!kb[@]}"; do
            if [[ "${kb[j]}" == "${TARGET_BINS[i]}" ]]; then
                dup=1
                break
            fi
        done
        (( dup )) && continue
        kb+=("${TARGET_BINS[i]}")
        kp+=("${TARGET_PKGS[i]}")
        kf+=("${TARGET_FLAGS[i]}")
    done
    if (( ${#kb[@]} > 0 )); then
        TARGET_BINS=("${kb[@]}")
        TARGET_PKGS=("${kp[@]}")
        TARGET_FLAGS=("${kf[@]}")
    else
        TARGET_BINS=()
        TARGET_PKGS=()
        TARGET_FLAGS=()
    fi
}

# warn_ghost <verb> <name> <internal> — the manager still lists the row, but
# no executable is on disk. The caller skips it: update cannot verify a
# transition it cannot witness, uninstall has nothing to remove, and install is
# the repair.
warn_ghost() {
    local verb="$1" name="$2" internal="$3"
    warn "$name: $internal reports it installed, but none of its executables exist in $ECO_BIN_DIR"
    if [[ "$verb" == "update" ]]; then
        warn "$name skipped: use 'install' to reinstall it"
    else
        warn "$name skipped: nothing to remove"
    fi
}

# prune_absent_targets <verb> <channel> <snapshot>
# Keep only targets the user can actually see: the snapshot lists the package
# AND one of its executables exists in ECO_BIN_DIR. A snapshot-only ghost is
# warned and skipped; a name no row claims is reported as not installed.
# The user-facing channel is needed to consult the manifest while translating.
prune_absent_targets() {
    local verb="$1" ch="$2" snapshot="$3" internal i bin row rbin rpkg rflag
    internal="$(channel_name "$ch")"
    local -a kb=() kp=() kf=()
    for i in "${!TARGET_BINS[@]}"; do
        bin="${TARGET_BINS[i]}"
        if installed_version_of "$snapshot" "$bin" >/dev/null; then
            # Any executable the row ships is a witness; a ghost is skipped.
            if ! row_on_disk "$snapshot" "$bin"; then
                warn_ghost "$verb" "$bin" "$internal"
                continue
            fi
            # A raw bin name (ncc) still carries the bin as its pkg. Adopt the
            # snapshot's package when nothing else identifies the target; a
            # manifest row already has an authoritative pkg and flag.
            if [[ "${TARGET_PKGS[i]}" == "$bin" && -z "${TARGET_FLAGS[i]}" ]] \
               && row="$(installed_row_for "$snapshot" "$bin")"; then
                read -r rbin rpkg <<<"$row"
                read -r rpkg rflag <<<"$(resolved_pkg_flag "$ch" "$rbin" "$rpkg")"
                kb+=("$rbin")
                kp+=("$rpkg")
                kf+=("$rflag")
            else
                kb+=("$bin")
                kp+=("${TARGET_PKGS[i]}")
                kf+=("${TARGET_FLAGS[i]}")
            fi
        # Not a key the snapshot knows, but it may name a row from the other
        # side (the user types rg, the row is keyed ripgrep). Translate; only
        # an unclaimed name is "not installed".
        elif row="$(installed_row_for "$snapshot" "$bin")"; then
            read -r rbin rpkg <<<"$row"
            # A translated name obeys the same witness as a key.
            if ! row_on_disk "$snapshot" "$rbin"; then
                warn_ghost "$verb" "$bin" "$internal"
                continue
            fi
            read -r rpkg rflag <<<"$(resolved_pkg_flag "$ch" "$rbin" "$rpkg")"
            kb+=("$rbin")
            kp+=("$rpkg")
            kf+=("$rflag")
        elif [[ "$verb" == "update" ]]; then
            warn "$bin is not installed via $internal; nothing to update (use 'install')"
        else
            warn "$bin is not installed via $internal; nothing to remove"
        fi
    done
    if (( ${#kb[@]} > 0 )); then
        TARGET_BINS=("${kb[@]}")
        TARGET_PKGS=("${kp[@]}")
        TARGET_FLAGS=("${kf[@]}")
    else
        TARGET_BINS=()
        TARGET_PKGS=()
        TARGET_FLAGS=()
    fi
}

# show_current_versions <internal> <snapshot>
# What this run is about to touch, and the version each has right now. Local
# data only: the resulting version is reported after the action, so nothing
# here can predict a value it has not observed.
show_current_versions() {
    local internal="$1" snapshot="$2" i bin ver w=7
    local -a pairs=()
    for i in "${!TARGET_BINS[@]}"; do
        bin="${TARGET_BINS[i]}"
        ver="$(installed_version_of "$snapshot" "$bin" || true)"
        [[ -n "$ver" ]] || ver="-"
        pairs+=("$bin $ver")
        (( ${#bin} > w )) && w=${#bin}
    done
    (( ${#pairs[@]} > 0 )) || return 0
    info "updating via $internal:"
    printf "  %-$((w + 1))s%s\n" "package" "current"
    for i in "${!pairs[@]}"; do
        read -r bin ver <<<"${pairs[i]}"
        printf "  %-$((w + 1))s%s\n" "$bin" "$ver"
    done
}

# print_plan <verb> <internal> — the actions a dry run would take, with the
# package and (for install/update) the flag each channel would receive.
# Uninstall takes no flag, so showing one there would be a lie.
#
# Written to stdout, not through info(): the plan is the dry run's whole
# deliverable, so -q (which drops progress chatter) must not erase it —
# the same rule `list` follows for its table.
print_plan() {
    local verb="$1" internal="$2" i what
    for i in "${!TARGET_BINS[@]}"; do
        what="${TARGET_BINS[i]} (${TARGET_PKGS[i]})"
        [[ -n "${TARGET_FLAGS[i]}" && "$verb" != "uninstall" ]] \
            && what="$what [${TARGET_FLAGS[i]}]"
        printf 'would %s %s via %s\n' "$verb" "$what" "$internal"
    done
}

# ── batch confirm + dispatch ────────────────────────────────────
# batch_confirm_and_run <verb> <channel>
# One batch confirm covers every target (default N). `-y` (ECO_ASSUME_YES)
# skips it. In non-interactive mode without -y nothing is approved, which is
# what keeps bootstrap and CI from mutating a machine by accident.
# Approved targets execute one-by-one via the channel's dumb one-shot verb;
# a failed row warns and continues, the aggregate exit code reports any failure.
batch_confirm_and_run() {
    local verb="$1" ch="$2"
    local internal script
    internal="$(channel_name "$ch")"
    script="$(channel_script "$ch")"

    # update and uninstall act on what is already there, so both start from the
    # installed snapshot: it decides whether a target exists (the package
    # managers disagree about a missing one — npm exits 0 and does nothing, uv
    # exits 2, cargo exits 101) and, for update, what version is about to move.
    # A caller that already read it (do_update_all) passes it in SNAPSHOT_BEFORE.
    local before=""
    if [[ "$verb" == "update" || "$verb" == "uninstall" ]]; then
        before="${SNAPSHOT_BEFORE:-}"
        # A failed read is an error, not an empty machine: pruning against it
        # would silently turn every target into "not installed".
        [[ -n "$before" ]] || before="$(channel_installed "$ch")" || return 1
        prune_absent_targets "$verb" "$ch" "$before"
        # Translation can collapse two inputs onto one package, so dedupe
        # again after it.
        dedupe_targets
    fi

    local -a auth_bins=() auth_pkgs=() auth_flags=()
    local count=${#TARGET_BINS[@]}
    (( count > 0 )) || { info "nothing to $verb"; return 0; }

    local verb_one doing done_w prompt_verb
    case "$verb" in
        install)   verb_one="--install-one";   doing="installing";   done_w="installed";   prompt_verb="Install" ;;
        update)    verb_one="--update-one";    doing="updating";     done_w="updated";     prompt_verb="Update" ;;
        uninstall) verb_one="--uninstall-one"; doing="uninstalling"; done_w="uninstalled"; prompt_verb="Uninstall" ;;
    esac

    # Show what is about to move, before asking, so a confirmation is not blind.
    # Quiet mode drops this too: it is progress, not data.
    [[ "$verb" == "update" && -z "${ECO_QUIET:-}" ]] && show_current_versions "$internal" "$before"

    # A dry run prints the plan and stops before any prompt or action. Local
    # state was read, so the plan reflects what is installed.
    if [[ -n "${ECO_DRY_RUN:-}" ]]; then
        print_plan "$verb" "$internal"
        info "dry run: no action taken"
        return 0
    fi

    if [[ -n "${ECO_ASSUME_YES:-}" ]] \
       || confirm "$prompt_verb $count via $internal? [y/N]: " 0; then
        auth_bins=("${TARGET_BINS[@]}")
        auth_pkgs=("${TARGET_PKGS[@]}")
        auth_flags=("${TARGET_FLAGS[@]}")
    else
        info "declined $count $internal CLI(s); nothing was $done_w"
        return 0
    fi

    # update and uninstall are judged against the state after the action, and
    # that state is the same for the whole batch: collect the successes, read
    # the snapshot once. Install needs no such read in the common case, so it
    # verifies in place.
    local after="" rc=0 one_rc state_unknown=0
    local i bin new_ver cur_ver
    local -a done_bins=()
    for i in "${!auth_bins[@]}"; do
        bin="${auth_bins[i]}"
        info "$doing $bin (${auth_pkgs[i]}) via $internal..."
        one_rc=0
        bash "$script" "$verb_one" "$bin" "${auth_pkgs[i]}" "${auth_flags[i]}" || one_rc=$?
        # Exit 3 is the channel's "runtime unavailable, nothing done" signal:
        # a missing fnm/uv/go/cargo skips cleanly during bootstrap, but an
        # explicit one-shot request must not be reported as completed.
        if (( one_rc == 3 )); then
            warn "$bin was not $done_w ($internal runtime unavailable)"
            rc=1
            continue
        fi
        if (( one_rc != 0 )); then
            warn "$bin $verb failed; retry manually later"
            rc=1
            continue
        fi

        if [[ "$verb" != "install" ]]; then
            done_bins+=("$bin")
            continue
        fi

        # An exit code says the command ran, not that a binary appeared (npm
        # exits 0 for a package that ships no bin). Every channel lands its
        # bins in ECO_BIN_DIR; when the arg names a package rather than a bin
        # (typescript → tsc), the snapshot supplies the executable to look for.
        # The path check below settles the common case without a listing.
        if [[ -x "$ECO_BIN_DIR/$bin" ]]; then
            ok "$bin $done_w"
            continue
        fi
        if ! after="$(channel_installed "$ch")"; then
            warn "$bin: install could not be verified; check it manually"
            state_unknown=1
            continue
        fi
        if ! installed_target_present "$after" "$bin" "${auth_pkgs[i]}"; then
            error_msg "$bin was not $done_w: no executable at $ECO_BIN_DIR/$bin"
            info "the package may not ship a '$bin' command; check the package name"
            rc=1
            continue
        fi
        ok "$bin $done_w"
    done

    if (( ${#done_bins[@]} > 0 )); then
        # An unreadable snapshot leaves every queued outcome unknowable, which
        # is a failure, not a success.
        if ! after="$(channel_installed "$ch")"; then
            # Name the targets: one unreadable read leaves every one of them
            # unknown, and "verify manually" is useless without the list.
            warn "cannot read the installed $internal CLIs after ${verb} (${done_bins[*]}); verify the results manually"
            state_unknown=1
        else
            for i in "${!done_bins[@]}"; do
                bin="${done_bins[i]}"
                if [[ "$verb" == "uninstall" ]]; then
                    # Trust the snapshot, not the exit code (npm reports
                    # success for a package that was never there).
                    if installed_version_of "$after" "$bin" >/dev/null; then
                        error_msg "$bin was not removed (still installed)"
                        rc=1
                    else
                        ok "$bin uninstalled"
                    fi
                    continue
                fi
                # Update: report the transition actually observed, never a
                # version predicted before the action.
                cur_ver="$(installed_version_of "$before" "$bin" || true)"
                new_ver="$(installed_version_of "$after" "$bin" || true)"
                if [[ -n "$new_ver" && "$new_ver" == "$cur_ver" ]]; then
                    ok "$bin is already up to date ($new_ver)"
                elif [[ -n "$cur_ver" && -n "$new_ver" ]]; then
                    ok "$bin updated ($cur_ver → $new_ver)"
                elif [[ -n "$new_ver" ]]; then
                    ok "$bin updated (now $new_ver)"
                else
                    ok "$bin updated"
                fi
            done
        fi
    fi
    (( state_unknown )) && rc=1
    return "$rc"
}

# ── per-verb flows ──────────────────────────────────────────────
# list: read-only table of installed CLIs with current and latest versions.
# The channel's stdout is the data channel, so its warnings stay on stderr and
# reach the user. An empty result means "nothing installed" only when the
# channel succeeded; a failed listing propagates as an error.
do_list() {
    local ch="$1" script internal
    script="$(channel_script "$ch")"
    internal="$(channel_name "$ch")"
    local rows rc=0
    rows="$(bash "$script" --list)" || rc=$?
    if (( rc != 0 )); then
        warn "listing $internal CLIs failed (exit $rc)"
        return 1
    fi
    if [[ -z "$rows" ]]; then
        info "no $internal CLIs found"
        return 0
    fi

    local -a out_pkg=() out_cur=() out_latest=()
    local line pkg cur latest display
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        read -r pkg cur latest <<<"$line"
        if conf_row_for "$ch" "$pkg"; then
            display="$CONF_BIN"
        else
            display="$pkg"
        fi
        out_pkg+=("$display")
        out_cur+=("$cur")
        out_latest+=("$latest")
    done <<<"$rows"
    (( ${#out_pkg[@]} > 0 )) || return 0

    # Widths follow the data: a fixed width misaligns as soon as a name is
    # longer than the guess (unmanaged go tools show module paths).
    local w_pkg=7 w_cur=7 i
    for i in "${!out_pkg[@]}"; do
        (( ${#out_pkg[i]} > w_pkg )) && w_pkg=${#out_pkg[i]}
        (( ${#out_cur[i]} > w_cur )) && w_cur=${#out_cur[i]}
    done

    local width=$((w_pkg + 1)) wv=$((w_cur + 1))
    printf "%-${width}s%-${wv}s%s\n" "package" "version" "latest"
    for i in "${!out_pkg[@]}"; do
        printf "%-${width}s%-${wv}s%s\n" "${out_pkg[i]}" "${out_cur[i]}" "${out_latest[i]}"
    done
}

# install (no pkgs): manifest mode — per-item confirm inside the channel.
do_install_manifest() {
    local ch="$1" script internal
    script="$(channel_script "$ch")"
    internal="$(channel_name "$ch")"
    bash "$script" --install-manifest
}

# update (no pkgs): upgrade everything the channel reports as installed.
# No "which version is latest?" pre-query: eco updates what is there and
# reports the transition it observed. One local read instead of a network round
# trip, and it cannot claim an update that did not happen.
do_update_all() {
    local ch="$1" internal snapshot
    internal="$(channel_name "$ch")"
    snapshot="$(channel_installed "$ch")" || return 1

    TARGET_BINS=()
    TARGET_PKGS=()
    TARGET_FLAGS=()
    local bin ver pkg
    # The snapshot's package column is what the manager must be given and is
    # not always the key (staticcheck lives at honnef.co/.../staticcheck).
    # A registered bin updates through its manifest package; others through
    # the snapshot's.
    while read -r bin ver pkg aliases; do
        [[ -n "$bin" ]] || continue
        if conf_row_for "$ch" "$bin"; then
            TARGET_BINS+=("$bin")
            TARGET_PKGS+=("$CONF_PKG")
            TARGET_FLAGS+=("$CONF_FLAG")
        else
            TARGET_BINS+=("$bin")
            TARGET_PKGS+=("${pkg:-$bin}")
            TARGET_FLAGS+=("")
        fi
    done <<<"$snapshot"

    if (( ${#TARGET_BINS[@]} == 0 )); then
        info "no $internal CLIs are installed; nothing to update"
        return 0
    fi

    SNAPSHOT_BEFORE="$snapshot"
    batch_confirm_and_run update "$ch"
}

# ── main ────────────────────────────────────────────────────────
main() {
    # eco <channel> <verb> [-y|--yes] [-q|--quiet] [-n|--dry-run] [pkg…]
    # -y belongs to the verb it confirms, so it is accepted after the verb and
    # anywhere among the packages. `list` never prompts, so -y and -n there are
    # usage errors rather than silent no-ops; -q only changes output volume.
    ECO_ASSUME_YES=""
    ECO_DRY_RUN=""

    case "${1:-}" in
        -h|--help)
            usage
            return 0
            ;;
    esac

    local ch="${1:-}" verb="${2:-}"

    if [[ -z "$ch" || -z "$verb" ]]; then
        error_msg "missing channel or verb"
        usage >&2
        return 2
    fi

    case "$ch" in
        node|py|go|rust) ;;
        *)
            error_msg "unknown channel '$ch' (choices: node, py, go, rust)"
            usage >&2
            return 2
            ;;
    esac

    case "$verb" in
        list|install|update|uninstall) ;;
        -h|--help)
            usage
            return 0
            ;;
        *)
            error_msg "unknown verb '$verb' (choices: list, install, update, uninstall)"
            usage >&2
            return 2
            ;;
    esac

    shift 2 || true

    # Separate -y from the package list. Everything else that looks like an
    # option is a usage error (exit 2), never a silently ignored argument.
    local -a args=()
    local arg
    for arg in "$@"; do
        case "$arg" in
            -y|--yes)
                if [[ "$verb" == "list" ]]; then
                    error_msg "list takes no options ('$arg')"
                    return 2
                fi
                ECO_ASSUME_YES=1
                ;;
            -q|--quiet)
                ECO_QUIET=1
                ;;
            -n|--dry-run)
                if [[ "$verb" == "list" ]]; then
                    error_msg "list takes no options ('$arg')"
                    return 2
                fi
                ECO_DRY_RUN=1
                ;;
            -*)
                error_msg "unknown option '$arg'"
                usage >&2
                return 2
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done
    # Exported so the channel scripts (and the shared manifest loop they call)
    # see the same decision.
    [[ -n "$ECO_ASSUME_YES" ]] && export ECO_ASSUME_YES
    [[ -n "$ECO_DRY_RUN" ]] && export ECO_DRY_RUN
    [[ -n "${ECO_QUIET:-}" ]] && export ECO_QUIET
    set -- ${args[@]+"${args[@]}"}

    # The manifest is only needed to resolve bin names and for manifest mode,
    # so a broken eco.conf fails loudly exactly where it matters.
    eco_conf_load || return 1

    local internal
    internal="$(channel_name "$ch")"

    local rc=0
    case "$verb" in
        list)
            (( $# == 0 )) || { warn "list takes no arguments"; return 2; }
            do_list "$ch" || rc=$?
            ;;
        install)
            if (( $# == 0 )); then
                # DOTFILES_SKIP_ECOSYSTEM_TOOLS gates the manifest (bootstrap)
                # path only; an explicit named install is never skipped.
                if [[ -n "${DOTFILES_SKIP_ECOSYSTEM_TOOLS:-}" ]]; then
                    info "DOTFILES_SKIP_ECOSYSTEM_TOOLS is set; skipping $internal ecosystem tool install"
                    return 0
                fi
                if (( $(conf_channel_row_count "$ch") == 0 )); then
                    info "no $internal CLIs are declared for this channel; nothing to install"
                    return 0
                fi
                do_install_manifest "$ch" || rc=$?
            else
                resolve_args "$ch" "$@" || return 2
                dedupe_targets
                prune_installed_targets "$ch"
                if (( ${#TARGET_BINS[@]} == 0 )); then
                    info "nothing to install; every requested $internal CLI is already installed"
                    return 0
                fi
                batch_confirm_and_run install "$ch" || rc=$?
            fi
            ;;
        update)
            if (( $# == 0 )); then
                do_update_all "$ch" || rc=$?
            else
                resolve_args "$ch" "$@" || return 2
                dedupe_targets
                batch_confirm_and_run update "$ch" || rc=$?
            fi
            ;;
        uninstall)
            (( $# > 0 )) || {
                error_msg "uninstall requires at least one package"
                usage >&2
                return 2
            }
            resolve_args "$ch" "$@" || return 2
            dedupe_targets
            batch_confirm_and_run uninstall "$ch" || rc=$?
            ;;
    esac
    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

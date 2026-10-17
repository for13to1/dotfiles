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
    echo "usage: eco <node|py|go|rust> <list|install|update|uninstall> [-y] [pkg…]"
    echo ""
    echo "  list                  list installed CLIs with current and latest versions"
    echo "  install [-y] [pkg…]   install missing CLIs; without pkg, manifest mode"
    echo "  update  [-y] [pkg…]   upgrade installed CLIs; without pkg, all of them"
    echo "  uninstall [-y] <pkg…> remove installed CLIs (package names required)"
    echo ""
    echo "  -y, --yes             do not ask for confirmation (not valid for list)"
    echo ""
    echo "Packages are bin names from eco.conf, or raw package names for unmanaged tools."
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

# resolve_args <verb> <channel> [arg…]
# Fills TARGET_BINS / TARGET_PKGS / TARGET_FLAGS.
# An arg matching a conf bin (or pkg) yields that row's pkg+flag; otherwise the
# arg is a raw pkg (flag empty). go uninstall is the exception: a raw pkg's bin
# is the module path's last segment (the binary name Go installs).
#
# A bare name is the only accepted form: `pkg@selector` is refused, because eco
# stores no versions (see pkg_has_selector).
resolve_args() {
    local verb="$1" ch="$2"
    shift 2
    TARGET_BINS=()
    TARGET_PKGS=()
    TARGET_FLAGS=()
    local arg
    for arg in "$@"; do
        if pkg_has_selector "$arg"; then
            error_msg "version selectors are not supported: '$arg'"
            info "eco installs and updates whatever the package manager resolves;"
            info "use 'eco <ch> list' to see the installed versions."
            return 1
        fi
        if conf_row_for "$ch" "$arg"; then
            TARGET_BINS+=("$CONF_BIN")
            TARGET_PKGS+=("$CONF_PKG")
            TARGET_FLAGS+=("$CONF_FLAG")
        else
            if [[ "$verb" == "uninstall" && "$ch" == "go" ]]; then
                TARGET_BINS+=("${arg##*/}")
            else
                TARGET_BINS+=("$arg")
            fi
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
    local ch="$1" internal detect i path
    internal="$(channel_name "$ch")"
    detect="$(channel_detect "$internal")"
    local -a kb=() kp=() kf=()
    for i in "${!TARGET_BINS[@]}"; do
        path="$CLI_BIN_DIR/${TARGET_BINS[i]}"
        if [[ "$detect" == "path" ]]; then
            if is_installed "${TARGET_BINS[i]}" "$path"; then
                info "${TARGET_BINS[i]} already installed; skipping"
                continue
            fi
        elif [[ -x "$path" ]]; then
            info "${TARGET_BINS[i]} already installed; skipping"
            continue
        fi
        # A stale placeholder is not "installed" (is_installed says no) yet
        # still blocks a fresh install (EEXIST / "executable already exists"),
        # so clear it the same way the manifest path does.
        clean_stale_installs "$path"
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
# channel_installed <channel> — local-only "bin version" rows, no network.
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

# installed_version_of <snapshot> <bin> — look up one bin's version.
installed_version_of() {
    local snapshot="$1" want="$2" bin ver
    while read -r bin ver; do
        [[ -n "$bin" ]] || continue
        if [[ "$bin" == "$want" ]]; then
            printf '%s\n' "$ver"
            return 0
        fi
    done <<<"$snapshot"
    return 1
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

# prune_absent_targets <verb> <internal> <snapshot>
# Keep only targets the channel reports as installed. update and uninstall both
# demand that: saying "ghost updated" about a package that was never installed
# is the same lie as reporting a removal that did not happen.
prune_absent_targets() {
    local verb="$1" internal="$2" snapshot="$3" i bin
    local -a kb=() kp=() kf=()
    for i in "${!TARGET_BINS[@]}"; do
        bin="${TARGET_BINS[i]}"
        if installed_version_of "$snapshot" "$bin" >/dev/null; then
            kb+=("$bin")
            kp+=("${TARGET_PKGS[i]}")
            kf+=("${TARGET_FLAGS[i]}")
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
        prune_absent_targets "$verb" "$internal" "$before"
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
    [[ "$verb" == "update" ]] && show_current_versions "$internal" "$before"

    if [[ -n "${ECO_ASSUME_YES:-}" ]] \
       || confirm "$prompt_verb $count via $internal? [y/N]: " 0; then
        auth_bins=("${TARGET_BINS[@]}")
        auth_pkgs=("${TARGET_PKGS[@]}")
        auth_flags=("${TARGET_FLAGS[@]}")
    else
        info "declined $count $internal CLI(s); nothing was $done_w"
        return 0
    fi

    local after="" rc=0 one_rc
    for i in "${!auth_bins[@]}"; do
        local bin="${auth_bins[i]}" new_ver
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

        case "$verb" in
            update)
                # Re-read instead of predicting: the right-hand side is what
                # actually got installed, not a version eco guessed earlier.
                local cur_ver
                cur_ver="$(installed_version_of "$before" "$bin" || true)"
                after="$(channel_installed "$ch")" || after=""
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
                ;;
            uninstall)
                # Trust the filesystem, not the exit code: npm reports success
                # for a package that was never there.
                after="$(channel_installed "$ch")" || after=""
                if installed_version_of "$after" "$bin" >/dev/null; then
                    error_msg "$bin was not removed (still installed)"
                    rc=1
                else
                    ok "$bin uninstalled"
                fi
                ;;
            *)
                ok "$bin $done_w"
                ;;
        esac
    done
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
    local bin ver
    while read -r bin ver; do
        [[ -n "$bin" ]] || continue
        # A bin the manifest knows is updated through its package; an unmanaged
        # bin is updated by its own name.
        if conf_row_for "$ch" "$bin"; then
            TARGET_BINS+=("$bin")
            TARGET_PKGS+=("$CONF_PKG")
            TARGET_FLAGS+=("$CONF_FLAG")
        else
            TARGET_BINS+=("$bin")
            TARGET_PKGS+=("$bin")
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
    # eco <channel> <verb> [-y|--yes] [pkg…]
    # -y belongs to the verb it confirms, so it is accepted after the verb and
    # anywhere among the packages. `list` never prompts, so -y there is a usage
    # error rather than a silent no-op.
    ECO_ASSUME_YES=""

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
                resolve_args install "$ch" "$@" || return 1
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
                resolve_args update "$ch" "$@" || return 1
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
            resolve_args uninstall "$ch" "$@" || return 1
            dedupe_targets
            batch_confirm_and_run uninstall "$ch" || rc=$?
            ;;
    esac
    return "$rc"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

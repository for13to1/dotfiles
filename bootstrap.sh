#!/usr/bin/env bash
#
# bootstrap.sh — one-shot development environment bootstrap
# Usage: git clone https://github.com/for13to1/dotfiles.git ~/dotfiles
#        cd ~/dotfiles && bash bootstrap.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# ── Shared infrastructure (colored output etc., see _scripts/common.sh) ─
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_scripts/common.sh"

# ── 1. Detect the operating system ──────────────────────────────
OS="$(uname -s)"
info "Detected OS: $OS"

# ── 2. Software installation ───────────────────────────────────
# ── Optional-group hint: list all groups except "default" for a platform ──
hint_optional_groups() {
    local platform="$1"
    local groups=() _f _t
    for _f in "$DOTFILES_DIR/_install/$platform"/*.group; do
        [[ -f "$_f" ]] || continue
        _t="$(basename "$_f")"
        [[ "$_t" == "default.group" ]] && continue
        groups+=("${_t%.group}")
    done
    if (( ${#groups[@]} > 0 )); then
        info "💡 Optional groups: bash _install/install --$platform ${groups[*]}"
    fi
}

case "$OS" in
    Darwin*)
        info "🍎 macOS environment, starting setup..."

        # Detect Xcode tooling: prefer a full Xcode.app, otherwise install the slim CLT.
        if [[ -d "/Applications/Xcode.app" ]]; then
            # Full Xcode is present; verify xcodebuild is reachable.
            if ! xcodebuild -version &>/dev/null; then
                info "Xcode.app detected but xcode-select does not point to it; switching..."
                sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
            fi
            ok "Xcode.app ready"
        elif ! xcode-select -p &>/dev/null; then
            # Neither full Xcode nor CLT is installed: install the slim CLT.
            info "Xcode.app not found; installing Command Line Tools..."
            xcode-select --install
            echo "Click \"Install\" in the dialog, then rerun this script."
            exit 0
        else
            ok "Xcode Command Line Tools ready"
        fi

        if [[ -f "$DOTFILES_DIR/zsh/.zsh.d/brew_mirror.sh" ]]; then
            # shellcheck disable=SC1091
            source "$DOTFILES_DIR/zsh/.zsh.d/brew_mirror.sh"
        else
            error "brew_mirror.sh not found"
        fi

        # Ask whether to use a mirror to speed up package downloads.
        echo ""
        info "🌍 Homebrew mirror selection:"
        echo "   1) Tsinghua (TUNA) - [default]"
        echo "   2) USTC"
        echo "   3) Aliyun"
        echo "   4) Skip (use official sources)"
        mirror_choice="$(ask_value "Enter a number [1-4]: " "1")"

        SELECTED_MIRROR=""
        case "$mirror_choice" in
            1) SELECTED_MIRROR="tuna" ;;
            2) SELECTED_MIRROR="ustc" ;;
            3) SELECTED_MIRROR="ali"  ;;
            *) SELECTED_MIRROR=""     ;;
        esac

        if [[ -n "$SELECTED_MIRROR" ]]; then
            brew_mirror -q "$SELECTED_MIRROR"
            ok "Temporarily set the $SELECTED_MIRROR mirror to speed up installation"
        elif command -v brew &>/dev/null; then
            brew_mirror -q reset
            ok "Reset to the official Homebrew sources"
        else
            info "Using the official Homebrew sources by default"
        fi

        # Install Homebrew if missing.
        if ! command -v brew &>/dev/null; then
            info "Installing Homebrew..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            # Apple Silicon needs the PATH set manually.
            if [[ "$(uname -m)" == "arm64" ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            fi
        fi
        ok "Homebrew ready"

        # Ensure the hard script dependency is installed.
        if ! command -v stow &>/dev/null; then
            info "Installing stow..."
            brew install stow
        fi

        # Install the default group.
        info "Updating Homebrew and installing the default group..."
        brew update || warn "Homebrew index update did not fully complete; continuing with the install..."
        if bash "$DOTFILES_DIR/_install/install" --brew; then
            ok "Default group installed"
        else
            warn "Some packages in the default group failed; run 'bash _install/install --brew' later to retry"
        fi
        hint_optional_groups brew

        # Apply macOS system preferences.
        if [[ -f "$DOTFILES_DIR/_setup/mac/setup.sh" ]]; then
            info "Applying macOS system preferences..."
            bash "$DOTFILES_DIR/_setup/mac/setup.sh"
            ok "macOS preferences applied"
        fi
        ;;

    Linux*)
        info "🐧 Linux environment, starting setup..."

        # Install software by group.
        install_bootstrap_groups() {
            local platform="$1"
            if bash "$DOTFILES_DIR/_install/install" "--$platform"; then
                ok "$platform default group installed"
            else
                warn "Some packages in the $platform default group failed; run 'bash _install/install --$platform' later to retry"
                if confirm "Continue with the remaining setup? [Y/n]: " 1; then
                    warn "Continuing with the remaining setup"
                else
                    error "Stopped bootstrap as requested"
                fi
            fi
        }

        if command -v apt &>/dev/null; then
            info "Updating the apt package index..."
            if ! sudo apt update; then
                warn "apt update failed (possibly a network issue); continuing with cached packages..."
            fi

            # Ensure hard script dependencies are installed (zsh + stow + make).
            if ! command -v zsh &>/dev/null; then
                info "Installing zsh..."
                sudo apt install -y zsh
            fi
            if ! command -v stow &>/dev/null; then
                info "Installing stow..."
                sudo apt install -y stow
            fi
            if ! command -v make &>/dev/null; then
                info "Installing make..."
                sudo apt install -y make
            fi

            install_bootstrap_groups apt
            hint_optional_groups apt

            # Ensure en_US.UTF-8 locale exists to avoid stow/perl locale warnings.
            if command -v locale-gen &>/dev/null \
               && ! locale -a 2>/dev/null | grep -qiE 'en_US\.utf-?8'; then
                info "Generating the en_US.UTF-8 locale..."
                sudo locale-gen en_US.UTF-8 \
                    || warn "Generation failed; you can run 'sudo locale-gen en_US.UTF-8' later"
            fi
        elif command -v pacman &>/dev/null; then
            if [[ -n "${DOTFILES_NON_INTERACTIVE:-}" ]]; then
                sudo pacman -Syu --noconfirm
            else
                sudo pacman -Syu
            fi

            # Ensure hard script dependencies are installed (zsh + stow + make).
            if ! command -v zsh &>/dev/null; then
                info "Installing zsh..."
                sudo pacman -S --noconfirm zsh
            fi
            if ! command -v stow &>/dev/null; then
                info "Installing stow..."
                sudo pacman -S --noconfirm stow
            fi
            if ! command -v make &>/dev/null; then
                info "Installing make..."
                sudo pacman -S --noconfirm make
            fi

            install_bootstrap_groups pacman
            hint_optional_groups pacman
        else
            warn "Unrecognized Linux package manager; please install zsh and required tools manually"
        fi

        # Only on Debian-like platforms do we use these ecosystem channels (the
        # distro repos ship stale tool versions there); macOS and Arch use their own.
        if is_debian_like; then
            for installer in install-by-curl.sh install-by-npm.sh install-by-uv.sh install-by-cargo.sh; do
                if [[ -f "$DOTFILES_DIR/_install/$installer" ]]; then
                    bash "$DOTFILES_DIR/_install/$installer"
                fi
            done
            unset installer
        fi
        ;;

    *)
        error "Unsupported OS: $OS"
        ;;
esac

# ── 3-5. Host base configuration ────────────────────────────────
bash "$DOTFILES_DIR/_bootstrap/ssh.sh"
bash "$DOTFILES_DIR/_bootstrap/git.sh" "$DOTFILES_DIR"
bash "$DOTFILES_DIR/_bootstrap/shell.sh" "$OS" "${SELECTED_MIRROR:-}"

# ── 6. Mount configuration files (Stow) ─────────────────────────
info "Mounting configuration files with Stow..."

## 1. Resolve the module list (single source of truth, see _scripts/modules.conf).
# The module list is emitted one module per line and read into an array.
STOW_MODULES=()
if [[ -f "$DOTFILES_DIR/_scripts/modules.conf" && -f "$DOTFILES_DIR/_scripts/list-modules.sh" ]]; then
    # macOS ships bash 3.2 without mapfile, so use a while-read loop.
    while IFS= read -r _module; do
        STOW_MODULES+=("$_module")
    done < <(bash "$DOTFILES_DIR/_scripts/list-modules.sh" "$DOTFILES_DIR/_scripts/modules.conf")
    unset _module
fi

if (( ${#STOW_MODULES[@]} == 0 )); then
    warn "No modules found in _scripts/modules.conf; nothing to mount"
else
    info "Loaded modules from _scripts/modules.conf: ${STOW_MODULES[*]}"
fi

## 2. Run the Stow mount.
# The single entry point handles preflight, conflict backup, shared dir creation,
# `stow -R`, and post-mount verification. Mount failures only warn, never block.
if bash "$DOTFILES_DIR/_scripts/stow-sync.sh" \
    "$DOTFILES_DIR" "$HOME" "${STOW_MODULES[@]}"; then
    ok "Stow configuration mounted"
else
    warn "Stow mount had failures (see errors above); run 'make sync' later to fix"
fi

# ── 7. Sync tmux plugins (tpm) ──────────────────────────────────
echo ""
info "Syncing tmux plugins (tpm)..."
if bash "$DOTFILES_DIR/_scripts/tmux-plugins.sh"; then
    ok "tmux plugins ready"
else
    warn "tmux plugin sync had errors; run 'bash _scripts/tmux-plugins.sh' later to retry"
fi

# ── 8. Sync editor plugins ──────────────────────────────────────
echo ""
bash "$DOTFILES_DIR/_bootstrap/editors.sh"

# ── 9. Deploy custom scripts ────────────────────────────────────
bash "$DOTFILES_DIR/_bootstrap/tools.sh" "$DOTFILES_DIR"

# ── 10. Done ────────────────────────────────────────────────────
echo ""
ok "🎉 All done! Restart your terminal or run 'source ~/.zshrc' to apply the config."
echo ""

#!/usr/bin/env bash
# _bootstrap/pkg-linux.sh — Linux package managers (apt, pacman) setup
# Usage: pkg-linux.sh [dotfiles_dir]

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"


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

main() {
    local repo_dir="${1:-$DOTFILES_DIR}"
    local resolved_dir=""

    resolved_dir="$(dotfiles_dir "$repo_dir")" || error "Cannot access dotfiles dir: $repo_dir"
    DOTFILES_DIR="$resolved_dir"

    info "🐧 Linux environment, starting setup..."

    if command -v apt &>/dev/null; then
        # Ensure the universe repository is enabled on Ubuntu (required for eza, 7zip, etc.).
        if command -v add-apt-repository &>/dev/null; then
            sudo add-apt-repository -y universe &>/dev/null || true
        fi

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
        hint_optional_groups apt "$DOTFILES_DIR"

        # apt lacks fnm/rustup/uv; fill the gap with their official
        # installers. (brew/pacman provide them via default groups, so only
        # apt runs this single script; it skips anything already installed.)
        if [[ -f "$DOTFILES_DIR/_install/install-by-curl.sh" \
              && -z "${DOTFILES_SKIP_ECOSYSTEM_TOOLS:-}" ]]; then
            if bash "$DOTFILES_DIR/_install/install-by-curl.sh"; then
                ok "fnm/rustup/uv installed"
            else
                warn "fnm/rustup/uv install failed; run 'bash _install/install-by-curl.sh' later to retry"
                if confirm "Continue with the remaining setup? [Y/n]: " 1; then
                    warn "Continuing with the remaining setup"
                else
                    error "Stopped bootstrap as requested"
                fi
            fi
        fi

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
        hint_optional_groups pacman "$DOTFILES_DIR"
    else
        warn "Unrecognized Linux package manager; please install zsh and required tools manually"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

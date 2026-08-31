#!/usr/bin/env bash
# _install/install-by-cargo.sh — Rust CLI installs via Cargo (reserved backup channel)

set -euo pipefail

SCRIPT_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../_scripts/common.sh"

# Reserved backup channel; no tools enabled. stylua moved to the npm prebuilt
# distribution (@johnnymorganz/stylua-bin). When a cargo-only Rust CLI (no
# prebuilt distribution) is needed, add this script to install_ecosystem_tools
# — cargo is a platform-neutral channel, like npm/uv.

main() {
    warn "install-by-cargo.sh is a reserved backup channel with no tools enabled"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

#!/usr/bin/env bash
#
# list-modules.sh — read the Stow module list
# Usage: list-modules.sh <modules.conf>
# Blank lines, comment lines starting with #, and trailing comments are ignored;
# each line yields its first field as the module name.
#

set -euo pipefail

conf="${1:?usage: list-modules.sh <modules.conf>}"
[[ -r "$conf" ]] || exit 0

awk 'NF && $1 !~ /^#/ { print $1 }' "$conf"

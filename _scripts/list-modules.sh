#!/usr/bin/env bash
#
# list-modules.sh — 读取 Stow 模块列表
# 用法: list-modules.sh <modules.conf>
# 空行、# 开头的注释行和行尾注释都会被忽略；每行取第一个字段作为模块名。
#

set -euo pipefail

conf="${1:?usage: list-modules.sh <modules.conf>}"
[[ -r "$conf" ]] || exit 0

awk 'NF && $1 !~ /^#/ { print $1 }' "$conf"

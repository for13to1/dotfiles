#!/bin/bash
# Homebrew installer for dotfiles
#
# Usage:
#   ./brew-install.sh              # 只装必备项 (Brewfile.essential)
#   ./brew-install.sh --all        # 全量安装 (Brewfile)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "${1:-}" == "--all" ]]; then
  echo "📦 全量安装 (Brewfile)..."
  brew bundle --file="$SCRIPT_DIR/Brewfile"
else
  echo "📦 安装必备项 (Brewfile.essential)..."
  brew bundle --file="$SCRIPT_DIR/Brewfile.essential"
  echo ""
  echo "💡 其余软件请参考 Brewfile 按需手动安装，或运行 ./brew-install.sh --all 全量安装"
fi

echo "✅ 完成"

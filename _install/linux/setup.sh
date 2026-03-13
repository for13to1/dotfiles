#!/usr/bin/env bash
# _install/linux/setup.sh — Linux 系统级优化脚本

# 可以在这里添加特定于 Linux 的配置，例如：
# 1. 自动安装 fnm/rustup (如果 apt 没装)
# 2. 系统别名、内核参数调整等

# ── 彩色输出 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
error() { echo -e "${RED}❌ $*${NC}"; exit 1; }

# 示例：安装 fnm (如果不存在)
if ! command -v fnm &>/dev/null; then
    info "Linux 环境下未检测到 fnm，建议通过 curl 安装以通过 .zshrc 自动加载"
    # curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

# 示例：安装 rustup
if ! command -v rustup &>/dev/null && ! command -v rustc &>/dev/null; then
    info "Linux 环境下未检测到 Rust，建议运行: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
fi

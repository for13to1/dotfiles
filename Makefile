# Dotfiles 管理方案
# 需要被 Stow 挂载的核心模块列表。
#
# 使用默认折叠行为：stow 会将目录折叠为软链接，即 ~/.zsh.d 、~/.agents 、~/.config/nvim
# 各自作为一条软链接指向 dotfiles 里的对应目录。
# ~/.config 是系统共享目录，由 mkdir -p 确保存在，使 stow 折叠停在 nvim 这一层而不是 .config 层。

SHELL := /bin/bash
MODULES := agents codestyle zsh git vim nvim tmux ripgrep

.PHONY: sync check help

# 默认一键同步：Restow 所有模块
sync:
	@mkdir -p $(HOME)/.config
	@echo "正在同步模块: $(MODULES) ..."
	@stow -R $(MODULES)
	@echo "同步完成！"

# 验证所有模块的软链接是否已正确建立
check:
	@echo "正在检查软链接状态..."; \
	failed=0; \
	verify() { \
		local mod="$$1" entry="$$2"; \
		local rel="$${entry#$$mod/}"; \
		[ -z "$$rel" ] && rel="$$(basename "$$entry")"; \
		local target="$$HOME/$$rel"; \
		local src="$$(pwd)/$$entry"; \
		if [ -L "$$target" ]; then \
			local link=$$(readlink "$$target"); \
			local resolved; \
			resolved=$$(cd "$$(dirname "$$target")" && cd "$$link" 2>/dev/null && pwd -P); \
			if [ -z "$$resolved" ]; then \
				resolved="$$(cd "$$(dirname "$$target")" && cd "$$(dirname "$$link")" 2>/dev/null && pwd -P)/$$(basename "$$link")"; \
			fi; \
			resolved="$${resolved%/}"; \
			[ "$$resolved" = "$$src" ] && return 0; \
			echo "  ❌ $$rel → 软链接指向错误"; return 1; \
		fi; \
		if [ ! -e "$$target" ]; then \
			echo "  ❌ $$rel → 软链接缺失"; return 1; \
		fi; \
		if [ -d "$$entry" ] && [ -d "$$target" ]; then \
			while IFS= read -r -d '' sub; do \
				verify "$$mod" "$$sub" || return 1; \
			done < <(find "$$entry" -mindepth 1 -maxdepth 1 \
				! -name '__pycache__' ! -name '.pytest_cache' ! -name '.ruff_cache' \
				! -name '.stow-local-ignore' ! -name '.DS_Store' ! -name '.git' \
				! -name '.gitignore' ! -name 'history.json' -print0 2>/dev/null); \
			return 0; \
		fi; \
		echo "  ❌ $$rel → 存在但不是正确软链接"; return 1; \
	}; \
	for mod in $(MODULES); do \
		if [ ! -d "$$mod" ]; then \
			echo "  ⚠️  模块目录不存在: $$mod"; failed=1; continue; \
		fi; \
		errors=0; \
		while IFS= read -r -d '' entry; do \
			verify "$$mod" "$$entry" || errors=$$((errors + 1)); \
		done < <(find "$$mod" -mindepth 1 -maxdepth 1 \
			! -name '__pycache__' ! -name '.pytest_cache' ! -name '.ruff_cache' \
			! -name '.stow-local-ignore' ! -name '.DS_Store' ! -name '.git' \
			! -name '.gitignore' ! -name 'history.json' -print0 2>/dev/null); \
		if [ $$errors -eq 0 ]; then echo "  ✅ $$mod"; \
		else failed=1; fi; \
	done; \
	if [ $$failed -eq 0 ]; then echo "全部检查通过！"; \
	else echo "存在异常，请运行 make sync 修复。"; exit 1; fi


# 简易帮助说明
help:
	@echo "可用命令:"
	@echo "  make sync   - 一键刷新并重新挂载所有核心模块"
	@echo "  make check  - 验证所有模块的软链接是否正确建立"
	@echo "  make help   - 显示此帮助信息"

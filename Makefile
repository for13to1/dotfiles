# Dotfiles 管理方案
# 记录需要被 Stow 挂载的核心模块

MODULES := agents codestyle zsh git vim nvim tmux

.PHONY: sync check help

# 默认一键同步：Restow 所有模块
sync:
	@echo "正在同步模块: $(MODULES) ..."
	@stow -R $(MODULES)
	@echo "同步完成！"

# 验证所有模块的软链接是否已正确建立
check:
	@echo "正在检查软链接状态..."
	@rm -f .check_failed; \
	for mod in $(MODULES); do \
		if [ ! -d "$$mod" ]; then \
			echo "  ⚠️  模块目录不存在: $$mod"; touch .check_failed; continue; \
		fi; \
		find "$$mod" -mindepth 1 -not -path '*/.git/*' \( -type f -o -type d \) | while IFS= read -r f; do \
			rel=$${f#$$mod/}; \
			target="$$HOME/$$rel"; \
			if [ -L "$$target" ] && [ "$$(readlink -f "$$target")" = "$$(pwd)/$$f" ]; then \
				echo "  ✅ $$rel"; \
			elif [ -e "$$target" ]; then \
				echo "  ❌ $$rel → 目标存在但不是正确的软链接"; touch .check_failed; \
			else \
				echo "  ❌ $$rel → 软链接缺失"; touch .check_failed; \
			fi; \
		done; \
	done; \
	if [ ! -f .check_failed ]; then \
		echo "全部检查通过！"; \
	else \
		echo "存在异常，请运行 make sync 修复。"; \
		rm -f .check_failed; \
		exit 1; \
	fi

# 简易帮助说明
help:
	@echo "可用命令:"
	@echo "  make sync   - 一键刷新并重新挂载所有核心模块"
	@echo "  make check  - 验证所有模块的软链接是否正确建立"
	@echo "  make help   - 显示此帮助信息"

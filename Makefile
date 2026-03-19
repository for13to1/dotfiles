# Dotfiles 管理方案
# 记录需要被 Stow 挂载的核心模块

MODULES := agents codestyle zsh git vim nvim

.PHONY: sync help

# 默认一键同步：Restow 所有模块
sync:
	@echo "正在同步模块: $(MODULES) ..."
	@stow -R $(MODULES)
	@echo "同步完成！"

# 简易帮助说明
help:
	@echo "可用命令:"
	@echo "  make sync    - 一键刷新并重新挂载所有核心模块"
	@echo "  make help    - 显示此帮助信息"

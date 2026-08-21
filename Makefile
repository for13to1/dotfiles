# Dotfiles 管理方案
# 需要被 Stow 挂载的核心模块列表见 _scripts/modules.conf（与 bootstrap.sh 共用的真值源）。
#
# 使用默认折叠行为：stow 会将目录折叠为软链接，即 ~/.zsh.d 、~/.agents 、~/.config/nvim
# 各自作为一条软链接指向 dotfiles 里的对应目录。
# ~/.config 是系统共享目录，由 mkdir -p 确保存在，使 stow 折叠停在 nvim 这一层而不是 .config 层。

SHELL := /bin/bash
# 解析规则见 _scripts/list-modules.sh，Makefile 与 bootstrap.sh 共用同一实现。
MODULES := $(shell bash _scripts/list-modules.sh _scripts/modules.conf)

.PHONY: sync check doctor test help

# 默认一键同步：Restow 所有模块
sync:
	@bash _scripts/stow-sync.sh "$(CURDIR)" "$(HOME)" $(MODULES)

# 验证所有模块的软链接是否已正确建立
check:
	@bash _scripts/check-links.sh verify "$(CURDIR)" "$(HOME)" $(MODULES)

doctor:
	@bash _scripts/doctor.sh "$(CURDIR)" "$(HOME)"

test:
	@if command -v shellcheck >/dev/null 2>&1; then \
		find . -type f -name '*.sh' -not -path './.git/*' -not -path './agents/*' -not -path './_install/scratch/*' -exec shellcheck {} + ; \
		shellcheck _scripts/hooks/pre-push; \
	else \
		echo "❌ shellcheck 未安装，无法运行完整测试" >&2; \
		exit 1; \
	fi
	@find . -type f -name '*.sh' -not -path './.git/*' -not -path './agents/*' -not -path './_install/scratch/*' -exec bash -n {} \;
	@set -e; for t in _tests/test-*.sh; do bash "$$t"; done
	@python3 agents/.agents/skills/commit-summarizer/scripts/test_analyze_staged.py
	@python3 agents/.agents/skills/script-analyzer/scripts/test_analyze.py
	@if [ -x agents/.agents/skills/pdf2md-polish/.venv/bin/python ] \
	    && agents/.agents/skills/pdf2md-polish/.venv/bin/python -m pytest --version >/dev/null 2>&1; then \
		agents/.agents/skills/pdf2md-polish/.venv/bin/python -m pytest -q agents/.agents/skills/pdf2md-polish/test_polish.py; \
	elif command -v pytest >/dev/null 2>&1; then \
		pytest -q agents/.agents/skills/pdf2md-polish/test_polish.py; \
	elif command -v uv >/dev/null 2>&1; then \
		uv run --offline --with pytest pytest -q agents/.agents/skills/pdf2md-polish/test_polish.py \
		|| uv run --with pytest pytest -q agents/.agents/skills/pdf2md-polish/test_polish.py; \
	else \
		echo "❌ pytest 与 uv 均未安装，无法运行 pdf2md-polish 测试" >&2; \
		exit 1; \
	fi


# 简易帮助说明
help:
	@echo "可用命令:"
	@echo "  make sync   - 一键刷新并重新挂载所有核心模块"
	@echo "  make check  - 验证所有模块的软链接是否正确建立"
	@echo "  make doctor - 诊断本机 dotfiles 环境状态"
	@echo "  make test   - 运行 shell 静态检查、Stow 行为测试与 skill Python 测试"
	@echo "  make help   - 显示此帮助信息"

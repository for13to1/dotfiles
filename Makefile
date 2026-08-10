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
	@command -v shellcheck >/dev/null || { echo "shellcheck 未安装，请先安装 shellcheck"; exit 1; }
	@shellcheck bootstrap.sh \
		_install/linux/curl-install.sh \
		_install/linux/npm-install.sh \
		_install/mac/brew-install.sh \
		_setup/mac/setup.sh \
		_scripts/common.sh \
		_scripts/hooks/pre-push \
		_scripts/list-modules.sh \
		_scripts/check-links.sh \
		_scripts/doctor.sh \
		_scripts/stow-sync.sh \
		_scripts/test-check-links.sh \
		_scripts/test-doctor.sh \
		_scripts/test-proj-setup.sh \
		_scripts/test-stow-sync.sh \
		proj-setup/bin/proj-setup.sh \
		zsh/.zsh.d/brew_mirror.sh
	@find . -type f -name '*.sh' -not -path './.git/*' -exec bash -n {} \;
	@bash _scripts/test-check-links.sh
	@bash _scripts/test-doctor.sh
	@bash _scripts/test-proj-setup.sh
	@bash _scripts/test-stow-sync.sh


# 简易帮助说明
help:
	@echo "可用命令:"
	@echo "  make sync   - 一键刷新并重新挂载所有核心模块"
	@echo "  make check  - 验证所有模块的软链接是否正确建立"
	@echo "  make doctor - 诊断本机 dotfiles 环境状态"
	@echo "  make test   - 运行 shell 静态检查与 Stow 行为测试"
	@echo "  make help   - 显示此帮助信息"

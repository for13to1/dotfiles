# Dotfiles management scheme
# The core module list to Stow lives in _scripts/modules.conf (shared source of truth
# with bootstrap.sh).
#
# Use the default folding behavior: stow folds directories into symlinks, so ~/.zsh.d,
# ~/.agents, ~/.config/nvim, and ~/.config/git each become a single symlink into the
# dotfiles repo. ~/.config is a system-shared dir ensured by mkdir -p, so stow folding
# stops at the nvim/git level rather than the .config level.

SHELL := /bin/bash
# Parsing rules live in _scripts/list-modules.sh; Makefile and bootstrap.sh share this impl.
MODULES := $(shell bash _scripts/list-modules.sh _scripts/modules.conf)

.PHONY: sync check doctor test lint-shell test-shell test-skills skills-attach skills-detach skills-update skills-list help

# Default one-shot sync: restow all modules.
sync:
	@bash _scripts/stow-sync.sh "$(CURDIR)" "$(HOME)" $(MODULES)

# Verify every module's symlinks are correctly created.
check:
	@bash _scripts/check-links.sh verify "$(CURDIR)" "$(HOME)" $(MODULES)

doctor:
	@bash _scripts/doctor.sh "$(CURDIR)" "$(HOME)"

test: lint-shell test-shell test-skills

lint-shell:
	@set -e; if command -v shellcheck >/dev/null 2>&1; then \
		find . -type f -name '*.sh' -not -path './.git/*' -not -path './agents/*' -not -path './_vendor/*' -not -path './_install/installer/*' -exec shellcheck {} + ; \
		shellcheck _scripts/hooks/pre-push; \
	else \
		echo "❌ shellcheck not installed; cannot run the full test suite" >&2; \
		exit 1; \
	fi

test-shell:
	@find . -type f -name '*.sh' -not -path './.git/*' -not -path './agents/*' -not -path './_vendor/*' -not -path './_install/installer/*' -exec bash -n {} \;
	@set -e; for t in _tests/test-*.sh; do bash "$$t"; done

test-skills:
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
		echo "❌ neither pytest nor uv is installed; cannot run pdf2md-polish tests" >&2; \
		exit 1; \
	fi

# Manage pluggable external skills (e.g. make skills-attach, make skills-detach, make skills-list)
skills-attach:
	@bash _scripts/skills-vendor.sh attach $(VENDOR)

skills-detach:
	@bash _scripts/skills-vendor.sh detach $(VENDOR)

skills-update:
	@bash _scripts/skills-vendor.sh update $(VENDOR)

skills-list:
	@bash _scripts/skills-vendor.sh list

# Brief help.
help:
	@echo "Available commands:"
	@echo "  make sync          - restow all core modules"
	@echo "  make check         - verify every module's symlinks"
	@echo "  make doctor        - diagnose the local dotfiles environment"
	@echo "  make test          - run all static checks and behavior tests"
	@echo "  make lint-shell    - run ShellCheck"
	@echo "  make test-shell    - run bash syntax checks and shell behavior tests"
	@echo "  make test-skills   - run the skill Python tests"
	@echo "  make skills-attach - attach external skills from _vendor/ into ~/.agents/skills/"
	@echo "  make skills-detach - detach external skills and restore clean built-in state"
	@echo "  make skills-update - update external submodules to latest upstream"
	@echo "  make skills-list   - list native built-in skills and active attached skills"
	@echo "  make help          - show this help"

# tmux-airline — installation and developer tasks.

.PHONY: install completions check-completions test test-fast test-integration test-layout test-lifecycle test-runner lint

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
BASH_COMPLETION_DIR ?= $(PREFIX)/share/bash-completion/completions
ZSH_COMPLETION_DIR ?= $(PREFIX)/share/zsh/site-functions

SHELLCHECK_SOURCES := airline airline.sh airline.tmux scripts/generate-completions \
	completions/airline.bash \
	$(wildcard lib/*.sh adapters/* classifiers/* filters/* helpers/* layouts/* probes/* runners/*)

install: check-completions
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 airline "$(DESTDIR)$(BINDIR)/airline"
	install -d "$(DESTDIR)$(BASH_COMPLETION_DIR)"
	install -m 644 completions/airline.bash "$(DESTDIR)$(BASH_COMPLETION_DIR)/airline"
	install -d "$(DESTDIR)$(ZSH_COMPLETION_DIR)"
	install -m 644 completions/_airline "$(DESTDIR)$(ZSH_COMPLETION_DIR)/_airline"

completions:
	bash scripts/generate-completions

check-completions:
	@tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT; \
	bash scripts/generate-completions "$$tmp"; \
	diff -u completions/airline.bash "$$tmp/airline.bash"; \
	diff -u completions/_airline "$$tmp/_airline"

test:
	bats test/

test-fast:
	bats test/architecture.bats test/grammar.bats test/completions.bats test/collections.bats \
		test/render.bats test/runner.bats test/lifecycle.bats

test-integration:
	bats test/integration-lifecycle.bats test/layout.bats \
		test/integration-runner.bats test/tmux.bats test/wrapper.bats

test-layout:
	bats test/layout.bats test/render.bats

test-lifecycle:
	bats test/lifecycle.bats test/integration-lifecycle.bats

test-runner:
	bats test/runner.bats test/integration-runner.bats

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck $(SHELLCHECK_SOURCES); \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi
	@echo "architecture lint (DESIGN.md §Enforcement):"
	@test/lint-architecture.sh all

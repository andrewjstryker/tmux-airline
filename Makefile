# tmux-airline — installation and developer tasks.

.PHONY: install completions check-completions test test-fast test-integration test-layout test-session test-runner lint

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
BASH_COMPLETION_DIR ?= $(PREFIX)/share/bash-completion/completions
ZSH_COMPLETION_DIR ?= $(PREFIX)/share/zsh/site-functions

SHELLCHECK_SOURCES := airline airline.sh airline.tmux scripts/generate-completions \
	completions/airline.bash $(wildcard lib/*.sh layouts/adapters/* \
	layouts/definitions/* layouts/helpers/* runners/classifiers/* runners/filters/* \
	runners/probes/* runners/definitions/*)

FAST_TESTS := test/architecture.bats test/cli/grammar.bats test/cli/completions.bats \
	test/core/collections.bats test/core/catalog.bats test/core/render.bats test/runner/behavior.bats \
	test/signal/behavior.bats test/session/behavior.bats test/transaction/behavior.bats
INTEGRATION_TESTS := test/session/integration.bats test/layout/integration.bats \
	test/runner/integration.bats test/core/tmux.bats test/cli/wrapper.bats
ALL_TESTS := $(FAST_TESTS) $(INTEGRATION_TESTS)

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
	bats $(ALL_TESTS)

test-fast:
	bats $(FAST_TESTS)

test-integration:
	bats $(INTEGRATION_TESTS)

test-layout:
	bats test/layout/integration.bats test/core/render.bats

test-session:
	bats test/session/behavior.bats test/session/integration.bats

test-runner:
	bats test/runner/behavior.bats test/runner/integration.bats

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck $(SHELLCHECK_SOURCES); \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi
	@echo "architecture lint (DESIGN.md §Enforcement):"
	@test/lint-architecture.sh all

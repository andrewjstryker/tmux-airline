# tmux-airline — installation and developer tasks.

.PHONY: install test test-fast test-integration test-layout test-lifecycle test-runner lint

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

SHELLCHECK_SOURCES := airline airline.sh airline.tmux $(wildcard lib/*.sh adapters/* classifiers/* filters/* helpers/* layouts/* probes/* runners/*)

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 airline "$(DESTDIR)$(BINDIR)/airline"

test:
	bats test/

test-fast:
	bats test/architecture.bats test/grammar.bats test/collections.bats \
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

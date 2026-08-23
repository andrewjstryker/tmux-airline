# tmux-airline — installation and developer tasks.

.PHONY: install test lint

PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

SHELLCHECK_SOURCES := airline airline.tmux bin/airline $(wildcard *.sh adapters/* helpers/* layouts/*)

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 755 bin/airline "$(DESTDIR)$(BINDIR)/airline"

test:
	bats test/

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck $(SHELLCHECK_SOURCES); \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi
	@echo "architecture lint (DESIGN.md §Enforcement):"
	@test/lint-architecture.sh all

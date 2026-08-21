# tmux-airline — developer tasks.

.PHONY: test lint

SHELLCHECK_SOURCES := airline airline.tmux $(wildcard *.sh adapters/* helpers/* layouts/*)

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

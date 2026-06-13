# tmux-airline — developer tasks.

.PHONY: test lint

test:
	bats test/

lint:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck airline airline.tmux scripts/*.sh scripts/plugins/*.sh; \
	else \
	  echo "shellcheck not installed; skipping"; \
	fi

# tmux-airline — developer tasks.

.PHONY: test lint

test:
	bats test/

lint:
	@command -v shellcheck >/dev/null \
	  && shellcheck airline airline.tmux scripts/*.sh scripts/plugins/*.sh \
	  || echo "shellcheck not installed; skipping"

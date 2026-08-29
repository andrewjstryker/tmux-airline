#!/usr/bin/env bash

# Selective AIRLINE_TMUX shim for process-level failure-contract tests. Every
# unselected command reaches the isolated real tmux server unchanged.

set -u

real_tmux="${AIRLINE_TEST_REAL_TMUX:?need AIRLINE_TEST_REAL_TMUX}"
socket="${AIRLINE_TEST_TMUX_SOCKET:?need AIRLINE_TEST_TMUX_SOCKET}"
mode="${AIRLINE_TEST_TMUX_FAILURE:?need AIRLINE_TEST_TMUX_FAILURE}"
joined=" $* "

case "$mode" in
  acquire)
    [[ "${1:-}" == wait-for && "${2:-}" == -L ]] && exit 71
    ;;
  flush)
    if [[ "${1:-}" == set-option ]]; then
      case "$joined" in
        *' @airline--status-'*|*' @airline--health-'*|*' @airline--problem-'*) exit 72 ;;
      esac
    fi
    ;;
  release)
    if [[ "${1:-}" == set-option && "$joined" == *' -qu '* &&
          "$joined" == *' @airline--transaction-'* ]]; then
      exit 73
    fi
    ;;
esac

exec "$real_tmux" -L "$socket" "$@"

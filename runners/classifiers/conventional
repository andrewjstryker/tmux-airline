#!/usr/bin/env bash
#| summary: Map exit zero to ok, failures to fail, and deliberate stops to no verdict

airline_runner_classify () {   # <exit-status> <signal>
  local status="$1" signal="$2"
  [[ "$signal" != 2 && "$signal" != 15 && "$signal" != INT && "$signal" != TERM ]] || return 0
  if [[ "$status" == 0 && -z "$signal" ]]; then printf 'ok\n'
  elif [[ -n "$signal" ]]; then
    printf 'fail\tcommand terminated by signal %s (status %s)\n' "$signal" "$status"
  else
    printf 'fail\tcommand exited with status %s\n' "$status"
  fi
}

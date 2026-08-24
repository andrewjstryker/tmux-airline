#!/usr/bin/env bash
#
# runner.sh — the program-specific half of airline's process runner.
#
# A runner is trusted shell selected through the registered runner path. It defines:
#
#   airline_runner_classify <exit-status> <signal>
#       Required. Print exactly one of: ok, warn, fail.
#
#   airline_runner_filter <pid> <report-function> [<command> <arg>...]
#       Optional. While <pid> is alive, inspect domain evidence (logs, an API, …)
#       and call <report-function> with the current ok|warn|fail condition whenever
#       useful. The function runs in a background subshell owned by the core.
#
# This layer loads and validates that contract. It has no tmux knowledge and never
# writes airline signals; api.sh owns lifecycle orchestration and projection.

# shellcheck shell=bash

if ! declare -F _condition_level_valid >/dev/null; then
  printf 'runner.sh: load render.sh (and its layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

_runner_impl_reset () {
  unset -f airline_runner_classify airline_runner_filter 2>/dev/null || true
}

# Load one implementation into the current shell. Callers that only need validation
# use this in a subshell so a selection never leaks its functions into later work.
runner_impl_load () {   # <file>
  local file="$1"
  _runner_impl_reset
  # shellcheck source=/dev/null
  source "$file" || return 1
  declare -F airline_runner_classify >/dev/null
}

runner_impl_valid () (   # <file>
  runner_impl_load "$1"
)

# Invoke the loaded terminal classifier and validate its complete output. Returning
# nonzero distinguishes a broken implementation from the job condition it was meant
# to classify.
runner_impl_classify () {   # <exit-status> <signal>
  local condition rc=0
  condition="$(airline_runner_classify "$1" "$2")" || rc=$?
  (( rc == 0 )) || return 1
  _condition_level_valid "$condition" || return 1
  printf '%s' "$condition"
}

runner_impl_has_filter () {
  declare -F airline_runner_filter >/dev/null
}

# Start the loaded filter in a background subshell. The API callback owns validation
# and projection. Store the PID in a caller-visible variable rather than printing it:
# command substitution would put the background process under a throwaway subshell.
AIRLINE_RUNNER_FILTER_PID=""
runner_impl_filter_start () {   # <pid> <report-function> [<command> <arg>...]
  local child_pid="$1" report="$2"; shift 2
  airline_runner_filter "$child_pid" "$report" "$@" &
  # shellcheck disable=SC2034 # consumed by api.sh after this cross-layer call
  AIRLINE_RUNNER_FILTER_PID=$!
}

runner_impl_filter_stop () {   # <filter-pid>
  local pid="${1:-}" rc=0
  [[ -n "$pid" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 0
  fi
  wait "$pid" 2>/dev/null || rc=$?
  return "$rc"
}

# vim: ft=bash

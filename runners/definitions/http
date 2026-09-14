#!/usr/bin/env bash
#| summary: Monitor one or more HTTP endpoints
#| usage: [<http-probe-option>...] [<endpoint>...]
# With no arguments, use local defaults. Otherwise forward probe options and endpoints.

airline_runner_configure () {   # <configure-function> [<http-probe-arg>...]
  local configure="$1"; shift
  local -a probe_args=("$@")
  if (( ${#probe_args[@]} == 0 )); then
    probe_args=(
      http://localhost/health/live
      http://localhost/health/ready
    )
  fi
  "$configure" classify conventional
  "$configure" probe http "${probe_args[@]}"
}

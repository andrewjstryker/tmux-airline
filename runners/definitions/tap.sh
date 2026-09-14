#!/usr/bin/env bash
#| summary: Monitor a TAP-producing test command
#| usage:

airline_runner_configure () {   # <configure-function>
  local configure="$1"; shift
  (( $# == 0 )) || return 2
  "$configure" classify conventional
  "$configure" filter tap
}

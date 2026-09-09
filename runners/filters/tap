#!/usr/bin/env bash
#| summary: Interpret top-level TAP assertions and bailouts
# A small TAP observer: an unsuccessful assertion warns while more tests may run;
# completion with any unsuccessful assertion, or a bailout, fails health.

airline_runner_filter () {   # <pid> <health> <problem>
  local _pid="$1" health="$2" _problem="$3" line message plan="" seen=0 failed=0 final=0
  shopt -s nocasematch

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^Bail[[:space:]]out! ]]; then
      message="${line//$'\t'/ }"
      "$health" airline-tap assertions fail "TAP bailout: $message" || return
      failed=1
      final=1
    elif [[ "$line" =~ ^1\.\.([0-9]+)([[:space:]]|$) ]]; then
      plan="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ ^not[[:space:]]+ok([[:space:]]|$) ]]; then
      (( seen += 1 ))
      if [[ ! "$line" =~ \#[[:space:]]*(TODO|SKIP)([[:space:]]|$) ]]; then
        failed=1
        message="${line//$'\t'/ }"
        "$health" airline-tap assertions warn "TAP assertion failed: $message" || return
      fi
    elif [[ "$line" =~ ^ok([[:space:]]|$) ]]; then
      (( seen += 1 ))
    fi

    if (( failed && ! final )) && [[ -n "$plan" ]] && (( seen >= plan )); then
      "$health" airline-tap assertions fail "TAP stream completed with unsuccessful assertions" || return
      final=1
    fi
  done

  if (( failed && ! final )); then
    "$health" airline-tap assertions fail "TAP stream ended with unsuccessful assertions"
  elif (( ! failed )); then
    "$health" airline-tap assertions ok
  fi
}

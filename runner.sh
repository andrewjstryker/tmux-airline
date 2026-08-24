#!/usr/bin/env bash
#
# runner.sh — contracts and mechanics for runner elements.
#
# Elements are trusted shell selected independently for one invocation:
#
#   classifiers/<name>: airline_runner_classify <exit-status> <signal>
#       Print exactly one of ok|warn|fail.
#       AIRLINE_CLASSIFIER_SUMMARY describes it for `classifier show`.
#
#   filters/<name>: airline_runner_filter <pid> <report-function>
#       Read stdout (or merged stdout/stderr when core requests it) from stdin and
#       call the reporter with ok|warn|fail as evidence changes.
#       AIRLINE_FILTER_SUMMARY describes it for `filter show`.
#
#   probes/<name>: airline_runner_probe <lifecycle-pid> <report-function> [<arg>...]
#       Perform one bounded observation, calling the reporter with ok|warn|fail for
#       each condition. Stdout is uninterpreted user output. Airline reduces reports.
#       AIRLINE_PROBE_SUMMARY and AIRLINE_PROBE_USAGE provide discovery metadata.
#       AIRLINE_RUNNER_PROBE_INTERVAL optionally sets seconds between observations.
#
#   runners/<name>: airline_runner_metadata + airline_runner_configure
#       Declare discovery text and build one normalized monitoring composition by
#       calling core-supplied callbacks. Run uses the full result; watch its subset.
#
# This layer has no tmux knowledge. api.sh resolves elements, owns lifecycle
# composition, and projects normalized reports onto airline signals.

# shellcheck shell=bash

if ! declare -F _condition_level_valid >/dev/null; then
  printf 'runner.sh: load render.sh (and its layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

runner_classifier_load () {   # <file>
  unset -f airline_runner_classify 2>/dev/null || true
  unset AIRLINE_CLASSIFIER_SUMMARY
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_classify >/dev/null || return 1
  [[ -n "${AIRLINE_CLASSIFIER_SUMMARY:-}" ]]
}

runner_classifier_valid () ( runner_classifier_load "$1" )

runner_classifier_run () {   # <exit-status> <signal>
  local condition rc=0
  condition="$(airline_runner_classify "$1" "$2")" || rc=$?
  (( rc == 0 )) || return 1
  _condition_level_valid "$condition" || return 1
  printf '%s' "$condition"
}

runner_filter_load () {   # <file>
  unset -f airline_runner_filter 2>/dev/null || true
  unset AIRLINE_FILTER_SUMMARY
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_filter >/dev/null || return 1
  [[ -n "${AIRLINE_FILTER_SUMMARY:-}" ]]
}

runner_filter_valid () ( runner_filter_load "$1" )

AIRLINE_RUNNER_FILTER_PID=""
runner_filter_start () {   # <pid> <report-function> <input>
  local child_pid="$1" report="$2" input="$3"
  airline_runner_filter "$child_pid" "$report" < "$input" &
  # shellcheck disable=SC2034 # consumed by api.sh after this cross-layer call
  AIRLINE_RUNNER_FILTER_PID=$!
}

runner_filter_wait () {   # <filter-pid>
  local pid="${1:-}" rc=0
  [[ -n "$pid" ]] || return 0
  wait "$pid" 2>/dev/null || rc=$?
  return "$rc"
}

# One selected command stream is tee'd to one filter while remaining visible. In
# merge mode stderr joins stdout before the tee, matching ordinary shell `2>&1`.
AIRLINE_RUNNER_STREAM_DIR=""
AIRLINE_RUNNER_STREAM_INPUT=""
AIRLINE_RUNNER_STREAM_COMMAND=""
AIRLINE_RUNNER_TEE_PID=""

runner_stream_prepare () {
  AIRLINE_RUNNER_STREAM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airline-runner.XXXXXX")" || return 1
  AIRLINE_RUNNER_STREAM_INPUT="$AIRLINE_RUNNER_STREAM_DIR/input"
  AIRLINE_RUNNER_STREAM_COMMAND="$AIRLINE_RUNNER_STREAM_DIR/command"
  mkfifo "$AIRLINE_RUNNER_STREAM_INPUT" "$AIRLINE_RUNNER_STREAM_COMMAND"
}

runner_stream_start () {
  tee "$AIRLINE_RUNNER_STREAM_INPUT" < "$AIRLINE_RUNNER_STREAM_COMMAND" &
  # shellcheck disable=SC2034 # consumed by api.sh after this cross-layer call
  AIRLINE_RUNNER_TEE_PID=$!
}

runner_stream_wait () {
  [[ -n "$AIRLINE_RUNNER_TEE_PID" ]] || return 0
  wait "$AIRLINE_RUNNER_TEE_PID"
}

runner_stream_cleanup () {
  [[ -n "$AIRLINE_RUNNER_STREAM_COMMAND" ]] && rm -f "$AIRLINE_RUNNER_STREAM_COMMAND"
  [[ -n "$AIRLINE_RUNNER_STREAM_INPUT" ]] && rm -f "$AIRLINE_RUNNER_STREAM_INPUT"
  if [[ -n "$AIRLINE_RUNNER_STREAM_DIR" ]]; then
    rmdir "$AIRLINE_RUNNER_STREAM_DIR" 2>/dev/null || true
  fi
  AIRLINE_RUNNER_STREAM_DIR=""
  AIRLINE_RUNNER_STREAM_INPUT=""
  AIRLINE_RUNNER_STREAM_COMMAND=""
  AIRLINE_RUNNER_TEE_PID=""
}

_runner_interval_valid () {   # positive integer or decimal seconds
  local value="$1"
  [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  [[ "${value//[0.]/}" != "" ]]
}

runner_probe_load () {   # <file>
  unset -f airline_runner_probe 2>/dev/null || true
  unset AIRLINE_PROBE_SUMMARY AIRLINE_PROBE_USAGE AIRLINE_RUNNER_PROBE_INTERVAL
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_probe >/dev/null || return 1
  [[ -n "${AIRLINE_PROBE_SUMMARY:-}" ]] || return 1
  [[ -n "${AIRLINE_PROBE_USAGE+x}" ]] || return 1
  _runner_interval_valid "${AIRLINE_RUNNER_PROBE_INTERVAL:-5}"
}

runner_probe_valid () ( runner_probe_load "$1" )

# A probe's stdout belongs to the user. Its reporter is the separate machine
# channel: collect every call made during one observation, validate it, and expose
# the reduced condition through a variable so no control data enters stdout.
AIRLINE_RUNNER_PROBE_REPORTS=()
AIRLINE_RUNNER_PROBE_REPORT_INVALID=""
AIRLINE_RUNNER_PROBE_CONDITION=""

_runner_probe_collect () {   # <ok|warn|fail>
  if (( $# != 1 )); then
    AIRLINE_RUNNER_PROBE_REPORT_INVALID=1
    return 1
  fi
  AIRLINE_RUNNER_PROBE_REPORTS+=("$1")
}

runner_probe_once () {   # <lifecycle-pid> [<arg>...]
  local lifecycle_pid="$1" condition worst=ok rc=0; shift
  AIRLINE_RUNNER_PROBE_REPORTS=()
  AIRLINE_RUNNER_PROBE_REPORT_INVALID=""
  AIRLINE_RUNNER_PROBE_CONDITION=""
  airline_runner_probe "$lifecycle_pid" _runner_probe_collect "$@" || rc=$?
  (( rc == 0 )) || return 1
  [[ -z "$AIRLINE_RUNNER_PROBE_REPORT_INVALID" ]] || return 1
  (( ${#AIRLINE_RUNNER_PROBE_REPORTS[@]} > 0 )) || return 1
  for condition in "${AIRLINE_RUNNER_PROBE_REPORTS[@]}"; do
    _condition_level_valid "$condition" || return 1
    case "$condition" in
      fail) worst=fail ;;
      warn) [[ "$worst" == ok ]] && worst=warn ;;
    esac
  done
  AIRLINE_RUNNER_PROBE_CONDITION="$worst"
}

_runner_probe_loop () {   # <pid> <report-function> <error-function> [<probe-arg>...]
  local lifecycle_pid="$1" report="$2" error="$3" interval
  shift 3
  interval="${AIRLINE_RUNNER_PROBE_INTERVAL:-5}"
  while kill -0 "$lifecycle_pid" 2>/dev/null; do
    if runner_probe_once "$lifecycle_pid" "$@"; then
      "$report" "$AIRLINE_RUNNER_PROBE_CONDITION"
    else
      "$error"
    fi
    kill -0 "$lifecycle_pid" 2>/dev/null || break
    sleep "$interval"
  done
}

AIRLINE_RUNNER_PROBE_PID=""
runner_probe_start () {   # <pid> <report-function> <error-function> [<probe-arg>...]
  _runner_probe_loop "$@" &
  # shellcheck disable=SC2034 # consumed by api.sh after this cross-layer call
  AIRLINE_RUNNER_PROBE_PID=$!
}

runner_probe_stop () {   # <probe-pid>
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
  fi
  wait "$pid" 2>/dev/null || true
}

# A named runner is syntactic composition, not lifecycle machinery. Two required
# functions call validated core callbacks; stdout is never a protocol channel.
runner_definition_load () {   # <file>
  unset -f airline_runner_metadata airline_runner_configure 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_metadata >/dev/null || return 1
  declare -F airline_runner_configure >/dev/null
}

_runner_contract_call () {   # <function> <callback> [<arg>...]; require quiet stdout
  local function="$1" callback="$2" output rc=0; shift 2
  output="$(mktemp "${TMPDIR:-/tmp}/airline-runner-contract.XXXXXX")" || return 1
  "$function" "$callback" "$@" > "$output" || rc=$?
  [[ ! -s "$output" ]] || rc=1
  rm -f "$output"
  return "$rc"
}

AIRLINE_RUNNER_SUMMARY=""
AIRLINE_RUNNER_USAGE=""
AIRLINE_RUNNER_METADATA_INVALID=""
AIRLINE_RUNNER_METADATA_SUMMARY_SEEN=""
AIRLINE_RUNNER_METADATA_USAGE_SEEN=""

_runner_metadata_collect () {   # <summary|usage> <value>
  local field="${1:-}" value="${2:-}"
  if (( $# != 2 )) || [[ "$value" == *$'\n'* ]]; then
    AIRLINE_RUNNER_METADATA_INVALID=1
    return 1
  fi
  case "$field" in
    summary)
      [[ -z "$AIRLINE_RUNNER_METADATA_SUMMARY_SEEN" && -n "$value" ]] || {
        AIRLINE_RUNNER_METADATA_INVALID=1; return 1;
      }
      AIRLINE_RUNNER_METADATA_SUMMARY_SEEN=1
      AIRLINE_RUNNER_SUMMARY="$value"
      ;;
    usage)
      [[ -z "$AIRLINE_RUNNER_METADATA_USAGE_SEEN" ]] || {
        AIRLINE_RUNNER_METADATA_INVALID=1; return 1;
      }
      AIRLINE_RUNNER_METADATA_USAGE_SEEN=1
      AIRLINE_RUNNER_USAGE="$value"
      ;;
    *) AIRLINE_RUNNER_METADATA_INVALID=1; return 1 ;;
  esac
}

runner_definition_metadata () {
  # shellcheck disable=SC2034 # consumed by api.sh after this cross-layer call
  AIRLINE_RUNNER_SUMMARY=""
  # shellcheck disable=SC2034 # consumed by api.sh after this cross-layer call
  AIRLINE_RUNNER_USAGE=""
  AIRLINE_RUNNER_METADATA_INVALID=""
  AIRLINE_RUNNER_METADATA_SUMMARY_SEEN=""
  AIRLINE_RUNNER_METADATA_USAGE_SEEN=""
  _runner_contract_call airline_runner_metadata _runner_metadata_collect || return 1
  [[ -z "$AIRLINE_RUNNER_METADATA_INVALID" ]] || return 1
  [[ -n "$AIRLINE_RUNNER_METADATA_SUMMARY_SEEN" && -n "$AIRLINE_RUNNER_METADATA_USAGE_SEEN" ]]
}

AIRLINE_RUNNER_CONFIG_CLASSIFIER=""
AIRLINE_RUNNER_CONFIG_FILTER=""
AIRLINE_RUNNER_CONFIG_FILTER_MERGE=""
AIRLINE_RUNNER_CONFIG_PROBE=""
AIRLINE_RUNNER_CONFIG_PROBE_ARGS=()
AIRLINE_RUNNER_CONFIG_INVALID=""
AIRLINE_RUNNER_CONFIG_SEEN=""

_runner_configure_collect () {   # <classify|filter|probe> ...
  local field="${1:-}"
  case "$field" in
    classify)
      if (( $# != 2 )) || [[ -n "$AIRLINE_RUNNER_CONFIG_CLASSIFIER" || -z "$2" ]]; then
        AIRLINE_RUNNER_CONFIG_INVALID=1; return 1
      fi
      AIRLINE_RUNNER_CONFIG_CLASSIFIER="$2"
      ;;
    filter)
      if (( $# < 2 || $# > 3 )) || [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER" || -z "$2" ]] || \
        { (( $# == 3 )) && [[ "$3" != merge-stderr ]]; }; then
        AIRLINE_RUNNER_CONFIG_INVALID=1; return 1
      fi
      AIRLINE_RUNNER_CONFIG_FILTER="$2"
      (( $# == 3 )) && AIRLINE_RUNNER_CONFIG_FILTER_MERGE=1
      ;;
    probe)
      if (( $# < 2 )) || [[ -n "$AIRLINE_RUNNER_CONFIG_PROBE" || -z "$2" ]]; then
        AIRLINE_RUNNER_CONFIG_INVALID=1; return 1
      fi
      AIRLINE_RUNNER_CONFIG_PROBE="$2"
      AIRLINE_RUNNER_CONFIG_PROBE_ARGS=("${@:3}")
      ;;
    *) AIRLINE_RUNNER_CONFIG_INVALID=1; return 1 ;;
  esac
  AIRLINE_RUNNER_CONFIG_SEEN=1
}

runner_definition_configure () {   # [<runner-arg>...]
  AIRLINE_RUNNER_CONFIG_CLASSIFIER=""
  AIRLINE_RUNNER_CONFIG_FILTER=""
  AIRLINE_RUNNER_CONFIG_FILTER_MERGE=""
  AIRLINE_RUNNER_CONFIG_PROBE=""
  AIRLINE_RUNNER_CONFIG_PROBE_ARGS=()
  AIRLINE_RUNNER_CONFIG_INVALID=""
  AIRLINE_RUNNER_CONFIG_SEEN=""
  _runner_contract_call airline_runner_configure _runner_configure_collect "$@" || return 1
  [[ -z "$AIRLINE_RUNNER_CONFIG_INVALID" && -n "$AIRLINE_RUNNER_CONFIG_SEEN" ]]
}

AIRLINE_RUNNER_DEFINITION_ARGV=()
runner_definition_project () {   # <run|watch>
  local mode="$1"
  AIRLINE_RUNNER_DEFINITION_ARGV=()
  if [[ "$mode" == run ]]; then
    [[ -n "$AIRLINE_RUNNER_CONFIG_CLASSIFIER" ]] && \
      AIRLINE_RUNNER_DEFINITION_ARGV+=(--classify "$AIRLINE_RUNNER_CONFIG_CLASSIFIER")
    if [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER" ]]; then
      AIRLINE_RUNNER_DEFINITION_ARGV+=(--filter "$AIRLINE_RUNNER_CONFIG_FILTER")
      [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER_MERGE" ]] && \
        AIRLINE_RUNNER_DEFINITION_ARGV+=(--merge-stderr)
    fi
  fi
  if [[ -n "$AIRLINE_RUNNER_CONFIG_PROBE" ]]; then
    AIRLINE_RUNNER_DEFINITION_ARGV+=(
      --probe "$AIRLINE_RUNNER_CONFIG_PROBE" "${AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]}"
    )
  elif [[ "$mode" == watch ]]; then
    return 2
  fi
}

runner_definition_valid () (
  runner_definition_load "$1" && runner_definition_metadata && runner_definition_configure
)

# vim: ft=bash

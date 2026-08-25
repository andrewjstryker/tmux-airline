#!/usr/bin/env bash
#
# runner.sh — runner contracts, mechanics, catalogs, and command orchestration.
#
# Elements are trusted shell selected independently for one invocation:
#
#   runners/classifiers/<name>: airline_runner_classify <exit-status> <signal>
#       Print exactly one of ok|warn|fail.
#       AIRLINE_CLASSIFIER_SUMMARY describes it for `classifier show`.
#
#   runners/filters/<name>: airline_runner_filter <pid> <report-function>
#       Read stdout (or merged stdout/stderr when core requests it) from stdin and
#       call the reporter with ok|warn|fail as evidence changes.
#       AIRLINE_FILTER_SUMMARY describes it for `filter show`.
#
#   runners/probes/<name>: airline_runner_probe <lifecycle-pid> <report-function> [<arg>...]
#       Perform one bounded observation, calling the reporter with ok|warn|fail for
#       each condition. Stdout is uninterpreted user output. Airline reduces reports.
#       AIRLINE_PROBE_SUMMARY and AIRLINE_PROBE_USAGE provide discovery metadata.
#       AIRLINE_RUNNER_PROBE_INTERVAL optionally sets seconds between observations.
#
#   runners/definitions/<name>: airline_runner_metadata + airline_runner_configure
#       Declare discovery text and build one normalized monitoring composition by
#       calling core-supplied callbacks. Run uses the full result; watch its subset.
#
# The contract/mechanics section has no tmux knowledge. The command orchestration
# later in this module reaches tmux only through tmux.sh and projects normalized
# reports onto lifecycle signals.

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
  # shellcheck disable=SC2034 # consumed by runner orchestration below
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
  # shellcheck disable=SC2034 # consumed by runner orchestration below
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
  # shellcheck disable=SC2034 # consumed by runner orchestration below
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
  # shellcheck disable=SC2034 # consumed by runner orchestration below
  AIRLINE_RUNNER_SUMMARY=""
  # shellcheck disable=SC2034 # consumed by runner orchestration below
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

#-----------------------------------------------------------------------------#
# Runner command behavior
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Runner catalogs and ephemeral composition of classifier, filter, and probe elements
#-----------------------------------------------------------------------------#

_runner_element_file () {   # <session> <kind> <bare-name>
  local session="$1" kind="$2" name="$3"
  [[ "$kind" == classify ]] && kind=classifier
  _path_resolve "$session" "$kind" "$name"
}

_runner_element_show () {   # <session> <classifier|filter|probe> <name>
  local session="$1" kind="$2" name="${3:-}" file summary usage="" interval=""
  [[ -n "$name" ]] || die "$kind show: need <name>"
  [[ "$name" != */* ]] || die "$kind show: need a bare name"
  file="$(_path_resolve "$session" "$kind" "$name")"
  [[ -n "$file" ]] || die "$kind show: '$name' not found on the $kind path"
  case "$kind" in
    classifier)
      runner_classifier_load "$file" || die "classifier show: '$name' is invalid"
      summary="$AIRLINE_CLASSIFIER_SUMMARY"
      ;;
    filter)
      runner_filter_load "$file" || die "filter show: '$name' is invalid"
      summary="$AIRLINE_FILTER_SUMMARY"
      ;;
    probe)
      runner_probe_load "$file" || die "probe show: '$name' is invalid"
      summary="$AIRLINE_PROBE_SUMMARY"
      usage="$AIRLINE_PROBE_USAGE"
      interval="${AIRLINE_RUNNER_PROBE_INTERVAL:-5} seconds"
      ;;
  esac
  _show_row name "$name"
  _show_row summary "$summary"
  [[ "$kind" == probe ]] && _show_row arguments "${usage:-none}"
  [[ "$kind" == probe ]] && _show_row interval "$interval"
  _show_row path "$file"
}

_runner_definition_show () {   # <session> <name> [<runner-arg>...]
  local session="$1" name="${2:-}" file probe_args=""; shift 2 || true
  [[ -n "$name" ]] || die "runner show: need <name>"
  [[ "$name" != */* ]] || die "runner show: need a bare name"
  file="$(_path_resolve "$session" runner "$name")"
  [[ -n "$file" ]] || die "runner show: '$name' not found on the runner path"
  runner_definition_load "$file" || die "runner show: '$name' is invalid"
  runner_definition_metadata || die "runner show: '$name' has invalid metadata"
  runner_definition_configure "$@" || die "runner show: '$name' produced an invalid configuration"
  if (( ${#AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]} )); then
    printf -v probe_args '%q ' "${AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]}"
    probe_args="${probe_args% }"
  fi
  _show_row name "$name"
  _show_row summary "$AIRLINE_RUNNER_SUMMARY"
  _show_row arguments "${AIRLINE_RUNNER_USAGE:-none}"
  _show_row classifier "${AIRLINE_RUNNER_CONFIG_CLASSIFIER:-basic}"
  _show_row filter "${AIRLINE_RUNNER_CONFIG_FILTER:-none}"
  [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER_MERGE" ]] && _show_row filter-input merged-stderr
  _show_row probe "${AIRLINE_RUNNER_CONFIG_PROBE:-none}"
  [[ -n "$probe_args" ]] && _show_row probe-args "$probe_args"
  _show_row path "$file"
}

_runner_problem () {   # <session> <key> <ok|warn|fail> [<message>]
  _problem_store "$@" && redraw
  return 0
}

# Globals intentionally cross the filter's background subshell boundary. Each CLI
# invocation owns one run, so concurrent jobs live in separate processes and cannot
# collide here; their tmux contributors are pane-qualified below.
AIRLINE_RUNNER_SESSION=""
AIRLINE_RUNNER_WINDOW=""
AIRLINE_RUNNER_FILTER_KEY=""
AIRLINE_RUNNER_FILTER_PROBLEM=""
AIRLINE_RUNNER_FILTER_LAST=""
AIRLINE_RUNNER_PROBE_KEY=""
AIRLINE_RUNNER_PROBE_PROBLEM=""
AIRLINE_RUNNER_PROBE_LAST=""

_runner_problem_key () {   # <element> <load|classify|filter|probe>
  local name="${1##*/}"
  name="${name//[^a-zA-Z0-9_-]/-}"
  printf 'airline-runner-%s-%s' "$name" "$2"
}

_runner_filter_report () {   # <ok|warn|fail>
  local condition="${1:-}"
  if ! _condition_level_valid "$condition"; then
    _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_FILTER_PROBLEM" fail \
      "runner filter emitted invalid condition '${condition}'"
    return 1
  fi
  _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_FILTER_PROBLEM" ok ""
  [[ "$condition" == "$AIRLINE_RUNNER_FILTER_LAST" ]] && return 0
  AIRLINE_RUNNER_FILTER_LAST="$condition"
  _signal_set health _condition_level_valid ok \
    "$AIRLINE_RUNNER_FILTER_KEY" "$condition" -t "$AIRLINE_RUNNER_WINDOW"
}

_runner_probe_report () {   # <ok|warn|fail>
  local condition="${1:-}"
  if ! _condition_level_valid "$condition"; then
    _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_PROBE_PROBLEM" fail \
      "runner probe emitted invalid condition '${condition}'"
    return 1
  fi
  _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_PROBE_PROBLEM" ok ""
  [[ "$condition" == "$AIRLINE_RUNNER_PROBE_LAST" ]] && return 0
  AIRLINE_RUNNER_PROBE_LAST="$condition"
  _signal_set health _condition_level_valid ok \
    "$AIRLINE_RUNNER_PROBE_KEY" "$condition" -t "$AIRLINE_RUNNER_WINDOW"
}

_runner_probe_error () {
  _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_PROBE_PROBLEM" fail \
    "runner probe failed or emitted an invalid condition"
}

_runner_finish () {   # <condition> <window> <key>
  local condition="$1" win="$2" key="$3"
  case "$condition" in
    ok)
      _signal_set health _condition_level_valid ok "$key" ok -t "$win"
      _signal_set status _status_level_valid "" "$key" result --transient -t "$win"
      ;;
    warn|fail)
      _signal_set health _condition_level_valid ok "$key" "$condition" --transient -t "$win"
      _signal_set status _status_level_valid "" "$key" attention --transient -t "$win"
      ;;
  esac
}

# Parsed runner specification. The CLI composes at most one element of each type for
# one operation. Probe arguments end at the next recognized runner option, at `--`
# for run, or at argv exhaustion for watch.
AIRLINE_RUNNER_PLACEMENT=here
AIRLINE_RUNNER_PANE_ORIENTATION=""
AIRLINE_RUNNER_CLASSIFIER=""
AIRLINE_RUNNER_FILTER=""
AIRLINE_RUNNER_FILTER_MERGE=""
AIRLINE_RUNNER_PROBE=""
AIRLINE_RUNNER_PROBE_ARGS=()
AIRLINE_RUNNER_COMMAND=()
AIRLINE_RUNNER_INVOCATION_ARGV=()

# A leading bare name selects a catalogued composition. Its arguments are passed to
# the definition's configure function; run still uses `--` to delimit the command.
# Leading placement options are invocation concerns and never enter the definition.
# An otherwise option-leading invocation is the existing ad-hoc form.
_runner_expand_named () {   # <session> <run|watch> [invocation...]
  local session="$1" mode="$2" name file boundary=""; shift 2
  local -a placement=() extra=() command=()
  AIRLINE_RUNNER_INVOCATION_ARGV=()

  while (( $# )); do
    case "$1" in
      --pane)
        placement+=("$1"); shift
        if [[ "${1:-}" == -h || "${1:-}" == -v ]]; then
          placement+=("$1"); shift
        fi
        ;;
      --here|--window) placement+=("$1"); shift ;;
      *) break ;;
    esac
  done

  if (( $# == 0 )) || [[ "$1" == --* ]]; then
    AIRLINE_RUNNER_INVOCATION_ARGV=("${placement[@]}" "$@")
    return 0
  fi

  name="$1"; shift
  [[ "$name" != */* ]] || die "runner $mode: runner must be a bare name"
  file="$(_path_resolve "$session" runner "$name")"
  [[ -n "$file" ]] || die "runner $mode: runner '$name' not found"
  runner_definition_load "$file" || die "runner $mode: runner '$name' is invalid"
  runner_definition_metadata || die "runner $mode: runner '$name' has invalid metadata"

  if [[ "$mode" == run ]]; then
    while (( $# )); do
      if [[ "$1" == -- ]]; then
        boundary=1; shift; command=("$@"); break
      fi
      extra+=("$1"); shift
    done
    [[ -n "$boundary" && ${#command[@]} -gt 0 ]] || \
      die "runner run: named runner '$name' needs -- <command>"
    runner_definition_configure "${extra[@]}" || \
      die "runner run: runner '$name' produced an invalid configuration"
    runner_definition_project run
    AIRLINE_RUNNER_INVOCATION_ARGV=(
      "${placement[@]}" "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}" -- "${command[@]}"
    )
  else
    runner_definition_configure "$@" || \
      die "runner watch: runner '$name' produced an invalid configuration"
    if ! runner_definition_project watch; then
      die "runner watch: runner '$name' has no probe"
    fi
    AIRLINE_RUNNER_INVOCATION_ARGV=(
      "${placement[@]}" "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
    )
  fi
}

_runner_spec_token () {
  case "${1:-}" in
    --here|--pane|--window|--classify|--filter|--probe|--) return 0 ;;
    *) return 1 ;;
  esac
}

_runner_parse () {   # <run|watch> [spec...]
  local mode="$1"; shift
  AIRLINE_RUNNER_PLACEMENT=here
  AIRLINE_RUNNER_PANE_ORIENTATION=""
  AIRLINE_RUNNER_CLASSIFIER=""
  AIRLINE_RUNNER_FILTER=""
  AIRLINE_RUNNER_FILTER_MERGE=""
  AIRLINE_RUNNER_PROBE=""
  AIRLINE_RUNNER_PROBE_ARGS=()
  AIRLINE_RUNNER_COMMAND=()

  while (( $# )); do
    case "$1" in
      --here)
        AIRLINE_RUNNER_PLACEMENT=here
        AIRLINE_RUNNER_PANE_ORIENTATION=""
        shift
        ;;
      --pane)
        AIRLINE_RUNNER_PLACEMENT=pane
        AIRLINE_RUNNER_PANE_ORIENTATION=""
        shift
        if [[ "${1:-}" == -h || "${1:-}" == -v ]]; then
          AIRLINE_RUNNER_PANE_ORIENTATION="$1"
          shift
        fi
        ;;
      --window)
        AIRLINE_RUNNER_PLACEMENT=window
        AIRLINE_RUNNER_PANE_ORIENTATION=""
        shift
        ;;
      --classify)
        [[ "$mode" == run ]] || die "runner watch: --classify is not applicable"
        [[ -z "$AIRLINE_RUNNER_CLASSIFIER" ]] || die "runner run: classifier already specified"
        [[ $# -ge 2 && -n "$2" ]] || die "runner run: --classify requires <name>"
        AIRLINE_RUNNER_CLASSIFIER="$2"; shift 2 ;;
      --filter)
        [[ "$mode" == run ]] || die "runner watch: --filter is not applicable"
        [[ -z "$AIRLINE_RUNNER_FILTER" ]] || die "runner run: filter already specified"
        [[ $# -ge 2 && -n "$2" ]] || die "runner run: --filter requires <name>"
        AIRLINE_RUNNER_FILTER="$2"; shift 2
        if [[ "${1:-}" == --merge-stderr ]]; then AIRLINE_RUNNER_FILTER_MERGE=1; shift; fi
        ;;
      --probe)
        [[ -z "$AIRLINE_RUNNER_PROBE" ]] || die "runner $mode: probe already specified"
        [[ $# -ge 2 && -n "$2" ]] || die "runner $mode: --probe requires <name>"
        AIRLINE_RUNNER_PROBE="$2"; shift 2
        while (( $# )) && ! _runner_spec_token "$1"; do
          AIRLINE_RUNNER_PROBE_ARGS+=("$1"); shift
        done
        ;;
      --)
        [[ "$mode" == run ]] || die "runner watch: unexpected -- (watch ends at end of arguments)"
        shift; AIRLINE_RUNNER_COMMAND=("$@"); break ;;
      --merge-stderr) die "runner $mode: --merge-stderr must immediately follow --filter <name>" ;;
      *) die "runner $mode: unknown option '$1'" ;;
    esac
  done

  if [[ "$mode" == run ]]; then
    [[ ${#AIRLINE_RUNNER_COMMAND[@]} -gt 0 ]] || die "runner run: need -- <command>"
    [[ -n "$AIRLINE_RUNNER_CLASSIFIER" ]] || AIRLINE_RUNNER_CLASSIFIER=basic
  else
    [[ -n "$AIRLINE_RUNNER_PROBE" ]] || die "runner watch: need --probe <name> [<arg>...]"
  fi
}

_runner_validate_spec () {   # <session> <run|watch>
  local session="$1" mode="$2" file
  if [[ "$mode" == run ]]; then
    file="$(_runner_element_file "$session" classify "$AIRLINE_RUNNER_CLASSIFIER")" || \
      die "runner run: classifier '$AIRLINE_RUNNER_CLASSIFIER' not found"
    runner_classifier_valid "$file" || die "runner run: classifier '$AIRLINE_RUNNER_CLASSIFIER' is invalid"
    if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
      file="$(_runner_element_file "$session" filter "$AIRLINE_RUNNER_FILTER")" || \
        die "runner run: filter '$AIRLINE_RUNNER_FILTER' not found"
      runner_filter_valid "$file" || die "runner run: filter '$AIRLINE_RUNNER_FILTER' is invalid"
    fi
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")" || \
      die "runner $mode: probe '$AIRLINE_RUNNER_PROBE' not found"
    runner_probe_valid "$file" || die "runner $mode: probe '$AIRLINE_RUNNER_PROBE' is invalid"
  fi
}

AIRLINE_RUNNER_SPEC_ARGV=()
_runner_normalize_spec () {   # <run|watch>
  local mode="$1"
  AIRLINE_RUNNER_SPEC_ARGV=()
  [[ "$mode" == run ]] && AIRLINE_RUNNER_SPEC_ARGV+=(--classify "$AIRLINE_RUNNER_CLASSIFIER")
  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    AIRLINE_RUNNER_SPEC_ARGV+=(--filter "$AIRLINE_RUNNER_FILTER")
    [[ -n "$AIRLINE_RUNNER_FILTER_MERGE" ]] && AIRLINE_RUNNER_SPEC_ARGV+=(--merge-stderr)
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    AIRLINE_RUNNER_SPEC_ARGV+=(--probe "$AIRLINE_RUNNER_PROBE" "${AIRLINE_RUNNER_PROBE_ARGS[@]}")
  fi
  [[ "$mode" == run ]] && AIRLINE_RUNNER_SPEC_ARGV+=(-- "${AIRLINE_RUNNER_COMMAND[@]}")
}

# Run one command in the calling pane. The process is started as a child so airline
# can observe it; explicit stdin inheritance preserves current-pane interaction and
# stdout/stderr remain visible in the pane. A filter gets a tee'd copy of its declared
# stream; a probe performs sequential periodic observations without overlapping.
_runner_execute () {   # <session> <retain:0|1>; uses parsed run specification
  local session="$1" retain="$2" file pane win key filter_key probe_key
  local load_problem classify_problem filter_problem probe_problem streams=""
  local child_pid filter_pid="" probe_pid="" rc=0 signal="" condition

  pane="$(current_pane)"
  win="$(resolve_window "$pane")"
  key="runner-${pane#%}"
  filter_key="$key-filter"
  probe_key="$key-probe"
  load_problem="$(_runner_problem_key "$AIRLINE_RUNNER_CLASSIFIER" load)"
  classify_problem="$(_runner_problem_key "$AIRLINE_RUNNER_CLASSIFIER" classify)"
  filter_problem="$(_runner_problem_key "$AIRLINE_RUNNER_FILTER" filter)"
  probe_problem="$(_runner_problem_key "$AIRLINE_RUNNER_PROBE" probe)"
  [[ "$retain" == 1 ]] && runner_retain_pane "$pane"

  file="$(_runner_element_file "$session" classify "$AIRLINE_RUNNER_CLASSIFIER")"
  runner_classifier_load "$file" || return 2
  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    file="$(_runner_element_file "$session" filter "$AIRLINE_RUNNER_FILTER")"
    runner_filter_load "$file" || return 2
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")"
    runner_probe_load "$file" || return 2
  fi
  _runner_problem "$session" "$load_problem" ok ""

  _signal_set health _condition_level_valid ok "$key" ok -t "$win"
  _signal_set health _condition_level_valid ok "$filter_key" ok -t "$win"
  _signal_set health _condition_level_valid ok "$probe_key" ok -t "$win"
  _signal_set status _status_level_valid "" "$key" active -t "$win"

  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    streams=stdout
    if ! runner_stream_prepare "$streams"; then
      runner_stream_cleanup
      _runner_problem "$session" "$filter_problem" fail "runner filter '$AIRLINE_RUNNER_FILTER' could not prepare"
      return 2
    fi
    trap runner_stream_cleanup EXIT
  fi

  # Launch before opening the tee readers: a selected FIFO blocks the child briefly,
  # allowing airline to obtain its PID for the filter contract.
  case "$streams:$AIRLINE_RUNNER_FILTER_MERGE" in
    stdout:1) "${AIRLINE_RUNNER_COMMAND[@]}" <&0 > "$AIRLINE_RUNNER_STREAM_COMMAND" 2>&1 & ;;
    stdout:)  "${AIRLINE_RUNNER_COMMAND[@]}" <&0 > "$AIRLINE_RUNNER_STREAM_COMMAND" & ;;
    :)        "${AIRLINE_RUNNER_COMMAND[@]}" <&0 & ;;
  esac
  child_pid=$!

  AIRLINE_RUNNER_SESSION="$session"
  AIRLINE_RUNNER_WINDOW="$win"
  AIRLINE_RUNNER_FILTER_KEY="$filter_key"
  AIRLINE_RUNNER_FILTER_PROBLEM="$filter_problem"
  AIRLINE_RUNNER_FILTER_LAST=""
  AIRLINE_RUNNER_PROBE_KEY="$probe_key"
  AIRLINE_RUNNER_PROBE_PROBLEM="$probe_problem"
  AIRLINE_RUNNER_PROBE_LAST=""
  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    runner_filter_start "$child_pid" _runner_filter_report "$AIRLINE_RUNNER_STREAM_INPUT"
    filter_pid="$AIRLINE_RUNNER_FILTER_PID"
    runner_stream_start
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    runner_probe_start "$child_pid" _runner_probe_report _runner_probe_error \
      "${AIRLINE_RUNNER_PROBE_ARGS[@]}"
    probe_pid="$AIRLINE_RUNNER_PROBE_PID"
  fi

  wait "$child_pid" || rc=$?
  runner_probe_stop "$probe_pid"
  if [[ -n "$filter_pid" ]]; then
    runner_stream_wait || true
  fi
  if ! runner_filter_wait "$filter_pid"; then
    _runner_problem "$session" "$filter_problem" fail "runner filter '$AIRLINE_RUNNER_FILTER' failed"
  fi
  if [[ -n "$streams" ]]; then
    runner_stream_cleanup
    trap - EXIT
  fi
  _signal_set health _condition_level_valid ok "$filter_key" ok -t "$win"
  _signal_set health _condition_level_valid ok "$probe_key" ok -t "$win"
  (( rc > 128 )) && signal="$((rc - 128))"

  if condition="$(runner_classifier_run "$rc" "$signal")"; then
    _runner_problem "$session" "$classify_problem" ok ""
  else
    condition=fail
    _runner_problem "$session" "$classify_problem" fail \
      "runner classifier '$AIRLINE_RUNNER_CLASSIFIER' failed or emitted an invalid condition"
  fi
  _runner_finish "$condition" "$win" "$key"
  return "$rc"
}

_runner_invoke () {   # <session> <run|watch> [spec...]
  local session="$1" mode="$2" pane cwd spawned; shift 2
  _runner_expand_named "$session" "$mode" "$@"
  _runner_parse "$mode" "${AIRLINE_RUNNER_INVOCATION_ARGV[@]}"
  _runner_validate_spec "$session" "$mode"
  _runner_normalize_spec "$mode"

  case "$AIRLINE_RUNNER_PLACEMENT" in
    here)
      if [[ "$mode" == run ]]; then _runner_execute "$session" 0
      else _runner_watch_execute "$session" 0; fi
      ;;
    pane|window)
      pane="$(current_pane)"; cwd="$(current_path)"
      if [[ "$AIRLINE_RUNNER_PLACEMENT" == pane ]]; then
        spawned="$(runner_open_pane "$pane" "$cwd" "$AIRLINE_RUNNER_PANE_ORIENTATION" env \
          "AIRLINE_DIR=$AIRLINE_DIR" "AIRLINE_TMUX=${AIRLINE_TMUX:-tmux}" \
          "$AIRLINE_DIR/airline.sh" "_$mode" "${AIRLINE_RUNNER_SPEC_ARGV[@]}")"
      else
        spawned="$(runner_open_window "$session" "$cwd" env \
          "AIRLINE_DIR=$AIRLINE_DIR" "AIRLINE_TMUX=${AIRLINE_TMUX:-tmux}" \
          "$AIRLINE_DIR/airline.sh" "_$mode" "${AIRLINE_RUNNER_SPEC_ARGV[@]}")"
      fi
      # Arm retention from both sides of the spawn boundary. The child does it
      # before validation; the parent closes the scheduler race before a very
      # short-lived child can be reaped under load.
      runner_retain_pane "$spawned"
      printf '%s\n' "$spawned"
      ;;
  esac
}

# Watch external state without manufacturing a placeholder command.
_runner_watch_execute () {   # <session> <retain:0|1>; uses parsed watch specification
  local session="$1" retain="$2" file pane win key probe_key probe_problem
  local interval watch_pid="$BASHPID" watch_rc=0 sleep_pid=""

  pane="$(current_pane)"
  win="$(resolve_window "$pane")"
  key="runner-${pane#%}-watch"
  probe_key="$key-probe"
  probe_problem="$(_runner_problem_key "$AIRLINE_RUNNER_PROBE" probe)"
  [[ "$retain" == 1 ]] && runner_retain_pane "$pane"

  file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")"
  runner_probe_load "$file" || return 2
  _runner_problem "$session" "$(_runner_problem_key "$AIRLINE_RUNNER_PROBE" load)" ok ""

  AIRLINE_RUNNER_SESSION="$session"
  AIRLINE_RUNNER_WINDOW="$win"
  AIRLINE_RUNNER_PROBE_KEY="$probe_key"
  AIRLINE_RUNNER_PROBE_PROBLEM="$probe_problem"
  AIRLINE_RUNNER_PROBE_LAST=""
  interval="${AIRLINE_RUNNER_PROBE_INTERVAL:-5}"

  _signal_set health _condition_level_valid ok "$probe_key" ok -t "$win"
  _signal_set status _status_level_valid "" "$key" active -t "$win"

  trap 'watch_rc=130; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' INT
  trap 'watch_rc=143; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' TERM
  trap 'watch_rc=129; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' HUP
  while (( watch_rc == 0 )); do
    if runner_probe_once "$watch_pid" "${AIRLINE_RUNNER_PROBE_ARGS[@]}"; then
      _runner_probe_report "$AIRLINE_RUNNER_PROBE_CONDITION"
    else
      _runner_probe_error
    fi
    (( watch_rc == 0 )) || break
    sleep "$interval" &
    sleep_pid=$!
    wait "$sleep_pid" 2>/dev/null || true
    sleep_pid=""
  done
  trap - INT TERM HUP

  _signal_clear health "$probe_key" -t "$win"
  _signal_clear status "$key" -t "$win"
  return "$watch_rc"
}
# CLI delegation targets for runner and its primitives.
runner_classifier_show () { local s; s="$(_require_current_session)"; _runner_element_show "$s" classifier "$@"; }
runner_classifier_list () { local s; s="$(_require_current_session)"; _path_list "$s" classifier; }
runner_classifier_register () { local s; s="$(_require_current_session)"; _register "$s" classifier "$@"; }
runner_filter_show () { local s; s="$(_require_current_session)"; _runner_element_show "$s" filter "$@"; }
runner_filter_list () { local s; s="$(_require_current_session)"; _path_list "$s" filter; }
runner_filter_register () { local s; s="$(_require_current_session)"; _register "$s" filter "$@"; }
runner_probe_show () { local s; s="$(_require_current_session)"; _runner_element_show "$s" probe "$@"; }
runner_probe_list () { local s; s="$(_require_current_session)"; _path_list "$s" probe; }
runner_probe_register () { local s; s="$(_require_current_session)"; _register "$s" probe "$@"; }

runner_show () { local s; s="$(_require_current_session)"; _runner_definition_show "$s" "$@"; }
runner_list () { local s; s="$(_require_current_session)"; _path_list "$s" runner; }
runner_register () { local s; s="$(_require_current_session)"; _register "$s" runner "$@"; }
runner_run () { local s; s="$(_require_current_session)"; _runner_invoke "$s" run "$@"; }
runner_watch () { local s; s="$(_require_current_session)"; _runner_invoke "$s" watch "$@"; }

runner_exec () {   # <normalized-run-spec...>; internal spawned-pane entry
  local s
  s="$(_require_current_session)"
  runner_retain_pane "$(current_pane)"
  _runner_parse run "$@"
  _runner_validate_spec "$s" run
  _runner_execute "$s" 0
}

runner_watch_exec () {   # <normalized-watch-spec...>; internal spawned-pane entry
  local s
  s="$(_require_current_session)"
  runner_retain_pane "$(current_pane)"
  _runner_parse watch "$@"
  _runner_validate_spec "$s" watch
  _runner_watch_execute "$s" 0
}

# vim: ft=bash

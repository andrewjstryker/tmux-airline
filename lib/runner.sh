#!/usr/bin/env bash
#
# runner.sh — runner contracts, mechanics, and command orchestration.
#
# Elements are trusted shell selected independently for one invocation:
#
# Every element declares `#| summary:` in its header, plus `#| usage:` and an
# optional `#| interval:` where the kind calls for them. Catalog reads those without
# executing the file, so discovery never runs an element.
#
#   runners/classifiers/<name>: airline_runner_classify <exit-status> <signal>
#       Print `ok` or `<warn|fail><TAB><message>`.
#
#   runners/filters/<name>: airline_runner_filter <pid> <report-function>
#       Read stdout (or merged stdout/stderr when core requests it) from stdin and
#       call the reporter with `ok` or `<warn|fail> <message>` as evidence changes.
#       Emit a definitive report at EOF; that terminal health remains after exit.
#
#   runners/probes/<name>: airline_runner_probe <lifecycle-pid> <report-function> [<arg>...]
#       Perform one bounded observation, calling the reporter with `ok` or
#       `<warn|fail> <message>` for each condition. Stdout is uninterpreted user
#       output. Airline reduces reports and retains diagnostics at the worst level.
#       `#| interval:` optionally sets seconds between observations (default 5).
#
#   runners/definitions/<name>: airline_runner_configure
#       Build one normalized monitoring composition by calling core-supplied
#       callbacks. Run uses the full result; watch its subset.
#
# The contract/mechanics section has no tmux knowledge. The command orchestration
# later in this module reaches tmux only through tmux.sh and projects normalized
# reports through signal services.

# shellcheck shell=bash

# Required metadata per kind, read from the element header without executing it. A
# field that must be declared but may be empty is checked for presence, not value.
_runner_metadata_require () {   # <kind> <file>
  local kind="$1" file="$2"
  catalog_metadata_valid "$file" || return 1
  case "$kind" in
    probe)
      catalog_metadata "$file" usage >/dev/null || return 1
      _runner_interval_valid "$(_runner_probe_interval "$file")" || return 1
      ;;
    runner) catalog_metadata "$file" usage >/dev/null || return 1 ;;
  esac
}

# Seconds between probe observations. An interval supplied at invocation — directly
# or projected from a named runner — overrides the probe's declared default.
_runner_effective_interval () {
  printf '%s' "${AIRLINE_RUNNER_INTERVAL:-${AIRLINE_RUNNER_PROBE_INTERVAL:-5}}"
}

# Declared seconds between probe observations; the shipped default when unstated.
_runner_probe_interval () {   # <file>
  local interval
  interval="$(catalog_metadata "$1" interval)" || interval=""
  printf '%s' "${interval:-5}"
}

runner_classifier_load () {   # <file>
  unset -f airline_runner_classify 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_classify >/dev/null
}

runner_classifier_valid () ( _runner_metadata_require classifier "$1" && runner_classifier_load "$1" )

runner_classifier_run () {   # <exit-status> <signal>
  local report condition message rc=0
  report="$(airline_runner_classify "$1" "$2")" || rc=$?
  (( rc == 0 )) || return 1
  condition="${report%%$'\t'*}"
  if [[ "$report" == *$'\t'* ]]; then message="${report#*$'\t'}"
  else message=""; fi
  _runner_condition_report_valid "$condition" "$message" || return 1
  printf '%s' "$report"
}

runner_filter_load () {   # <file>
  unset -f airline_runner_filter 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_filter >/dev/null
}

runner_filter_valid () ( _runner_metadata_require filter "$1" && runner_filter_load "$1" )

AIRLINE_RUNNER_FILTER_PID=""
AIRLINE_RUNNER_FILTER_REPORT=""
AIRLINE_RUNNER_FILTER_REPORTED=""

_runner_filter_forward () {   # <ok> | <warn|fail> <message>
  AIRLINE_RUNNER_FILTER_REPORTED=1
  "$AIRLINE_RUNNER_FILTER_REPORT" "$@"
}

runner_filter_start () {   # <pid> <report-function> <input>
  local child_pid="$1" report="$2" input="$3"
  (
    AIRLINE_RUNNER_FILTER_REPORT="$report"
    AIRLINE_RUNNER_FILTER_REPORTED=""
    airline_runner_filter "$child_pid" _runner_filter_forward < "$input" || exit $?
    [[ -n "$AIRLINE_RUNNER_FILTER_REPORTED" ]]
  ) &
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
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_probe >/dev/null || return 1
  # Declared metadata; airline holds it internally for the observation loop.
  AIRLINE_RUNNER_PROBE_INTERVAL="$(_runner_probe_interval "$1")"
}

runner_probe_valid () ( _runner_metadata_require probe "$1" && runner_probe_load "$1" )

# A probe's stdout belongs to the user. Its reporter is the separate machine
# channel: collect every call made during one observation, validate it, and expose
# the reduced condition through a variable so no control data enters stdout.
AIRLINE_RUNNER_PROBE_REPORTS=()
AIRLINE_RUNNER_PROBE_MESSAGES=()
AIRLINE_RUNNER_PROBE_REPORT_INVALID=""
AIRLINE_RUNNER_PROBE_CONDITION=""
AIRLINE_RUNNER_PROBE_MESSAGE=""

_runner_probe_collect () {   # <ok> | <warn|fail> <message>
  local condition="${1:-}" message="${2:-}"
  if (( $# < 1 || $# > 2 )) || ! signal_condition_valid "$condition" || \
    [[ "$message" == *$'\t'* ]] || \
    { [[ "$condition" == ok ]] && [[ -n "$message" ]]; } || \
    { [[ "$condition" != ok ]] && [[ -z "$message" ]]; }; then
    AIRLINE_RUNNER_PROBE_REPORT_INVALID=1
    return 1
  fi
  AIRLINE_RUNNER_PROBE_REPORTS+=("$condition")
  AIRLINE_RUNNER_PROBE_MESSAGES+=("$message")
}

runner_probe_once () {   # <lifecycle-pid> [<arg>...]
  local lifecycle_pid="$1" condition message worst=ok worst_message="" rc=0 i; shift
  AIRLINE_RUNNER_PROBE_REPORTS=()
  AIRLINE_RUNNER_PROBE_MESSAGES=()
  AIRLINE_RUNNER_PROBE_REPORT_INVALID=""
  AIRLINE_RUNNER_PROBE_CONDITION=""
  AIRLINE_RUNNER_PROBE_MESSAGE=""
  airline_runner_probe "$lifecycle_pid" _runner_probe_collect "$@" || rc=$?
  (( rc == 0 )) || return 1
  [[ -z "$AIRLINE_RUNNER_PROBE_REPORT_INVALID" ]] || return 1
  (( ${#AIRLINE_RUNNER_PROBE_REPORTS[@]} > 0 )) || return 1
  for i in "${!AIRLINE_RUNNER_PROBE_REPORTS[@]}"; do
    condition="${AIRLINE_RUNNER_PROBE_REPORTS[$i]}"
    message="${AIRLINE_RUNNER_PROBE_MESSAGES[$i]}"
    case "$condition" in
      fail)
        if [[ "$worst" != fail ]]; then worst=fail; worst_message="$message"; fi
        ;;
      warn)
        if [[ "$worst" == ok ]]; then worst=warn; worst_message="$message"; fi
        ;;
    esac
  done
  AIRLINE_RUNNER_PROBE_CONDITION="$worst"
  AIRLINE_RUNNER_PROBE_MESSAGE="$worst_message"
}

_runner_probe_loop () {   # <pid> <report-function> <error-function> [<probe-arg>...]
  local lifecycle_pid="$1" report="$2" error="$3" interval
  shift 3
  interval="$(_runner_effective_interval)"
  while kill -0 "$lifecycle_pid" 2>/dev/null; do
    if runner_probe_once "$lifecycle_pid" "$@"; then
      "$report" "$AIRLINE_RUNNER_PROBE_CONDITION" "$AIRLINE_RUNNER_PROBE_MESSAGE"
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

# A named runner is syntactic composition, not lifecycle machinery. Its one required
# function calls validated core callbacks; stdout is never a protocol channel.
# Discovery text is header metadata, so listing a runner never evaluates it.
runner_definition_load () {   # <file>
  unset -f airline_runner_configure 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$1" || return 1
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

AIRLINE_RUNNER_CONFIG_CLASSIFIER=""
AIRLINE_RUNNER_CONFIG_FILTER=""
AIRLINE_RUNNER_CONFIG_FILTER_MERGE=""
AIRLINE_RUNNER_CONFIG_PROBE=""
AIRLINE_RUNNER_CONFIG_PROBE_ARGS=()
AIRLINE_RUNNER_CONFIG_INTERVAL=""
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
    interval)
      if (( $# != 2 )) || [[ -n "$AIRLINE_RUNNER_CONFIG_INTERVAL" ]] || \
        ! _runner_interval_valid "$2"; then
        AIRLINE_RUNNER_CONFIG_INVALID=1; return 1
      fi
      AIRLINE_RUNNER_CONFIG_INTERVAL="$2"
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
  AIRLINE_RUNNER_CONFIG_INTERVAL=""
  AIRLINE_RUNNER_CONFIG_INVALID=""
  AIRLINE_RUNNER_CONFIG_SEEN=""
  _runner_contract_call airline_runner_configure _runner_configure_collect "$@" || return 1
  [[ -z "$AIRLINE_RUNNER_CONFIG_INVALID" && -n "$AIRLINE_RUNNER_CONFIG_SEEN" ]] || return 1
  # An interval paces probe observations; declaring one without a probe is a mistake
  # rather than a silently ignored setting.
  [[ -z "$AIRLINE_RUNNER_CONFIG_INTERVAL" || -n "$AIRLINE_RUNNER_CONFIG_PROBE" ]]
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
    # Interval precedes the probe: probe arguments run to the end of the option list.
    [[ -z "$AIRLINE_RUNNER_CONFIG_INTERVAL" ]] || \
      AIRLINE_RUNNER_DEFINITION_ARGV+=(--interval "$AIRLINE_RUNNER_CONFIG_INTERVAL")
    AIRLINE_RUNNER_DEFINITION_ARGV+=(
      --probe "$AIRLINE_RUNNER_CONFIG_PROBE" "${AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]}"
    )
  elif [[ "$mode" == watch ]]; then
    return 2
  fi
}

#-----------------------------------------------------------------------------#
# Runner command behavior
#-----------------------------------------------------------------------------#

#-----------------------------------------------------------------------------#
# Runner catalogs and ephemeral composition of classifier, filter, and probe elements
#-----------------------------------------------------------------------------#

_runner_element_file () {   # <session> <kind> <bare-name>
  local session="$1" kind="$2" name="$3"
  [[ "$kind" == classify ]] && kind=classifier
  catalog_resolve "$session" "$kind" "$name"
}

_runner_definition_describe () {   # <session> <name> [<runner-arg>...]
  local session="$1" name="${2:-}" file probe_args=""; shift 2 || true
  file="$(catalog_describe_resolve "$session" runner "$name")" || return
  _runner_metadata_require runner "$file" || command_die "runner describe: '$name' has invalid metadata"
  runner_definition_load "$file" || command_die "runner describe: '$name' is invalid"
  runner_definition_configure "$@" || command_die "runner describe: '$name' produced an invalid configuration"
  if (( ${#AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]} )); then
    printf -v probe_args '%q ' "${AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]}"
    probe_args="${probe_args% }"
  fi
  catalog_describe_render "$name" "$file" || return
  command_show_row classifier "${AIRLINE_RUNNER_CONFIG_CLASSIFIER:-basic}"
  command_show_row filter "${AIRLINE_RUNNER_CONFIG_FILTER:-none}"
  [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER_MERGE" ]] && command_show_row filter-input merged-stderr
  command_show_row probe "${AIRLINE_RUNNER_CONFIG_PROBE:-none}"
  [[ -n "$probe_args" ]] && command_show_row probe-args "$probe_args"
  return 0
}

# Globals intentionally cross the filter's background subshell boundary. Each CLI
# invocation owns one run, so concurrent jobs live in separate processes and cannot
# collide here; health claims are isolated by their pane owner.
AIRLINE_RUNNER_SESSION=""
AIRLINE_RUNNER_PANE=""
AIRLINE_RUNNER_FILTER_HEALTH_KEY=""
AIRLINE_RUNNER_FILTER_CONTRIBUTOR=""
AIRLINE_RUNNER_FILTER_PROBLEM_KEY=""
AIRLINE_RUNNER_PROBE_HEALTH_KEY=""
AIRLINE_RUNNER_PROBE_CONTRIBUTOR=""
AIRLINE_RUNNER_PROBE_PROBLEM_KEY=""

_runner_element_contributor () {   # <classifier|filter|probe> <element>
  local kind="$1" name="${2##*/}"
  name="${name//[^a-zA-Z0-9_-]/-}"
  printf 'airline-runner-%s-%s' "$kind" "$name"
}

# tmux may observe EOF on a pane PTY before it reaps the pane process. With
# libutempter builds, its synthetic SIGCHLD can race the real child notification,
# leaving a retained pane dead without PANE_STATUSREADY or a native exit status.
# Keep one copy of the PTY open until this Airline process has actually disappeared;
# tmux must then reap and record the status before it can observe the final EOF.
_runner_exit_guard_start () {   # <airline-pid>
  local parent_pid="$1"
  (
    exec 9>&1
    exec >/dev/null 2>&1
    while kill -0 "$parent_pid" 2>/dev/null; do sleep 0.01; done
  ) &
}

_runner_condition_report_valid () {   # <ok|warn|fail> <message>
  local condition="$1" message="$2"
  signal_condition_valid "$condition" || return 1
  [[ "$message" != *$'\t'* ]] || return 1
  if [[ "$condition" == ok ]]; then [[ -z "$message" ]]
  else [[ -n "$message" ]]; fi
}

_runner_filter_report () {   # <ok> | <warn|fail> <message>
  local condition="${1:-}" message="${2:-}" diagnostic
  if (( $# < 1 || $# > 2 )) || ! _runner_condition_report_valid "$condition" "$message"; then
    diagnostic="${condition//$'\t'/ }"
    signal_problem_report "$AIRLINE_RUNNER_SESSION" \
      "$AIRLINE_RUNNER_FILTER_CONTRIBUTOR" "$AIRLINE_RUNNER_FILTER_PROBLEM_KEY" fail \
      "runner filter emitted invalid condition report '${diagnostic}'"
    return 1
  fi
  signal_problem_report "$AIRLINE_RUNNER_SESSION" \
    "$AIRLINE_RUNNER_FILTER_CONTRIBUTOR" "$AIRLINE_RUNNER_FILTER_PROBLEM_KEY" ok ""
  signal_health_set -t "$AIRLINE_RUNNER_PANE" \
    "$AIRLINE_RUNNER_FILTER_CONTRIBUTOR" \
    "$AIRLINE_RUNNER_FILTER_HEALTH_KEY" "$condition" ${message:+"$message"}
}

_runner_probe_report () {   # <ok> | <warn|fail> <message>
  local condition="${1:-}" message="${2:-}" diagnostic
  if (( $# < 1 || $# > 2 )) || ! _runner_condition_report_valid "$condition" "$message"; then
    diagnostic="${condition//$'\t'/ }"
    signal_problem_report "$AIRLINE_RUNNER_SESSION" \
      "$AIRLINE_RUNNER_PROBE_CONTRIBUTOR" "$AIRLINE_RUNNER_PROBE_PROBLEM_KEY" fail \
      "runner probe emitted invalid condition report '${diagnostic}'"
    return 1
  fi
  signal_problem_report "$AIRLINE_RUNNER_SESSION" \
    "$AIRLINE_RUNNER_PROBE_CONTRIBUTOR" "$AIRLINE_RUNNER_PROBE_PROBLEM_KEY" ok ""
  signal_health_set -t "$AIRLINE_RUNNER_PANE" \
    "$AIRLINE_RUNNER_PROBE_CONTRIBUTOR" \
    "$AIRLINE_RUNNER_PROBE_HEALTH_KEY" "$condition" ${message:+"$message"}
}

_runner_probe_error () {
  signal_problem_report "$AIRLINE_RUNNER_SESSION" \
    "$AIRLINE_RUNNER_PROBE_CONTRIBUTOR" "$AIRLINE_RUNNER_PROBE_PROBLEM_KEY" fail \
    "runner probe failed or emitted an invalid condition"
}

_runner_finish () {   # <condition> <message> <pane> <health-contributor> <health-key>
  local condition="$1" message="$2" pane="$3" contributor="$4" health_key="$5"
  case "$condition" in
    ok)
      signal_health_set -t "$pane" "$contributor" "$health_key" ok
      ;;
    warn|fail)
      signal_health_set -t "$pane" "$contributor" "$health_key" "$condition" "$message"
      ;;
  esac
  # Status describes the workflow phase; health separately describes its outcome.
  signal_status_set -t "$pane" result
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
  local session="$1" mode="$2" name file boundary="" placement_seen=""; shift 2
  local -a placement=() extra=() command=()
  AIRLINE_RUNNER_INVOCATION_ARGV=()

  while (( $# )); do
    case "$1" in
      --pane)
        [[ -z "$placement_seen" ]] || command_die "runner $mode: placement already specified"
        placement_seen=pane
        placement+=("$1"); shift
        if [[ "${1:-}" == -h || "${1:-}" == -v ]]; then
          placement+=("$1"); shift
        fi
        ;;
      --window)
        [[ -z "$placement_seen" ]] || command_die "runner $mode: placement already specified"
        placement_seen=window
        placement+=("$1"); shift ;;
      *) break ;;
    esac
  done

  if (( $# == 0 )) || [[ "$1" == --* ]]; then
    AIRLINE_RUNNER_INVOCATION_ARGV=("${placement[@]}" "$@")
    return 0
  fi

  name="$1"; shift
  [[ "$name" != */* ]] || command_die "runner $mode: runner must be a bare name"
  file="$(catalog_resolve "$session" runner "$name")"
  [[ -n "$file" ]] || command_die "runner $mode: runner '$name' not found"
  _runner_metadata_require runner "$file" || \
    command_die "runner $mode: runner '$name' has invalid metadata"
  runner_definition_load "$file" || command_die "runner $mode: runner '$name' is invalid"

  if [[ "$mode" == run ]]; then
    while (( $# )); do
      if [[ "$1" == -- ]]; then
        boundary=1; shift; command=("$@"); break
      fi
      extra+=("$1"); shift
    done
    [[ -n "$boundary" && ${#command[@]} -gt 0 ]] || \
      command_die "runner run: named runner '$name' needs -- <command>"
    runner_definition_configure "${extra[@]}" || \
      command_die "runner run: runner '$name' produced an invalid configuration"
    runner_definition_project run
    AIRLINE_RUNNER_INVOCATION_ARGV=(
      "${placement[@]}" "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}" -- "${command[@]}"
    )
  else
    runner_definition_configure "$@" || \
      command_die "runner watch: runner '$name' produced an invalid configuration"
    if ! runner_definition_project watch; then
      command_die "runner watch: runner '$name' has no probe"
    fi
    AIRLINE_RUNNER_INVOCATION_ARGV=(
      "${placement[@]}" "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
    )
  fi
}

_runner_spec_token () {
  case "${1:-}" in
    --pane|--window|--classify|--filter|--probe|--interval|--) return 0 ;;
    *) return 1 ;;
  esac
}

_runner_parse () {   # <run|watch> [spec...]
  local mode="$1" placement_seen=""; shift
  AIRLINE_RUNNER_PLACEMENT=here
  AIRLINE_RUNNER_PANE_ORIENTATION=""
  AIRLINE_RUNNER_CLASSIFIER=""
  AIRLINE_RUNNER_FILTER=""
  AIRLINE_RUNNER_FILTER_MERGE=""
  AIRLINE_RUNNER_INTERVAL=""
  AIRLINE_RUNNER_PROBE=""
  AIRLINE_RUNNER_PROBE_ARGS=()
  AIRLINE_RUNNER_COMMAND=()

  while (( $# )); do
    case "$1" in
      --pane)
        [[ -z "$placement_seen" ]] || command_die "runner $mode: placement already specified"
        placement_seen=pane
        AIRLINE_RUNNER_PLACEMENT=pane
        AIRLINE_RUNNER_PANE_ORIENTATION=""
        shift
        if [[ "${1:-}" == -h || "${1:-}" == -v ]]; then
          AIRLINE_RUNNER_PANE_ORIENTATION="$1"
          shift
        fi
        ;;
      --window)
        [[ -z "$placement_seen" ]] || command_die "runner $mode: placement already specified"
        placement_seen=window
        AIRLINE_RUNNER_PLACEMENT=window
        AIRLINE_RUNNER_PANE_ORIENTATION=""
        shift
        ;;
      --classify)
        [[ "$mode" == run ]] || command_die "runner watch: --classify is not applicable"
        [[ -z "$AIRLINE_RUNNER_CLASSIFIER" ]] || command_die "runner run: classifier already specified"
        [[ $# -ge 2 && -n "$2" ]] || command_die "runner run: --classify requires <name>"
        AIRLINE_RUNNER_CLASSIFIER="$2"; shift 2 ;;
      --filter)
        [[ "$mode" == run ]] || command_die "runner watch: --filter is not applicable"
        [[ -z "$AIRLINE_RUNNER_FILTER" ]] || command_die "runner run: filter already specified"
        [[ $# -ge 2 && -n "$2" ]] || command_die "runner run: --filter requires <name>"
        AIRLINE_RUNNER_FILTER="$2"; shift 2
        if [[ "${1:-}" == --merge-stderr ]]; then AIRLINE_RUNNER_FILTER_MERGE=1; shift; fi
        ;;
      --interval)
        [[ -z "$AIRLINE_RUNNER_INTERVAL" ]] || command_die "runner $mode: interval already specified"
        [[ $# -ge 2 && -n "$2" ]] || command_die "runner $mode: --interval requires <seconds>"
        _runner_interval_valid "$2" || \
          command_die "runner $mode: --interval must be positive seconds"
        AIRLINE_RUNNER_INTERVAL="$2"; shift 2 ;;
      --probe)
        [[ -z "$AIRLINE_RUNNER_PROBE" ]] || command_die "runner $mode: probe already specified"
        [[ $# -ge 2 && -n "$2" ]] || command_die "runner $mode: --probe requires <name>"
        AIRLINE_RUNNER_PROBE="$2"; shift 2
        while (( $# )) && ! _runner_spec_token "$1"; do
          AIRLINE_RUNNER_PROBE_ARGS+=("$1"); shift
        done
        [[ $# == 0 || "$1" == -- ]] || \
          command_die "runner $mode: --probe and its arguments must follow other options"
        ;;
      --)
        [[ "$mode" == run ]] || command_die "runner watch: unexpected -- (watch ends at end of arguments)"
        shift; AIRLINE_RUNNER_COMMAND=("$@"); break ;;
      --merge-stderr) command_die "runner $mode: --merge-stderr must immediately follow --filter <name>" ;;
      *) command_die "runner $mode: unknown option '$1'" ;;
    esac
  done

  if [[ "$mode" == run ]]; then
    [[ ${#AIRLINE_RUNNER_COMMAND[@]} -gt 0 ]] || command_die "runner run: need -- <command>"
    [[ -n "$AIRLINE_RUNNER_CLASSIFIER" ]] || AIRLINE_RUNNER_CLASSIFIER=basic
  else
    [[ -n "$AIRLINE_RUNNER_PROBE" ]] || command_die "runner watch: need --probe <name> [<arg>...]"
  fi
  [[ -z "$AIRLINE_RUNNER_INTERVAL" || -n "$AIRLINE_RUNNER_PROBE" ]] || \
    command_die "runner $mode: --interval paces --probe observations"
}

_runner_validate_spec () {   # <session> <run|watch>
  local session="$1" mode="$2" file
  if [[ "$mode" == run ]]; then
    file="$(_runner_element_file "$session" classify "$AIRLINE_RUNNER_CLASSIFIER")" || \
      command_die "runner run: classifier '$AIRLINE_RUNNER_CLASSIFIER' not found"
    runner_classifier_valid "$file" || command_die "runner run: classifier '$AIRLINE_RUNNER_CLASSIFIER' is invalid"
    if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
      file="$(_runner_element_file "$session" filter "$AIRLINE_RUNNER_FILTER")" || \
        command_die "runner run: filter '$AIRLINE_RUNNER_FILTER' not found"
      runner_filter_valid "$file" || command_die "runner run: filter '$AIRLINE_RUNNER_FILTER' is invalid"
    fi
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")" || \
      command_die "runner $mode: probe '$AIRLINE_RUNNER_PROBE' not found"
    runner_probe_valid "$file" || command_die "runner $mode: probe '$AIRLINE_RUNNER_PROBE' is invalid"
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
    [[ -z "$AIRLINE_RUNNER_INTERVAL" ]] || \
      AIRLINE_RUNNER_SPEC_ARGV+=(--interval "$AIRLINE_RUNNER_INTERVAL")
    AIRLINE_RUNNER_SPEC_ARGV+=(--probe "$AIRLINE_RUNNER_PROBE" "${AIRLINE_RUNNER_PROBE_ARGS[@]}")
  fi
  # An `if` rather than a trailing `&&`: watch normalizes successfully and must not
  # report the mode test's status as failure.
  if [[ "$mode" == run ]]; then
    AIRLINE_RUNNER_SPEC_ARGV+=(-- "${AIRLINE_RUNNER_COMMAND[@]}")
  fi
}

# Run one command in the calling pane. The process is started as a child so airline
# can observe it; explicit stdin inheritance preserves current-pane interaction and
# stdout/stderr remain visible in the pane. A filter gets a tee'd copy of its declared
# stream; a probe performs sequential periodic observations without overlapping.
_runner_execute () {   # <session>; uses parsed run specification
  local session="$1" file pane classifier_health_key
  local filter_health_key probe_health_key
  local classifier_contributor filter_contributor probe_contributor streams=""
  local child_pid filter_pid="" probe_pid="" rc=0 signal="" classification condition message

  pane="$(current_pane)"
  classifier_health_key='command'
  filter_health_key='filter'
  probe_health_key='probe'
  classifier_contributor="$(_runner_element_contributor classifier "$AIRLINE_RUNNER_CLASSIFIER")"
  filter_contributor="$(_runner_element_contributor filter "$AIRLINE_RUNNER_FILTER")"
  probe_contributor="$(_runner_element_contributor probe "$AIRLINE_RUNNER_PROBE")"
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
  signal_problem_report "$session" "$classifier_contributor" load ok ""

  signal_health_set -t "$pane" "$classifier_contributor" "$classifier_health_key" ok
  [[ -z "$AIRLINE_RUNNER_FILTER" ]] || \
    signal_health_set -t "$pane" "$filter_contributor" "$filter_health_key" ok
  [[ -z "$AIRLINE_RUNNER_PROBE" ]] || \
    signal_health_set -t "$pane" "$probe_contributor" "$probe_health_key" ok
  signal_status_set -t "$pane" active

  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    streams=stdout
    if ! runner_stream_prepare "$streams"; then
      runner_stream_cleanup
      signal_problem_report "$session" "$filter_contributor" filter fail "runner filter '$AIRLINE_RUNNER_FILTER' could not prepare"
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
  AIRLINE_RUNNER_PANE="$pane"
  AIRLINE_RUNNER_FILTER_HEALTH_KEY="$filter_health_key"
  AIRLINE_RUNNER_FILTER_CONTRIBUTOR="$filter_contributor"
  AIRLINE_RUNNER_FILTER_PROBLEM_KEY=filter
  AIRLINE_RUNNER_PROBE_HEALTH_KEY="$probe_health_key"
  AIRLINE_RUNNER_PROBE_CONTRIBUTOR="$probe_contributor"
  AIRLINE_RUNNER_PROBE_PROBLEM_KEY=probe
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
    signal_problem_report "$session" "$filter_contributor" filter fail "runner filter '$AIRLINE_RUNNER_FILTER' failed"
  fi
  if [[ -n "$streams" ]]; then
    runner_stream_cleanup
    trap - EXIT
  fi
  # A filter's EOF report describes completed output and remains useful after the
  # process exits. The next run clears this pane-owned health claim at startup.
  [[ -z "$AIRLINE_RUNNER_PROBE" ]] || \
    signal_health_set -t "$pane" "$probe_contributor" "$probe_health_key" ok
  (( rc > 128 )) && signal="$((rc - 128))"

  if classification="$(runner_classifier_run "$rc" "$signal")"; then
    condition="${classification%%$'\t'*}"
    if [[ "$classification" == *$'\t'* ]]; then message="${classification#*$'\t'}"
    else message=""; fi
    signal_problem_report "$session" "$classifier_contributor" classify ok ""
    _runner_finish "$condition" "$message" "$pane" \
      "$classifier_contributor" "$classifier_health_key"
  else
    signal_problem_report "$session" "$classifier_contributor" classify fail \
      "runner classifier '$AIRLINE_RUNNER_CLASSIFIER' failed or emitted an invalid condition"
    signal_health_set -t "$pane" "$classifier_contributor" "$classifier_health_key" ok
    signal_status_set -t "$pane" result
  fi
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
      if [[ "$mode" == run ]]; then _runner_execute "$session"
      else _runner_watch_execute "$session"; fi
      ;;
    pane|window)
      pane="$(current_pane)"; cwd="$(current_path)"
      if [[ "$AIRLINE_RUNNER_PLACEMENT" == pane ]]; then
        spawned="$(runner_open_pane "$pane" "$cwd" "$AIRLINE_RUNNER_PANE_ORIENTATION" env \
          "AIRLINE_RUNNER_SPAWNED=1" "AIRLINE_DIR=$AIRLINE_DIR" \
          "AIRLINE_TMUX=${AIRLINE_TMUX:-tmux}" "$AIRLINE_DIR/airline.sh" \
          runner "$mode" "${AIRLINE_RUNNER_SPEC_ARGV[@]}")"
      else
        spawned="$(runner_open_window "$session" "$cwd" env \
          "AIRLINE_RUNNER_SPAWNED=1" "AIRLINE_DIR=$AIRLINE_DIR" \
          "AIRLINE_TMUX=${AIRLINE_TMUX:-tmux}" "$AIRLINE_DIR/airline.sh" \
          runner "$mode" "${AIRLINE_RUNNER_SPEC_ARGV[@]}")"
      fi
      # The public child command consumes AIRLINE_RUNNER_SPAWNED and arms retention
      # before validation. The parent closes the scheduler race before a very
      # short-lived child can be reaped under load.
      runner_retain_pane "$spawned"
      printf '%s\n' "$spawned"
      ;;
  esac
}

# Watch external state without manufacturing a placeholder command.
_runner_watch_execute () {   # <session>; uses parsed watch specification
  local session="$1" file pane probe_health_key probe_contributor
  local interval watch_pid="$BASHPID" watch_rc=0 sleep_pid=""

  pane="$(current_pane)"
  probe_health_key='watch-probe'
  probe_contributor="$(_runner_element_contributor probe "$AIRLINE_RUNNER_PROBE")"
  file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")"
  runner_probe_load "$file" || return 2
  signal_problem_report "$session" "$probe_contributor" load ok ""

  AIRLINE_RUNNER_SESSION="$session"
  AIRLINE_RUNNER_PANE="$pane"
  AIRLINE_RUNNER_PROBE_HEALTH_KEY="$probe_health_key"
  AIRLINE_RUNNER_PROBE_CONTRIBUTOR="$probe_contributor"
  AIRLINE_RUNNER_PROBE_PROBLEM_KEY=probe
  interval="$(_runner_effective_interval)"

  signal_health_set -t "$pane" "$probe_contributor" "$probe_health_key" ok
  signal_status_set -t "$pane" active

  trap 'watch_rc=130; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' INT
  trap 'watch_rc=143; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' TERM
  trap 'watch_rc=129; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' HUP
  while (( watch_rc == 0 )); do
    if runner_probe_once "$watch_pid" "${AIRLINE_RUNNER_PROBE_ARGS[@]}"; then
      _runner_probe_report "$AIRLINE_RUNNER_PROBE_CONDITION" "$AIRLINE_RUNNER_PROBE_MESSAGE"
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

  signal_health_clear -t "$pane" "$probe_contributor" "$probe_health_key"
  signal_status_clear -t "$pane"
  return "$watch_rc"
}
# CLI delegation targets for runner and its primitives.
runner_classifier_list () {
  local s
  (( $# == 0 )) || command_die "classifier list: takes no arguments"
  s="$(command_current_session)"; catalog_list "$s" classifier
}
runner_classifier_register () { local s; s="$(command_current_session)"; catalog_register "$s" classifier "$@"; }
runner_filter_list () {
  local s
  (( $# == 0 )) || command_die "filter list: takes no arguments"
  s="$(command_current_session)"; catalog_list "$s" filter
}
runner_filter_register () { local s; s="$(command_current_session)"; catalog_register "$s" filter "$@"; }
runner_probe_describe () {
  local file
  (( $# == 1 )) || command_die "probe describe: need exactly one <probe>"
  file="$(catalog_describe_resolve "$(command_current_session)" probe "$1")" || return
  _runner_metadata_require probe "$file" || command_die "probe describe: '$1' has invalid metadata"
  catalog_describe_render "$1" "$file" || return
  command_show_row interval "$(_runner_probe_interval "$file") seconds"
}
runner_probe_list () {
  local s
  (( $# == 0 )) || command_die "probe list: takes no arguments"
  s="$(command_current_session)"; catalog_list "$s" probe
}
runner_probe_register () { local s; s="$(command_current_session)"; catalog_register "$s" probe "$@"; }

runner_describe () { local s; s="$(command_current_session)"; _runner_definition_describe "$s" "$@"; }
runner_list () {
  local s
  (( $# == 0 )) || command_die "runner list: takes no arguments"
  s="$(command_current_session)"; catalog_list "$s" runner
}
runner_register () { local s; s="$(command_current_session)"; catalog_register "$s" runner "$@"; }
_runner_command () {   # <run|watch> [invocation...]
  local mode="$1" spawned="${AIRLINE_RUNNER_SPAWNED:-}" s rc=0; shift
  # Spawn provenance is process-local context, not command grammar. Consume it so
  # the monitored child and any nested airline invocation cannot inherit it.
  unset AIRLINE_RUNNER_SPAWNED
  [[ "$spawned" != 1 ]] || runner_retain_pane "$(current_pane)"
  s="$(command_current_session)"
  _runner_invoke "$s" "$mode" "$@" || rc=$?
  [[ "$spawned" != 1 ]] || _runner_exit_guard_start "$BASHPID"
  return "$rc"
}
runner_run () { _runner_command run "$@"; }
runner_watch () { _runner_command watch "$@"; }

# vim: ft=bash

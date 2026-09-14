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
#   runners/classifiers/<name>: airline_runner_classify <exit-status> <signal> [<arg>...]
#       Print `ok` or `<warn|fail><TAB><message>`.
#
#   runners/filters/<name>: airline_runner_filter <pid> <health> <problem> [<arg>...]
#       Read stdout (or merged stdout/stderr when core requests it) from stdin and
#       Call health/problem with contributor, key, condition, and message.
#       Silence is valid; reports remain until the contributor recovers them.
#
#   runners/probes/<name>: airline_runner_probe <lifecycle-pid> <health> <problem> [<arg>...]
#       Perform one bounded observation and report under element-owned keys.
#       Stdout is uninterpreted user output; signal owns lifecycle and reduction.
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

# An optional parser validates only the element argv, without reporters or process
# identifiers. Its diagnostic is surfaced by invocation validation as a CLI error.
_runner_element_parse () {   # <classify|filter|probe> [<arg>...]
  local parser="airline_runner_${1}_parse"; shift
  if declare -F "$parser" >/dev/null; then
    "$parser" "$@"
  fi
}

runner_classifier_load () {   # <file>
  unset -f airline_runner_classify airline_runner_classify_parse 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_classify >/dev/null
}

runner_classifier_valid () (   # <file> [<arg>...]; validation state never reaches execution
  local file="$1"; shift
  _runner_metadata_require classifier "$file" && runner_classifier_load "$file" &&
    _runner_element_parse classify "$@"
)

runner_classifier_run () {   # <exit-status> <signal> [<arg>...]
  local report condition message rc=0
  report="$(airline_runner_classify "$@")" || rc=$?
  (( rc == 0 )) || return 1
  [[ -n "$report" ]] || return 0
  condition="${report%%$'\t'*}"
  if [[ "$report" == *$'\t'* ]]; then message="${report#*$'\t'}"
  else message=""; fi
  _runner_condition_report_valid "$condition" "$message" || return 1
  printf '%s' "$report"
}

runner_filter_load () {   # <file>
  unset -f airline_runner_filter airline_runner_filter_parse 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_filter >/dev/null
}

runner_filter_valid () (   # <file> [<arg>...]; validation state never reaches execution
  local file="$1"; shift
  _runner_metadata_require filter "$file" && runner_filter_load "$file" &&
    _runner_element_parse filter "$@"
)

AIRLINE_RUNNER_FILTER_PID=""
runner_filter_start () {   # <pid> <health> <problem> <input> [<arg>...]
  local child_pid="$1" health="$2" problem="$3" input="$4"; shift 4
  (
    rc=0
    airline_runner_filter "$child_pid" "$health" "$problem" "$@" || rc=$?
    # Keep a reader alive after an observer fails so tee can still deliver output.
    # Any unread byte proves an early return, even if the action returned zero.
    local unread_count
    unread_count="$(dd bs=1 count=1 2>/dev/null | wc -c)"
    (( unread_count == 0 )) || rc=1
    cat >/dev/null
    exit "$rc"
  ) < "$input" &
  # shellcheck disable=SC2034 # consumed by runner orchestration below
  AIRLINE_RUNNER_FILTER_PID=$!
  [[ -z "${AIRLINE_PROCESS_ID:-}" ]] || _runner_process_add_pid "$AIRLINE_PROCESS_ID" "$AIRLINE_RUNNER_FILTER_PID"
}

runner_filter_wait () {   # <filter-pid>
  local pid="${1:-}" rc=0
  [[ -n "$pid" ]] || return 0
  wait "$pid" 2>/dev/null || rc=$?
  return "$rc"
}

# Unix pipes supply buffering and backpressure. Separate pumps preserve visible
# stdout/stderr destinations; only the observer copy is merged.
AIRLINE_RUNNER_STREAM_DIR=""
AIRLINE_RUNNER_STREAM_INPUT=""
AIRLINE_RUNNER_STREAM_COMMAND=""
AIRLINE_RUNNER_TEE_PID=""

runner_stream_prepare () {
  AIRLINE_RUNNER_STREAM_DIR="${process_dir:-}"
  [[ -n "$AIRLINE_RUNNER_STREAM_DIR" ]] || AIRLINE_RUNNER_STREAM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/airline-runner.XXXXXX")" || return 1
  AIRLINE_RUNNER_STREAM_INPUT="$AIRLINE_RUNNER_STREAM_DIR/input"
  AIRLINE_RUNNER_STREAM_COMMAND="$AIRLINE_RUNNER_STREAM_DIR/command"
  mkfifo "$AIRLINE_RUNNER_STREAM_INPUT" "$AIRLINE_RUNNER_STREAM_COMMAND" || return
  [[ -z "$AIRLINE_RUNNER_FILTER_MERGE" ]] || mkfifo "$AIRLINE_RUNNER_STREAM_DIR/stderr"
}

runner_stream_start () {
  (
    # One open writer spans both pumps, so a gap between streams is not EOF.
    exec 3> "$AIRLINE_RUNNER_STREAM_INPUT"
    if [[ -n "$AIRLINE_RUNNER_FILTER_MERGE" ]]; then
      tee /dev/fd/3 < "$AIRLINE_RUNNER_STREAM_DIR/stderr" >&2 &
      stderr_pump=$!
    fi
    pump_rc=0
    tee /dev/fd/3 < "$AIRLINE_RUNNER_STREAM_COMMAND" || pump_rc=$?
    [[ -z "${stderr_pump:-}" ]] || wait "$stderr_pump" || pump_rc=$?
    exit "$pump_rc"
  ) &
  # shellcheck disable=SC2034 # consumed by runner orchestration below
  AIRLINE_RUNNER_TEE_PID=$!
  [[ -z "${AIRLINE_PROCESS_ID:-}" ]] || _runner_process_add_pid "$AIRLINE_PROCESS_ID" "$AIRLINE_RUNNER_TEE_PID"
}

runner_stream_wait () {
  [[ -n "$AIRLINE_RUNNER_TEE_PID" ]] || return 0
  wait "$AIRLINE_RUNNER_TEE_PID"
}

runner_stream_cleanup () {
  [[ -n "$AIRLINE_RUNNER_STREAM_COMMAND" ]] && rm -f "$AIRLINE_RUNNER_STREAM_COMMAND"
  [[ -n "$AIRLINE_RUNNER_STREAM_INPUT" ]] && rm -f "$AIRLINE_RUNNER_STREAM_INPUT"
  if [[ -n "$AIRLINE_RUNNER_STREAM_DIR" ]]; then
    rm -f "$AIRLINE_RUNNER_STREAM_DIR/stderr"
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
  unset -f airline_runner_probe airline_runner_probe_parse 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$1" || return 1
  declare -F airline_runner_probe >/dev/null || return 1
  # Declared metadata; airline holds it internally for the observation loop.
  AIRLINE_RUNNER_PROBE_INTERVAL="$(_runner_probe_interval "$1")"
}

runner_probe_valid () (   # <file> [<arg>...]; validation state never reaches execution
  local file="$1"; shift
  _runner_metadata_require probe "$file" && runner_probe_load "$file" &&
    _runner_element_parse probe "$@"
)

# Observations mutate contributor-owned claims through the supplied functions.
# Silence is valid; only a nonzero action status is an execution failure.
_runner_probe_loop () {   # <pid> <health> <problem> <result> [<arg>...]
  local lifecycle_pid="$1" health="$2" problem="$3" result="$4" interval rc; shift 4
  interval="$(_runner_effective_interval)"
  while kill -0 "$lifecycle_pid" 2>/dev/null; do
    rc=0
    airline_runner_probe "$lifecycle_pid" "$health" "$problem" "$@" || rc=$?
    kill -0 "$lifecycle_pid" 2>/dev/null || break
    "$result" "$rc"
    sleep "$interval"
  done
}

AIRLINE_RUNNER_PROBE_PID=""
runner_probe_start () {   # <pid> <health> <problem> <result> [<arg>...]
  _runner_probe_loop "$@" &
  # shellcheck disable=SC2034 # consumed by runner orchestration below
  AIRLINE_RUNNER_PROBE_PID=$!
  [[ -z "${AIRLINE_PROCESS_ID:-}" ]] || _runner_process_add_pid "$AIRLINE_PROCESS_ID" "$AIRLINE_RUNNER_PROBE_PID"
}

runner_probe_stop () {   # <probe-pid>
  local pid="${1:-}"
  [[ -n "$pid" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    _runner_process_kill_pid "$pid" TERM || true
  fi
  wait "$pid" 2>/dev/null || true
}

# A named runner is syntactic composition, not lifecycle machinery. Its one required
# function calls validated core callbacks; a definition must keep stdout quiet.
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
AIRLINE_RUNNER_CONFIG_CLASSIFIER_ARGS=()
AIRLINE_RUNNER_CONFIG_FILTER=""
AIRLINE_RUNNER_CONFIG_FILTER_ARGS=()
AIRLINE_RUNNER_CONFIG_FILTER_MERGE=""
AIRLINE_RUNNER_CONFIG_PROBE=""
AIRLINE_RUNNER_CONFIG_PROBE_ARGS=()
AIRLINE_RUNNER_CONFIG_INTERVAL=""
AIRLINE_RUNNER_CONFIG_INVALID=""
AIRLINE_RUNNER_CONFIG_SEEN=""

_runner_configure_collect () {   # <classify|filter|probe> ...
  local field="${1:-}"
  case "$field" in
    classify|filter|probe)
      local name="${2:-}" arg
      local -a args=()
      if (( $# < 2 )) || [[ -z "$name" ]] || _runner_spec_token "$name"; then
        AIRLINE_RUNNER_CONFIG_INVALID=1; return 1
      fi
      shift 2
      for arg in "$@"; do
        if [[ "$field" == filter && "$arg" == --merge-stderr ]]; then
          [[ -z "$AIRLINE_RUNNER_CONFIG_FILTER_MERGE" ]] || {
            AIRLINE_RUNNER_CONFIG_INVALID=1; return 1
          }
          AIRLINE_RUNNER_CONFIG_FILTER_MERGE=1
        elif _runner_spec_token "$arg"; then
          AIRLINE_RUNNER_CONFIG_INVALID=1; return 1
        else
          args+=("$arg")
        fi
      done
      case "$field" in
        classify)
          [[ -z "$AIRLINE_RUNNER_CONFIG_CLASSIFIER" ]] || { AIRLINE_RUNNER_CONFIG_INVALID=1; return 1; }
          AIRLINE_RUNNER_CONFIG_CLASSIFIER="$name"
          AIRLINE_RUNNER_CONFIG_CLASSIFIER_ARGS=("${args[@]}") ;;
        filter)
          [[ -z "$AIRLINE_RUNNER_CONFIG_FILTER" ]] || { AIRLINE_RUNNER_CONFIG_INVALID=1; return 1; }
          AIRLINE_RUNNER_CONFIG_FILTER="$name"
          AIRLINE_RUNNER_CONFIG_FILTER_ARGS=("${args[@]}") ;;
        probe)
          [[ -z "$AIRLINE_RUNNER_CONFIG_PROBE" ]] || { AIRLINE_RUNNER_CONFIG_INVALID=1; return 1; }
          AIRLINE_RUNNER_CONFIG_PROBE="$name"
          AIRLINE_RUNNER_CONFIG_PROBE_ARGS=("${args[@]}") ;;
      esac
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
  AIRLINE_RUNNER_CONFIG_CLASSIFIER_ARGS=()
  AIRLINE_RUNNER_CONFIG_FILTER=""
  AIRLINE_RUNNER_CONFIG_FILTER_ARGS=()
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
      AIRLINE_RUNNER_DEFINITION_ARGV+=(--classify "$AIRLINE_RUNNER_CONFIG_CLASSIFIER" "${AIRLINE_RUNNER_CONFIG_CLASSIFIER_ARGS[@]}")
    if [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER" ]]; then
      AIRLINE_RUNNER_DEFINITION_ARGV+=(--filter "$AIRLINE_RUNNER_CONFIG_FILTER" "${AIRLINE_RUNNER_CONFIG_FILTER_ARGS[@]}")
      [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER_MERGE" ]] && \
        AIRLINE_RUNNER_DEFINITION_ARGV+=(--merge-stderr)
    fi
  fi
  if [[ -n "$AIRLINE_RUNNER_CONFIG_PROBE" ]]; then
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
  local session="$1" name="${2:-}" file probe_args="" classifier_args="" filter_args=""; shift 2 || true
  file="$(catalog_describe_resolve "$session" runner "$name")" || return
  _runner_metadata_require runner "$file" || command_die "runner describe: '$name' has invalid metadata"
  runner_definition_load "$file" || command_die "runner describe: '$name' is invalid"
  runner_definition_configure "$@" || command_die "runner describe: '$name' produced an invalid configuration"
  if (( ${#AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]} )); then
    printf -v probe_args '%q ' "${AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]}"
    probe_args="${probe_args% }"
  fi
  if (( ${#AIRLINE_RUNNER_CONFIG_CLASSIFIER_ARGS[@]} )); then
    printf -v classifier_args '%q ' "${AIRLINE_RUNNER_CONFIG_CLASSIFIER_ARGS[@]}"
  fi
  if (( ${#AIRLINE_RUNNER_CONFIG_FILTER_ARGS[@]} )); then
    printf -v filter_args '%q ' "${AIRLINE_RUNNER_CONFIG_FILTER_ARGS[@]}"
  fi
  catalog_describe_render "$name" "$file" || return
  local modes=run
  [[ -z "$AIRLINE_RUNNER_CONFIG_PROBE" ]] || modes+=' watch'
  command_show_row modes "$modes"
  command_show_row classifier "${AIRLINE_RUNNER_CONFIG_CLASSIFIER:-conventional}"
  [[ -z "$classifier_args" ]] || command_show_row classifier-args "${classifier_args% }"
  command_show_row filter "${AIRLINE_RUNNER_CONFIG_FILTER:-none}"
  [[ -z "$filter_args" ]] || command_show_row filter-args "${filter_args% }"
  [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER_MERGE" ]] && command_show_row filter-input merged-stderr
  command_show_row probe "${AIRLINE_RUNNER_CONFIG_PROBE:-none}"
  [[ -n "$probe_args" ]] && command_show_row probe-args "$probe_args"
  return 0
}

# Globals intentionally cross the filter's background subshell boundary. Each CLI
# invocation owns one run, so concurrent jobs live in separate processes and cannot
# collide here; health claims are isolated by their pane owner.
AIRLINE_RUNNER_PANE=""
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

# These are adapters to the exact mutation functions used by the public CLI.
# They bind only pane context; identities, keys, and recovery belong to the element.
_runner_health_report () {   # <contributor> <key> <condition> [<message>...]
  signal_health_set -t "$AIRLINE_RUNNER_PANE" "$@"
}

_runner_problem_report () {   # <contributor> <key> <condition> [<message>...]
  signal_problem_set -t "$AIRLINE_RUNNER_PANE" "$@"
}

_runner_probe_result () {   # <exit-status>; only core's execution diagnostic
  local condition=ok message=""
  if (( $1 != 0 )); then condition=fail; message="runner probe '$AIRLINE_RUNNER_PROBE' exited with status $1"; fi
  signal_problem_set -t "$AIRLINE_RUNNER_PANE" airline-runner "probe-${AIRLINE_RUNNER_PROBE//[^a-zA-Z0-9_-]/-}" "$condition" "$message"
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
  [[ -n "${AIRLINE_PROCESS_ID:-}" ]] || signal_status_set -t "$pane" result
}

# Parsed runner specification. The CLI composes at most one element of each type for
# one operation. Element arguments end at the next recognized runner option, at `--`
# for run, or at argv exhaustion for watch.
AIRLINE_RUNNER_PLACEMENT=here
AIRLINE_RUNNER_PANE_ORIENTATION=""
AIRLINE_RUNNER_CLASSIFIER=""
AIRLINE_RUNNER_CLASSIFIER_ARGS=()
AIRLINE_RUNNER_FILTER=""
AIRLINE_RUNNER_FILTER_ARGS=()
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
    [[ -z "$boundary" || ${#command[@]} -gt 0 ]] || \
      command_die "runner run: named runner '$name' needs -- <command>"
    runner_definition_configure "${extra[@]}" || \
      command_die "runner run: runner '$name' produced an invalid configuration"
    runner_definition_project run
    AIRLINE_RUNNER_INVOCATION_ARGV=(
      "${placement[@]}" "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
    )
    if [[ -n "$boundary" ]]; then
      AIRLINE_RUNNER_INVOCATION_ARGV+=(-- "${command[@]}")
    fi
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
    --pane|--window|--classify|--filter|--probe|--interval|--merge-stderr|--) return 0 ;;
    *) return 1 ;;
  esac
}

_runner_parse () {   # <run|watch> [spec...]
  local mode="$1" placement_seen=""; shift
  AIRLINE_RUNNER_PLACEMENT=here
  AIRLINE_RUNNER_PANE_ORIENTATION=""
  AIRLINE_RUNNER_CLASSIFIER=""
  AIRLINE_RUNNER_CLASSIFIER_ARGS=()
  AIRLINE_RUNNER_FILTER=""
  AIRLINE_RUNNER_FILTER_ARGS=()
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
        ! _runner_spec_token "$2" || command_die "runner run: --classify requires <name>"
        AIRLINE_RUNNER_CLASSIFIER="$2"; shift 2
        while (( $# )) && ! _runner_spec_token "$1"; do
          AIRLINE_RUNNER_CLASSIFIER_ARGS+=("$1"); shift
        done
        ;;
      --filter)
        [[ "$mode" == run ]] || command_die "runner watch: --filter is not applicable"
        [[ -z "$AIRLINE_RUNNER_FILTER" ]] || command_die "runner run: filter already specified"
        [[ $# -ge 2 && -n "$2" ]] || command_die "runner run: --filter requires <name>"
        ! _runner_spec_token "$2" || command_die "runner run: --filter requires <name>"
        AIRLINE_RUNNER_FILTER="$2"; shift 2
        while (( $# )) && ! _runner_spec_token "$1"; do
          AIRLINE_RUNNER_FILTER_ARGS+=("$1"); shift
        done
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
        ! _runner_spec_token "$2" || command_die "runner $mode: --probe requires <name>"
        AIRLINE_RUNNER_PROBE="$2"; shift 2
        while (( $# )) && ! _runner_spec_token "$1"; do
          AIRLINE_RUNNER_PROBE_ARGS+=("$1"); shift
        done
        ;;
      --)
        [[ "$mode" == run ]] || command_die "runner watch: unexpected -- (watch ends at end of arguments)"
        shift
        (( $# > 0 )) || command_die "runner run: need -- <command>"
        AIRLINE_RUNNER_COMMAND=("$@"); break ;;
      --merge-stderr)
        [[ -z "$AIRLINE_RUNNER_FILTER_MERGE" ]] || command_die "runner $mode: --merge-stderr already specified"
        AIRLINE_RUNNER_FILTER_MERGE=1; shift ;;
      *) command_die "runner $mode: unknown option '$1'" ;;
    esac
  done

  if [[ "$mode" == run ]]; then
    [[ ${#AIRLINE_RUNNER_COMMAND[@]} -gt 0 || -n "$AIRLINE_RUNNER_PROBE" ]] || command_die "runner run: need -- <command> or --probe <name>"
    [[ ${#AIRLINE_RUNNER_COMMAND[@]} -gt 0 || -z "$AIRLINE_RUNNER_FILTER" ]] || command_die "runner run: --filter requires -- <command>"
    [[ -n "$AIRLINE_RUNNER_CLASSIFIER" ]] || AIRLINE_RUNNER_CLASSIFIER=conventional
  else
    [[ -n "$AIRLINE_RUNNER_PROBE" ]] || command_die "runner watch: need --probe <name> [<arg>...]"
  fi
  [[ -z "$AIRLINE_RUNNER_INTERVAL" || -n "$AIRLINE_RUNNER_PROBE" ]] || \
    command_die "runner $mode: --interval paces --probe observations"
  [[ -z "$AIRLINE_RUNNER_FILTER_MERGE" || -n "$AIRLINE_RUNNER_FILTER" ]] || \
    command_die "runner $mode: --merge-stderr requires --filter"
}

_runner_validate_spec () {   # <session> <run|watch>
  local session="$1" mode="$2" file diagnostic
  if [[ "$mode" == run ]]; then
    file="$(_runner_element_file "$session" classify "$AIRLINE_RUNNER_CLASSIFIER")" || \
      command_die "runner run: classifier '$AIRLINE_RUNNER_CLASSIFIER' not found"
    diagnostic="$(runner_classifier_valid "$file" "${AIRLINE_RUNNER_CLASSIFIER_ARGS[@]}" 2>&1)" ||
        command_die "runner run: classifier '$AIRLINE_RUNNER_CLASSIFIER' is invalid${diagnostic:+: $diagnostic}"
    if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
      file="$(_runner_element_file "$session" filter "$AIRLINE_RUNNER_FILTER")" || \
        command_die "runner run: filter '$AIRLINE_RUNNER_FILTER' not found"
      diagnostic="$(runner_filter_valid "$file" "${AIRLINE_RUNNER_FILTER_ARGS[@]}" 2>&1)" ||
        command_die "runner run: filter '$AIRLINE_RUNNER_FILTER' is invalid${diagnostic:+: $diagnostic}"
    fi
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")" || \
      command_die "runner $mode: probe '$AIRLINE_RUNNER_PROBE' not found"
    diagnostic="$(runner_probe_valid "$file" "${AIRLINE_RUNNER_PROBE_ARGS[@]}" 2>&1)" ||
        command_die "runner $mode: probe '$AIRLINE_RUNNER_PROBE' is invalid${diagnostic:+: $diagnostic}"
  fi
}

AIRLINE_RUNNER_SPEC_ARGV=()
_runner_normalize_spec () {   # <run|watch>
  local mode="$1"
  AIRLINE_RUNNER_SPEC_ARGV=()
  [[ "$mode" == run ]] && AIRLINE_RUNNER_SPEC_ARGV+=(--classify "$AIRLINE_RUNNER_CLASSIFIER" "${AIRLINE_RUNNER_CLASSIFIER_ARGS[@]}")
  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    AIRLINE_RUNNER_SPEC_ARGV+=(--filter "$AIRLINE_RUNNER_FILTER" "${AIRLINE_RUNNER_FILTER_ARGS[@]}")
    [[ -n "$AIRLINE_RUNNER_FILTER_MERGE" ]] && AIRLINE_RUNNER_SPEC_ARGV+=(--merge-stderr)
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    [[ -z "$AIRLINE_RUNNER_INTERVAL" ]] || \
      AIRLINE_RUNNER_SPEC_ARGV+=(--interval "$AIRLINE_RUNNER_INTERVAL")
    AIRLINE_RUNNER_SPEC_ARGV+=(--probe "$AIRLINE_RUNNER_PROBE" "${AIRLINE_RUNNER_PROBE_ARGS[@]}")
  fi
  # An `if` rather than a trailing `&&`: watch normalizes successfully and must not
  # report the mode test's status as failure.
  if [[ "$mode" == run && ${#AIRLINE_RUNNER_COMMAND[@]} -gt 0 ]]; then
    AIRLINE_RUNNER_SPEC_ARGV+=(-- "${AIRLINE_RUNNER_COMMAND[@]}")
  fi
}

# Run one command in the calling pane. The process is started as a child so airline
# can observe it; explicit stdin inheritance preserves current-pane interaction and
# stdout/stderr remain visible in the pane. A filter gets a tee'd copy of its declared
# stream; a probe performs sequential periodic observations without overlapping.
_runner_execute () {   # <session>; uses parsed run specification
  local session="$1" file pane classifier_health_key
  local classifier_contributor streams=""
  local child_pid filter_pid="" probe_pid="" rc=0 signal="" classification condition message
  local stream_rc=0 filter_rc=0

  pane="$(current_pane)"
  classifier_health_key='command'
  classifier_contributor="$(_runner_element_contributor classifier "$AIRLINE_RUNNER_CLASSIFIER")"
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

  signal_health_set -t "$pane" "$classifier_contributor" "$classifier_health_key" ok
  [[ -n "${AIRLINE_PROCESS_ID:-}" ]] || signal_status_set -t "$pane" active

  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    streams=stdout
    if ! runner_stream_prepare "$streams"; then
      runner_stream_cleanup
      signal_problem_set -t "$pane" airline-runner "filter-${AIRLINE_RUNNER_FILTER//[^a-zA-Z0-9_-]/-}" fail "runner filter '$AIRLINE_RUNNER_FILTER' could not prepare"
      return 2
    fi
    trap runner_stream_cleanup EXIT
  fi

  # Launch before opening the tee readers: a selected FIFO blocks the child briefly,
  # allowing airline to obtain its PID for the filter contract.
  case "$streams:$AIRLINE_RUNNER_FILTER_MERGE" in
    stdout:1) _runner_command_start <&0 > "$AIRLINE_RUNNER_STREAM_COMMAND" 2> "$AIRLINE_RUNNER_STREAM_DIR/stderr" & ;;
    stdout:)  _runner_command_start <&0 > "$AIRLINE_RUNNER_STREAM_COMMAND" & ;;
    :)        _runner_command_start <&0 & ;;
  esac
  child_pid=$!
  [[ -z "${AIRLINE_PROCESS_ID:-}" ]] || _runner_process_add_pid "$AIRLINE_PROCESS_ID" "$child_pid"

  AIRLINE_RUNNER_PANE="$pane"
  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    runner_filter_start "$child_pid" _runner_health_report _runner_problem_report "$AIRLINE_RUNNER_STREAM_INPUT" "${AIRLINE_RUNNER_FILTER_ARGS[@]}"
    filter_pid="$AIRLINE_RUNNER_FILTER_PID"
    runner_stream_start
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    runner_probe_start "$child_pid" _runner_health_report _runner_problem_report _runner_probe_result \
      "${AIRLINE_RUNNER_PROBE_ARGS[@]}"
    probe_pid="$AIRLINE_RUNNER_PROBE_PID"
  fi

  wait "$child_pid" || rc=$?
  [[ -z "${AIRLINE_PROCESS_ID:-}" ]] || _runner_process_remove_pid "$AIRLINE_PROCESS_ID" "$child_pid" || true
  runner_probe_stop "$probe_pid"
  if [[ -n "$probe_pid" ]]; then
    [[ -z "${AIRLINE_PROCESS_ID:-}" ]] || _runner_process_remove_pid "$AIRLINE_PROCESS_ID" "$probe_pid" || true
  fi
  if [[ -n "$filter_pid" ]]; then
    runner_stream_wait || stream_rc=$?
    [[ -z "${AIRLINE_PROCESS_ID:-}" ]] || _runner_process_remove_pid "$AIRLINE_PROCESS_ID" "$AIRLINE_RUNNER_TEE_PID" || true
  fi
  runner_filter_wait "$filter_pid" || filter_rc=$?
  if [[ -n "$filter_pid" ]]; then
    [[ -z "${AIRLINE_PROCESS_ID:-}" ]] || _runner_process_remove_pid "$AIRLINE_PROCESS_ID" "$filter_pid" || true
  fi
  if (( filter_rc != 0 || stream_rc != 0 )); then
    signal_problem_set -t "$pane" airline-runner "filter-${AIRLINE_RUNNER_FILTER//[^a-zA-Z0-9_-]/-}" fail "runner filter '$AIRLINE_RUNNER_FILTER' failed"
  elif [[ -n "$filter_pid" ]]; then
    signal_problem_set -t "$pane" airline-runner "filter-${AIRLINE_RUNNER_FILTER//[^a-zA-Z0-9_-]/-}" ok
  fi
  if [[ -n "$streams" ]]; then
    runner_stream_cleanup
    trap - EXIT
  fi
  if [[ -n "${AIRLINE_RUNNER_TERMINATION_FILE:-}" && -s "$AIRLINE_RUNNER_TERMINATION_FILE" ]]; then
    IFS=$'\t' read -r termination_kind termination_signal < "$AIRLINE_RUNNER_TERMINATION_FILE"
    [[ "$termination_kind" == signal ]] && signal="$termination_signal"
  elif (( rc > 128 )); then
    signal="$((rc - 128))"
  fi

  if classification="$(runner_classifier_run "$rc" "$signal" "${AIRLINE_RUNNER_CLASSIFIER_ARGS[@]}")"; then
    condition="${classification%%$'\t'*}"
    if [[ "$classification" == *$'\t'* ]]; then message="${classification#*$'\t'}"
    else message=""; fi
    signal_problem_set -t "$pane" "$classifier_contributor" classify ok ""
    _runner_finish "$condition" "$message" "$pane" \
      "$classifier_contributor" "$classifier_health_key"
  else
    signal_problem_set -t "$pane" "$classifier_contributor" classify fail \
      "runner classifier '$AIRLINE_RUNNER_CLASSIFIER' failed or emitted an invalid condition"
    signal_health_set -t "$pane" "$classifier_contributor" "$classifier_health_key" ok
    [[ -n "${AIRLINE_PROCESS_ID:-}" ]] || signal_status_set -t "$pane" result
  fi
  return "$rc"
}

_runner_command_start () {
  local marker="${AIRLINE_RUNNER_TERMINATION_FILE:-}" rc
  trap '[[ -z "$marker" ]] || printf "signal\tINT\n" > "$marker"; trap - INT; kill -INT $$' INT
  trap '[[ -z "$marker" ]] || printf "signal\tTERM\n" > "$marker"; trap - TERM; kill -TERM $$' TERM
  "${AIRLINE_RUNNER_COMMAND[@]}"
  rc=$?
  [[ -z "$marker" ]] || printf 'exit\t%s\n' "$rc" > "$marker"
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
      _runner_process_launch "$session" "$mode"
      ;;
    pane|window)
      pane="$(current_pane)"; cwd="$(current_path)"
      if [[ "$mode" == watch ]]; then
        if [[ "$AIRLINE_RUNNER_PLACEMENT" == pane ]]; then
          spawned="$(runner_open_pane "$pane" "$cwd" "$AIRLINE_RUNNER_PANE_ORIENTATION")" || return
        else
          spawned="$(runner_open_window "$session" "$cwd")" || return
        fi
        TMUX_PANE="$spawned" _runner_process_launch "$session" watch
        return
      fi
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
  local session="$1" file pane
  local interval watch_pid="$BASHPID" watch_rc=0 sleep_pid="" probe_rc

  pane="$(current_pane)"
  file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")"
  runner_probe_load "$file" || return 2

  AIRLINE_RUNNER_PANE="$pane"
  interval="$(_runner_effective_interval)"

  [[ -n "${AIRLINE_PROCESS_ID:-}" ]] || signal_status_set -t "$pane" active

  trap 'watch_rc=130; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' INT
  trap 'watch_rc=143; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' TERM
  trap 'watch_rc=129; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' HUP
  while (( watch_rc == 0 )); do
    probe_rc=0
    airline_runner_probe "$watch_pid" _runner_health_report _runner_problem_report "${AIRLINE_RUNNER_PROBE_ARGS[@]}" || probe_rc=$?
    _runner_probe_result "$probe_rc"
    (( watch_rc == 0 )) || break
    sleep "$interval" &
    sleep_pid=$!
    wait "$sleep_pid" 2>/dev/null || true
    sleep_pid=""
  done
  trap - INT TERM HUP

  [[ -n "${AIRLINE_PROCESS_ID:-}" ]] || signal_status_clear -t "$pane"
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

# Process records describe live invocations, not catalog definitions. Stop requests
# are addressed to a unique record; the CLI never signals a PID read from storage.
_runner_process_record () { # <id> <pane> <mode> <pid> <spec> <session>
  coll_set global server process "$1" "$2" "$3" "$4" active "$5" "$4" "$6"
}

_runner_process_add_pid () { # <id> <pid>
  [[ "$2" =~ ^[0-9]+$ ]] || return 2
  with_global_transaction process _runner_process_add_pid_unlocked "$@"
}

# Supervisor and worker both update this tuple. Read it only after acquiring the
# same lock used by stop and retirement, and hold that lock through publication.
_runner_process_add_pid_unlocked () { # <id> <pid>; caller owns process transaction
  local tuple pane mode supervisor state spec pids session
  coll_get_into tuple global server process "$1" || return
  [[ -n "$tuple" ]] || return 1
  IFS=$'\t' read -r pane mode supervisor state spec pids session <<< "$tuple"
  case " ${pids:-} " in *" $2 "*) return 0 ;; esac
  coll_set global server process "$1" "$pane" "$mode" "$supervisor" "$state" "$spec" "${pids:+$pids }$2" "$session"
}

_runner_process_remove_pid () { # <id> <pid>
  with_global_transaction process _runner_process_remove_pid_unlocked "$@"
}

_runner_process_remove_pid_unlocked () { # <id> <pid>; caller owns process transaction
  local tuple pane mode supervisor state spec pids session kept pid
  coll_get_into tuple global server process "$1" || return
  [[ -n "$tuple" ]] || return 0
  IFS=$'\t' read -r pane mode supervisor state spec pids session <<< "$tuple"
  kept=""
  for pid in $pids; do [[ "$pid" == "$2" ]] || kept="${kept:+$kept }$pid"; done
  coll_set global server process "$1" "$pane" "$mode" "$supervisor" "$state" "$spec" "$kept" "$session"
}

_runner_process_kill_pid () { # <pid> <signal>
  local pid="$1" signal="$2"
  kill -"$signal" "$pid" 2>/dev/null && return 0
  kill -0 "$pid" 2>/dev/null || return 0
  printf 'airline: cannot signal owned process %s with %s\n' "$pid" "$signal" >&2
  return 1
}

_runner_process_reap_stale () { # <id> <tuple>
  local id="$1" tuple="$2" pane mode supervisor state spec pids session
  IFS=$'\t' read -r pane mode supervisor state spec pids session <<< "$tuple"
  # Once the supervisor is gone, recorded child numbers are no longer evidence
  # of ownership. Retire bookkeeping without signaling potentially reused PIDs.
  if ! kill -0 "$supervisor" 2>/dev/null; then
    if [[ "$(resolve_pane "$pane" 2>/dev/null)" == "$pane" ]]; then
      signal_process_status "$pane" "$id" clear || return
    fi
    with_global_transaction process _runner_process_remove "$id"
  fi
}

_runner_process_remove () { # <id>
  coll_unregister global server process "$1"
  coll_unregister global server process-stop "$1"
}

_runner_process_request_stop () { # <id>
  local tuple pane mode pid state spec pids session
  coll_get_into tuple global server process "$1" || return
  if [[ -z "$tuple" ]]; then
    printf "airline: process '%s' already finished\n" "$1"
    return 0
  fi
  IFS=$'\t' read -r pane mode pid state spec pids session <<< "$tuple"
  if ! kill -0 "$pid" 2>/dev/null; then
    # Reconciliation runs outside this transaction so status uses its own lock.
    return 0
  fi
  coll_set global server process "$1" "$pane" "$mode" "$pid" stopping "$spec" "$pids" "$session" || return
  coll_set global server process-stop "$1" stop || return
  # The supervisor consumes this request and signals its own children. The CLI
  # need not race a numeric supervisor PID with reuse between check and kill.
}

runner_process_list () {
  (( $# == 0 )) || command_die 'process list: takes no arguments'
  local members id tuple pane mode pid state spec pids session
  coll_members_into members global server process || return
  for id in $members; do
    coll_get_into tuple global server process "$id" || return
    [[ -n "$tuple" ]] || continue
    IFS=$'\t' read -r pane mode pid state spec pids session <<< "$tuple"
    if [[ "$(resolve_pane "$pane" 2>/dev/null)" != "$pane" ]] || ! kill -0 "$pid" 2>/dev/null; then
      _runner_process_reap_stale "$id" "$tuple"
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$pane" "$mode" "$state" "$spec" "${pids:-}"
  done
}

runner_process_show () {
  [[ $# == 1 && "$1" =~ ^p-[a-zA-Z0-9]+$ ]] || command_die 'process show: need <process-id>'
  local tuple pane mode pid state spec pids session
  coll_get_into tuple global server process "$1" || return
  [[ -n "$tuple" ]] || command_die "process show: unknown process '$1'"
  IFS=$'\t' read -r pane mode pid state spec pids session <<< "$tuple"
  if [[ "$(resolve_pane "$pane" 2>/dev/null)" != "$pane" ]] || ! kill -0 "$pid" 2>/dev/null; then
    _runner_process_reap_stale "$1" "$tuple"
    command_die "process show: process '$1' is no longer active"
  fi
  command_show_row id "$1"
  command_show_row pane "$pane"
  command_show_row mode "$mode"
  command_show_row pid "$pid"
  command_show_row state "$state"
  command_show_row specification "$spec"
  command_show_row pids "${pids:-}"
}

runner_process_stop () {
  [[ $# == 1 && "$1" =~ ^p-[a-zA-Z0-9]+$ ]] || command_die 'process stop: need <process-id>'
  with_global_transaction process _runner_process_request_stop "$1" ||
    command_die "process stop: could not request stop for '$1'"
  # A successful stop means the supervisor has cleaned up and retired its record.
  local attempt tuple pane mode pid state spec pids session
  for ((attempt=0; attempt<100; attempt++)); do
    coll_get_into tuple global server process "$1" || return
    [[ -n "$tuple" ]] || return 0
    IFS=$'\t' read -r pane mode pid state spec pids session <<< "$tuple"
    if ! kill -0 "$pid" 2>/dev/null; then
      _runner_process_reap_stale "$1" "$tuple" || return
      printf "airline: process '%s' already finished\n" "$1"
      return 0
    fi
    coll_has global server process "$1" || return 0
    sleep 0.1
  done
  command_die "process stop: '$1' has not finished cleanup; inspect with process show"
}

_runner_process_cleanup () {
  local record tuple record_pids owned_pid record_session
  trap - EXIT
  trap '' HUP INT TERM
  if record="$(coll_get global server process "$AIRLINE_PROCESS_ID" 2>/dev/null)"; then
    IFS=$'\t' read -r _ _ _ _ _ record_pids record_session <<< "$record"
    for owned_pid in $record_pids; do
      [[ "$owned_pid" == "$BASHPID" ]] || _runner_process_kill_pid "$owned_pid" TERM || true
    done
  fi
  if [[ -n "${process_worker:-}" ]] && kill -0 "$process_worker" 2>/dev/null; then
    _runner_process_kill_pid "$process_worker" TERM || true
  fi
  [[ -z "${process_worker:-}" ]] || wait "$process_worker" 2>/dev/null || true
  if [[ "$(resolve_pane "$process_pane" 2>/dev/null)" == "$process_pane" ]]; then
    signal_process_status "$process_pane" "$AIRLINE_PROCESS_ID" "$process_result" || true
  else
    signal_problem_report "$record_session" airline-runner "process-${AIRLINE_PROCESS_ID#p-}" fail \
      "process '$AIRLINE_PROCESS_ID' lost its owning pane before cleanup" || true
  fi
  with_global_transaction process _runner_process_remove "$AIRLINE_PROCESS_ID" 2>/dev/null || true
  # Only invocation-owned control/FIFO files; command output is never spooled.
  rm -f "$process_dir/ready" "$process_dir/input" "$process_dir/command" "$process_dir/stderr" "$process_dir/termination"
  rmdir "$process_dir" 2>/dev/null || true
}

_runner_process_execute () ( # <session> <mode> <control-directory>
  local session="$1" mode="$2" process_dir="$3" process_pane process_worker=""
  local process_result=clear process_rc=0 spec stop="" termination_file
  AIRLINE_PROCESS_ID="p-${process_dir##*.}"
  termination_file="$process_dir/termination"
  AIRLINE_RUNNER_TERMINATION_FILE="$termination_file"
  process_pane="$(current_pane)" || return
  printf -v spec '%q ' "${AIRLINE_RUNNER_SPEC_ARGV[@]}"
  trap '_runner_process_cleanup' EXIT
  trap 'printf "signal\\tHUP\\n" > "$termination_file"; exit 129' HUP
  trap 'printf "signal\\tINT\\n" > "$termination_file"; exit 130' INT
  trap 'printf "signal\\tTERM\\n" > "$termination_file"; exit 143' TERM
  with_global_transaction process _runner_process_record "$AIRLINE_PROCESS_ID" \
    "$process_pane" "$mode" "$BASHPID" "${spec% }" "$session" || return
  signal_process_status "$process_pane" "$AIRLINE_PROCESS_ID" active || return
  printf '%s\n' "$AIRLINE_PROCESS_ID" > "$process_dir/ready"
  if [[ ${#AIRLINE_RUNNER_COMMAND[@]} -gt 0 ]]; then
    ( trap - EXIT HUP INT TERM; _runner_execute "$session" ) <&0 &
  else
    ( trap - EXIT HUP INT TERM; _runner_watch_execute "$session" ) <&0 &
  fi
  process_worker=$!
  _runner_process_add_pid "$AIRLINE_PROCESS_ID" "$process_worker"
  while kill -0 "$process_worker" 2>/dev/null; do
    [[ "$(resolve_pane "$process_pane" 2>/dev/null)" == "$process_pane" ]] || return 143
    coll_get_into stop global server process-stop "$AIRLINE_PROCESS_ID" || return 2
    [[ -z "$stop" ]] || return 143
    sleep 0.1 &
    wait $! || true
  done
  wait "$process_worker" || process_rc=$?
  _runner_process_remove_pid "$AIRLINE_PROCESS_ID" "$process_worker" || true
  process_worker=""
  [[ ${#AIRLINE_RUNNER_COMMAND[@]} == 0 ]] || process_result=result
  return "$process_rc"
)

_runner_process_launch () { # <session> <run|watch>
  local directory watcher id
  directory="$(mktemp -d "${TMPDIR:-/tmp}/airline-process.XXXXXXXXXX")" || return
  if [[ "$2" == run ]]; then
    _runner_process_execute "$1" "$2" "$directory"
  else
    _runner_process_execute "$1" "$2" "$directory" </dev/null >/dev/null 2>&1 &
    watcher=$!
    while [[ ! -s "$directory/ready" ]]; do
      if ! kill -0 "$watcher" 2>/dev/null; then
        wait "$watcher" || true
        command_die 'runner watch: process failed to start'
      fi
      sleep 0.05
    done
    IFS= read -r id < "$directory/ready"
    printf '%s\n' "$id"
  fi
}

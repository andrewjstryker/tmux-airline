#!/usr/bin/env bash
#
# signal.sh — status, health, and problem lifecycle policy.
#
# Status is pane-owned workflow state reduced at window scope; completed results are
# deleted after observation.
# Health is a persistent keyed window condition. Problems are a server-global
# lifecycle ledger whose active claims retain their pane or session origin.
#
# Signal owns validation, transactional mutation, projection orchestration, redraw
# gating, and observation cleanup for completed status results.

# shellcheck shell=bash

signal_condition_valid () {
  local level
  for level in "${AIRLINE_CONDITION_LEVELS[@]}"; do [[ "$level" == "$1" ]] && return 0; done
  return 1
}

_signal_status_valid () {
  local level
  for level in "${AIRLINE_STATUS_LEVELS[@]}"; do [[ "$level" == "$1" ]] && return 0; done
  return 1
}

_signal_validate_key () {   # <command> <key>
  local command="$1" key="$2"
  [[ -n "$key" ]] || command_die "$command: need <key>"
  [[ "$key" != *[[:space:]]* ]] || command_die "$command: key must not contain whitespace"
  [[ "$key" != *:* ]] || command_die "$command: key must not contain ':'"
}

_signal_validate_contributor () {   # <command> <contributor>
  local command="$1" contributor="$2"
  [[ -n "$contributor" ]] || command_die "$command: need <contributor>"
  [[ "$contributor" != *[[:space:]]* ]] || \
    command_die "$command: contributor must not contain whitespace"
  [[ "$contributor" != *:* ]] || command_die "$command: contributor must not contain ':'"
}

_signal_claim_id () { printf '%s:%s' "$1" "$2"; }

_signal_validate_condition () {   # <command> <ok|warn|fail> <message>
  local command="$1" level="$2" message="$3"
  signal_condition_valid "$level" || command_die "$command: invalid level '$level'"
  [[ "$message" != *$'\t'* ]] || command_die "$command: message must not contain a tab"
  case "$level" in
    ok) [[ -z "$message" ]] || command_die "$command: ok takes no <message>" ;;
    warn|fail) [[ -n "$message" ]] || command_die "$command: need <message>" ;;
  esac
}

_signal_resolve_window () {   # <destination> <command> [<target>]
  local -n destination="$1"
  local command="$2" target="${3:-}" resolved
  if [[ -z "$target" ]]; then
    resolved="$(current_window)" || command_die "$command: cannot resolve current window"
    target="$resolved"
  fi
  resolved="$(resolve_window "$target")" || command_die "$command: cannot resolve window '$target'"
  [[ -n "$resolved" ]] || command_die "$command: cannot resolve window '$target'"
  destination="$resolved"
}

# Every mutation follows one pipeline: transact at the signal's native owner,
# run its lifecycle policy, then reduce/project and redraw only if the projected
# scalar changed. Lifecycle callbacks return storage change through a destination
# variable and never perform presentation work themselves.
_signal_project_and_redraw () {   # <window|global> <owner> <status|health|problem>
  local scope="$1" owner="$2" namespace="$3" changed="" projector="render_${3}_project"
  "$projector" changed "$owner" || return
  [[ -n "$changed" ]] || return 0
  if [[ "$scope" == global ]]; then redraw_all; else redraw; fi
}

_signal_with_transaction () {   # <window|global> <owner> <namespace> <callback> [<arg>...]
  local scope="$1" owner="$2" namespace="$3" callback="$4"; shift 4
  case "$scope" in
    window) with_window_transaction "$owner" "$namespace" "$callback" "$@" ;;
    global) with_global_transaction "$namespace" "$callback" "$@" ;;
  esac
}

_signal_apply_unlocked () {   # <scope> <owner> <namespace> <lifecycle> [<arg>...]
  local scope="$1" owner="$2" namespace="$3" lifecycle="$4" storage_changed=""; shift 4
  "$lifecycle" storage_changed "$@" || return
  [[ -n "$storage_changed" ]] || return 0
  _signal_project_and_redraw "$scope" "$owner" "$namespace"
}

_signal_apply () {   # <window|global> <owner> <namespace> <lifecycle> [<arg>...]
  local scope="$1" owner="$2" namespace="$3"; shift 3
  _signal_with_transaction "$scope" "$owner" "$namespace" _signal_apply_unlocked \
    "$scope" "$owner" "$namespace" "$@"
}

#-----------------------------------------------------------------------------#
# Health lifecycle policy
#-----------------------------------------------------------------------------#

_signal_health_store_unlocked () {   # <destination> <window> <contributor> <key> <level> <message>
  local -n destination="$1"
  local owner="$2" contributor="$3" key="$4" level="$5" message="$6"
  local id tuple badge state previous_level desired has_rc=0
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"

  tuple="$(coll_get window "$owner" health "$id")" || return
  coll_has window "$owner" health "$id" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"

  if [[ "$level" == ok ]]; then
    if (( has_rc == 1 )) && [[ -z "$tuple" ]]; then return 0; fi
    coll_unregister window "$owner" health "$id" || return
  else
    state=active
    if (( has_rc == 0 )); then
      IFS=$'\t' read -r badge state previous_level _ <<< "$tuple"
      [[ "$state" == acknowledged && "$previous_level" == "$level" ]] || state=active
    fi
    badge="$level"
    [[ "$state" == acknowledged ]] && badge=none
    desired="$(printf '%s\t%s\t%s\t%s' "$badge" "$state" "$level" "$message")"
    if (( has_rc == 0 )) && [[ "$tuple" == "$desired" ]]; then return 0; fi
    coll_set window "$owner" health "$id" "$badge" "$state" "$level" "$message" || return
  fi

  destination=1
}

_signal_health_ack_unlocked () {   # <destination> <window> <contributor> <key>
  local -n destination="$1"
  local owner="$2" contributor="$3" key="$4" id tuple badge state level message
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"
  tuple="$(coll_get window "$owner" health "$id")" || return
  [[ -n "$tuple" ]] || return 0
  IFS=$'\t' read -r badge state level message <<< "$tuple"
  [[ "$state" != acknowledged ]] || return 0
  coll_set window "$owner" health "$id" none acknowledged "$level" "$message" || return
  destination=1
}

_signal_health_show_unlocked () {   # <active-only|all> <window> [<contributor> [<key>]]
  local visibility="$1" owner="$2" contributor="${3:-}" key="${4:-}" id
  local members member tuple badge state level message member_contributor member_key
  if [[ -n "$key" ]]; then
    id="$(_signal_claim_id "$contributor" "$key")"
    tuple="$(coll_get window "$owner" health "$id")" || return
    [[ -n "$tuple" ]] || return 0
    IFS=$'\t' read -r badge state level message <<< "$tuple"
    [[ "$visibility" == all || "$state" == active ]] || return 0
    if [[ "$visibility" == all ]]; then printf '%s\t%s\t%s\n' "$state" "$level" "$message"
    else printf '%s\t%s\n' "$level" "$message"; fi
    return
  fi
  members="$(coll_members window "$owner" health)" || return
  for member in $members; do
    member_contributor="${member%%:*}"; member_key="${member#*:}"
    [[ -z "$contributor" || "$member_contributor" == "$contributor" ]] || continue
    tuple="$(coll_get window "$owner" health "$member")" || return
    IFS=$'\t' read -r badge state level message <<< "$tuple"
    [[ "$visibility" == all || "$state" == active ]] || continue
    if [[ "$visibility" == all ]]; then
      command_show_row "$member_contributor" "$member_key  $state  $level${message:+  $message}"
    else
      command_show_row "$member_contributor" "$member_key  $level${message:+  $message}"
    fi
  done
}

#-----------------------------------------------------------------------------#
# Status — one workflow phase per pane, reduced at window scope
#-----------------------------------------------------------------------------#

_signal_ensure_result_hook () {
  local revision_option
  revision_option="$(prv_name status-revision)"
  opt_set_global focus-events on || return
  hook_set "pane-focus-out[90]" \
    "run-shell -b \"if [ -n '#{${revision_option}}' ]; then '$AIRLINE_DIR/airline.sh' status _observed-result '#{pane_id}' '#{${revision_option}}'; fi\""
}

_signal_status_next_revision () {   # <destination> <pane>
  local -n destination="$1"
  local pane="$2" current changed=""
  current="$(prv_get_pane "$pane" status-revision)" || return
  [[ -z "$current" || "$current" =~ ^[0-9]+$ ]] || command_die "status: invalid private revision"
  destination="$(( ${current:-0} + 1 ))"
  prv_setif_pane changed "$pane" status-revision "$destination"
}

_signal_status_set_unlocked () {   # <destination> <window> <pane> <pane-member> <value>
  local -n destination="$1"
  local win="$2" pane="$3" member="$4" value="$5"
  local tuple current revision has_rc=0
  destination=""
  tuple="$(coll_get window "$win" status "$member")" || return
  coll_has window "$win" status "$member" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"
  if (( has_rc == 0 )); then
    IFS=$'\t' read -r current revision <<< "$tuple"
    [[ "$revision" =~ ^[0-9]+$ ]] || command_die "status: invalid private revision"
    [[ "$current" != "$value" ]] || return 0
  fi
  _signal_status_next_revision revision "$pane" || return
  coll_set window "$win" status "$member" "$value" "$revision" || return
  destination=1
}

_signal_resolve_status_pane () {   # <pane-destination> <window-destination> <command> [target]
  local -n destination_pane="$1" destination_window="$2"
  local command="$3" target="${4:-}" resolved_pane resolved_window
  if [[ -z "$target" ]]; then
    resolved_pane="$(current_pane)" || command_die "$command: cannot resolve current pane"
  else
    resolved_pane="$(resolve_pane "$target")" || command_die "$command: cannot resolve pane '$target'"
  fi
  [[ -n "$resolved_pane" ]] || command_die "$command: cannot resolve pane '${target:-current}'"
  resolved_window="$(resolve_window "$resolved_pane")" || \
    command_die "$command: cannot resolve window for pane '$resolved_pane'"
  [[ -n "$resolved_window" ]] || \
    command_die "$command: cannot resolve window for pane '$resolved_pane'"
  # shellcheck disable=SC2034 # assignment is through a caller-selected nameref
  destination_pane="$resolved_pane"
  # shellcheck disable=SC2034 # assignment is through a caller-selected nameref
  destination_window="$resolved_window"
}

signal_status_set () {   # [-t <pane-target>] <active|result|attention>
  local value="" target="" pane win member
  if [[ "${1:-}" == -t ]]; then
    [[ $# -ge 2 && -n "$2" && "$2" != -t ]] || \
      command_die "status set: -t requires <pane-target>"
    target="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "status set: unknown option '$1'"
  fi
  if (( $# > 1 )); then
    local trailing
    for trailing in "${@:2}"; do
      [[ "$trailing" != -* ]] || command_die "status set: options must precede arguments"
    done
  fi
  (( $# == 1 )) || command_die "status set: need exactly <value>"
  value="$1"
  _signal_status_valid "$value" || command_die "status set: invalid value '$value'"
  _signal_resolve_status_pane pane win "status set" "$target"
  member="${pane#%}"
  _signal_apply window "$win" status _signal_status_set_unlocked \
    "$win" "$pane" "$member" "$value" || return
  [[ "$value" != result ]] || _signal_ensure_result_hook
}

_signal_status_clear_unlocked () {   # <destination> <window> <pane> <pane-member>
  local -n destination="$1"
  local win="$2" pane="$3" member="$4" tuple revision has_rc=0
  destination=""
  tuple="$(coll_get window "$win" status "$member")" || return
  coll_has window "$win" status "$member" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"
  if (( has_rc == 1 )) && [[ -z "$tuple" ]]; then return 0; fi
  _signal_status_next_revision revision "$pane" || return
  coll_unregister window "$win" status "$member" || return
  destination=1
}

_signal_status_clear_observed_unlocked () {   # <destination> <window> <pane> <pane-member> <revision>
  local -n destination="$1"
  local win="$2" pane="$3" member="$4" observed_revision="$5"
  # shellcheck disable=SC2034 # receives the increment through a nameref; clear needs only the side effect
  local tuple value revision next_revision has_rc=0
  destination=""
  tuple="$(coll_get window "$win" status "$member")" || return
  coll_has window "$win" status "$member" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"
  (( has_rc == 0 )) || return 0
  IFS=$'\t' read -r value revision <<< "$tuple"
  [[ "$value" == result && "$revision" =~ ^[0-9]+$ ]] || return 0
  [[ "$revision" == "$observed_revision" ]] || return 0
  _signal_status_next_revision next_revision "$pane" || return
  coll_unregister window "$win" status "$member" || return
  destination=1
}

signal_status_clear () {   # [-t <pane-target>]
  local target="" pane win member
  if [[ "${1:-}" == -t ]]; then
    [[ $# -ge 2 && -n "$2" && "$2" != -t ]] || \
      command_die "status clear: -t requires <pane-target>"
    target="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "status clear: unknown option '$1'"
  fi
  (( $# == 0 )) || command_die "status clear: takes no arguments"
  _signal_resolve_status_pane pane win "status clear" "$target"
  member="${pane#%}"
  _signal_apply window "$win" status _signal_status_clear_unlocked "$win" "$pane" "$member"
}

# Private hook callback. Its pane/revision tuple is Airline-owned state rather than
# contributor API, so both required components are positional and the command is
# intentionally omitted from public help and completions.
signal_status_observed_result () {   # <pane> <revision>
  (( $# == 2 )) || command_die "status _observed-result: need <pane> <revision>"
  local pane win member revision="$2"
  [[ "$revision" =~ ^[0-9]+$ ]] || \
    command_die "status _observed-result: invalid revision '$revision'"
  _signal_resolve_status_pane pane win "status _observed-result" "$1"
  member="${pane#%}"
  _signal_apply window "$win" status _signal_status_clear_observed_unlocked \
    "$win" "$pane" "$member" "$revision"
}

_signal_status_show_unlocked () {   # <window>
  local win="$1" tuple value revision member members
  members="$(coll_members window "$win" status)" || return
  for member in $members; do
    tuple="$(coll_get window "$win" status "$member")" || return
    IFS=$'\t' read -r value revision <<< "$tuple"
    command_show_row "%$member" "$value  revision $revision"
  done
}

signal_status_show () {   # [-t <window-target>]
  local target="" win
  if [[ "${1:-}" == -t ]]; then
    [[ $# -ge 2 && -n "$2" && "$2" != -t ]] || \
      command_die "status show: -t requires <window-target>"
    target="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "status show: unknown option '$1'"
  fi
  (( $# == 0 )) || command_die "status show: takes no arguments"
  _signal_resolve_window win "status show" "$target"
  _signal_with_transaction window "$win" status _signal_status_show_unlocked "$win"
}

#-----------------------------------------------------------------------------#
# Health public boundary
#-----------------------------------------------------------------------------#

signal_health_set () {   # [-t <window-target>] <contributor> <key> <ok|warn|fail> [<message>...]
  local win="" contributor key level message
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 4 )) || [[ -z "$2" ]]; then command_die "health set: -t requires <window-target>"; fi
    win="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "health set: unknown option '$1'"
  fi
  contributor="${1:-}"; key="${2:-}"; level="${3:-}"
  shift $(( $# < 3 ? $# : 3 ))
  message="$*"
  _signal_validate_contributor "health set" "$contributor"
  _signal_validate_key "health set" "$key"
  _signal_validate_condition "health set" "$level" "$message"
  _signal_resolve_window win "health set" "$win"
  _signal_apply window "$win" health _signal_health_store_unlocked \
    "$win" "$contributor" "$key" "$level" "$message"
}

signal_health_clear () {   # [-t <window-target>] <contributor> <key>
  local win="" contributor key
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 4 )) || [[ -z "$2" ]]; then command_die "health clear: -t requires <window-target>"; fi
    win="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "health clear: unknown option '$1'"
  fi
  (( $# == 2 )) || command_die "health clear: need exactly <contributor> <key>"
  contributor="$1"; key="$2"
  _signal_validate_contributor "health clear" "$contributor"
  _signal_validate_key "health clear" "$key"
  _signal_resolve_window win "health clear" "$win"
  _signal_apply window "$win" health _signal_health_store_unlocked \
    "$win" "$contributor" "$key" ok ""
}

signal_health_ack () {   # [-t <window-target>] <contributor> <key>
  local win="" contributor key
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 4 )) || [[ -z "$2" ]]; then command_die "health ack: -t requires <window-target>"; fi
    win="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "health ack: unknown option '$1'"
  fi
  (( $# == 2 )) || command_die "health ack: need exactly <contributor> <key>"
  contributor="$1"; key="$2"
  _signal_validate_contributor "health ack" "$contributor"
  _signal_validate_key "health ack" "$key"
  _signal_resolve_window win "health ack" "$win"
  _signal_apply window "$win" health _signal_health_ack_unlocked \
    "$win" "$contributor" "$key"
}

signal_health_show () {   # [--all] [-t <window-target>] [<contributor> [<key>]]
  local visibility=active-only win="" contributor="" key="" seen_all="" seen_target=""
  while (( $# )) && [[ "$1" == -* ]]; do
    case "$1" in
      --all)
        [[ -z "$seen_all" ]] || command_die "health show: duplicate --all"
        visibility=all; seen_all=1; shift ;;
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "health show: -t requires <window-target>"
        [[ -z "$seen_target" ]] || command_die "health show: duplicate -t"
        win="$2"; seen_target=1; shift 2 ;;
      -*) command_die "health show: unknown option '$1'" ;;
      *) command_die "health show: unknown option '$1'" ;;
    esac
  done
  [[ "${1:-}" != -t && "${1:-}" != --all && "${2:-}" != -t && "${2:-}" != --all ]] || \
    command_die "health show: options must precede arguments"
  (( $# <= 2 )) || command_die "health show: too many arguments"
  contributor="${1:-}"; key="${2:-}"
  (( $# == 0 )) || _signal_validate_contributor "health show" "$contributor"
  (( $# < 2 )) || _signal_validate_key "health show" "$key"
  _signal_resolve_window win "health show" "$win"
  _signal_with_transaction window "$win" health _signal_health_show_unlocked \
    "$visibility" "$win" "$contributor" "$key"
}

#-----------------------------------------------------------------------------#
# Global problem lifecycle ledger
#-----------------------------------------------------------------------------#
# `problem` members are logical ledger entries:
#   <badge-level|none>\t<active|acknowledged|closed|resolved>\t<last-level>\t<last-message>
# `problem-claim` members are active assertions:
#   <contributor>\t<problem-key>\t<pane|session>\t<origin-id>\t<level>\t<message>
# Closed claims are removed; a closed ledger entry retains the last diagnostic.
# Resolution removes active claims and retains the recovered ledger entry.

_signal_problem_claim_id () { printf '%s:%s:%s:%s' "$1" "$2" "$3" "$4"; }

_signal_problem_ledger_set () {   # <destination> <key> <active|acknowledged|closed|resolved> <level> <message>
  local -n destination="$1"
  local key="$2" state="$3" level="$4" message="$5" badge=none desired current
  destination=""
  [[ "$state" == active ]] && badge="$level"
  desired="$(printf '%s\t%s\t%s\t%s' "$badge" "$state" "$level" "$message")"
  current="$(coll_get global server problem "$key")" || return
  [[ "$current" != "$desired" ]] || return 0
  coll_set global server problem "$key" "$badge" "$state" "$level" "$message" || return
  destination=1
}

_signal_problem_recompute () {   # <destination> <contributor> <key> <close|resolve-when-empty>
  local -n destination="$1"
  local contributor="$2" key="$3" empty="$4" id members member tuple
  local claim_contributor claim_key kind origin level message
  local ledger badge state last_level last_message max="" max_message="" rank best=-1
  local ledger_changed=""
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"
  members="$(coll_members global server problem-claim)" || return
  for member in $members; do
    tuple="$(coll_get global server problem-claim "$member")" || return
    IFS=$'\t' read -r claim_contributor claim_key kind origin level message <<< "$tuple"
    [[ "$claim_contributor" == "$contributor" && "$claim_key" == "$key" ]] || continue
    case "$level" in warn) rank=1 ;; fail) rank=2 ;; *) continue ;; esac
    (( rank > best )) && { best=$rank; max="$level"; max_message="$message"; }
  done

  ledger="$(coll_get global server problem "$id")" || return
  if [[ -n "$max" ]]; then
    state=active
    if [[ -n "$ledger" ]]; then
      IFS=$'\t' read -r badge state last_level last_message <<< "$ledger"
      [[ "$state" == acknowledged && "$last_level" == "$max" ]] || state=active
    fi
    _signal_problem_ledger_set ledger_changed "$id" "$state" "$max" "$max_message" || return
    destination="$ledger_changed"
  elif [[ "$empty" == resolve-when-empty ]]; then
    [[ -n "$ledger" ]] || return 0
    IFS=$'\t' read -r badge state last_level last_message <<< "$ledger"
    _signal_problem_ledger_set ledger_changed "$id" resolved "$last_level" "$last_message" || return
    destination="$ledger_changed"
  elif [[ -n "$ledger" ]]; then
    IFS=$'\t' read -r badge state last_level last_message <<< "$ledger"
    _signal_problem_ledger_set ledger_changed "$id" closed "$last_level" "$last_message" || return
    destination="$ledger_changed"
  fi
}

_signal_problem_claim_set_unlocked () {   # <destination> <pane|session> <origin> <contributor> <key> <level> <message>
  local -n destination="$1"
  local kind="$2" origin="$3" contributor="$4" key="$5" level="$6" message="$7"
  local id tuple desired
  local claim_changed="" ledger_changed=""
  destination=""
  id="$(_signal_problem_claim_id "$kind" "$origin" "$contributor" "$key")"
  tuple="$(coll_get global server problem-claim "$id")" || return
  if [[ "$level" == ok ]]; then
    [[ -n "$tuple" ]] || return 0
    coll_unregister global server problem-claim "$id" || return
    claim_changed=1
    _signal_problem_recompute ledger_changed "$contributor" "$key" resolve-when-empty || return
  else
    desired="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$contributor" "$key" "$kind" "$origin" "$level" "$message")"
    if [[ "$tuple" != "$desired" ]]; then
      coll_set global server problem-claim "$id" "$contributor" "$key" "$kind" "$origin" "$level" "$message" || return
      claim_changed=1
    fi
    _signal_problem_recompute ledger_changed "$contributor" "$key" close || return
  fi
  [[ -z "$claim_changed$ledger_changed" ]] || destination=1
}

_signal_problem_close_unlocked () {   # <destination> <pane|session> <origin> [<contributor> [<key>]]
  local -n destination="$1"
  local kind="$2" origin="$3" contributor="${4:-}" key="${5:-}"
  local members member tuple claim_contributor claim_key claim_kind claim_origin
  local level message affected=" " affected_id changed="" ledger_changed=""
  destination=""
  members="$(coll_members global server problem-claim)" || return
  for member in $members; do
    tuple="$(coll_get global server problem-claim "$member")" || return
    IFS=$'\t' read -r claim_contributor claim_key claim_kind claim_origin level message <<< "$tuple"
    [[ "$claim_kind" == "$kind" && "$claim_origin" == "$origin" ]] || continue
    [[ -z "$contributor" || "$claim_contributor" == "$contributor" ]] || continue
    [[ -z "$key" || "$claim_key" == "$key" ]] || continue
    coll_unregister global server problem-claim "$member" || return
    affected_id="$(_signal_claim_id "$claim_contributor" "$claim_key")"
    case "$affected" in *" $affected_id "*) ;; *) affected+="$affected_id " ;; esac
    changed=1
  done
  [[ -n "$changed" ]] || return 0
  for affected_id in $affected; do
    claim_contributor="${affected_id%%:*}"; claim_key="${affected_id#*:}"
    _signal_problem_recompute ledger_changed "$claim_contributor" "$claim_key" close || return
  done
  destination=1
}

_signal_problem_ack_unlocked () {   # <destination> <contributor> <key>
  local -n destination="$1"
  local contributor="$2" key="$3" id tuple badge state level message ledger_changed=""
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"
  tuple="$(coll_get global server problem "$id")" || return
  [[ -n "$tuple" ]] || return 0
  IFS=$'\t' read -r badge state level message <<< "$tuple"
  [[ "$state" == active ]] || return 0
  _signal_problem_ledger_set ledger_changed "$id" acknowledged "$level" "$message" || return
  destination="$ledger_changed"
}

_signal_problem_resolve_unlocked () {   # <destination> <contributor> <key>
  local -n destination="$1"
  local contributor="$2" key="$3" id members member tuple claim_contributor claim_key
  local kind origin badge state level message changed="" ledger_changed=""
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"
  members="$(coll_members global server problem-claim)" || return
  for member in $members; do
    tuple="$(coll_get global server problem-claim "$member")" || return
    IFS=$'\t' read -r claim_contributor claim_key kind origin level message <<< "$tuple"
    [[ "$claim_contributor" == "$contributor" && "$claim_key" == "$key" ]] || continue
    coll_unregister global server problem-claim "$member" || return
    changed=1
  done
  tuple="$(coll_get global server problem "$id")" || return
  [[ -n "$tuple" ]] || { [[ -z "$changed" ]] || destination=1; return 0; }
  IFS=$'\t' read -r badge state level message <<< "$tuple"
  _signal_problem_ledger_set ledger_changed "$id" resolved "$level" "$message" || return
  [[ -z "$changed$ledger_changed" ]] || destination=1
}

_signal_problem_clear_unlocked () {   # <destination> <contributor> <key>
  local -n destination="$1"
  local contributor="$2" key="$3" id members member tuple claim_contributor claim_key changed=""
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"
  members="$(coll_members global server problem-claim)" || return
  for member in $members; do
    tuple="$(coll_get global server problem-claim "$member")" || return
    IFS=$'\t' read -r claim_contributor claim_key _ <<< "$tuple"
    [[ "$claim_contributor" == "$contributor" && "$claim_key" == "$key" ]] || continue
    coll_unregister global server problem-claim "$member" || return
    changed=1
  done
  if coll_has global server problem "$id"; then
    coll_unregister global server problem "$id" || return
    changed=1
  fi
  [[ -z "$changed" ]] || destination=1
}

_signal_problem_show_unlocked () {   # <active-only|all> [<contributor> [<key>]]
  local visibility="$1" wanted_contributor="${2:-}" wanted_key="${3:-}"
  local keys id contributor key ledger badge state level message
  local members member tuple claim_contributor claim_key kind origin claim_level claim_message
  keys="$(coll_members global server problem)" || return
  members="$(coll_members global server problem-claim)" || return
  for id in $keys; do
    contributor="${id%%:*}"; key="${id#*:}"
    [[ -z "$wanted_contributor" || "$contributor" == "$wanted_contributor" ]] || continue
    [[ -z "$wanted_key" || "$key" == "$wanted_key" ]] || continue
    ledger="$(coll_get global server problem "$id")" || return
    IFS=$'\t' read -r badge state level message <<< "$ledger"
    [[ "$visibility" == all || "$state" == active ]] || continue
    command_show_row "$contributor" "$key  $state  $level${message:+  $message}"
    for member in $members; do
      tuple="$(coll_get global server problem-claim "$member")" || return
      IFS=$'\t' read -r claim_contributor claim_key kind origin claim_level claim_message <<< "$tuple"
      [[ "$claim_contributor" == "$contributor" && "$claim_key" == "$key" ]] || continue
      command_show_row "  $kind:$origin" "$claim_level${claim_message:+  $claim_message}"
    done
  done
}

_signal_problem_resolve_pane () {   # <destination> <command> <target> [allow-missing-canonical]
  local -n destination="$1"
  local command="$2" target="$3" allow_missing="${4:-}" resolved
  [[ -n "$target" ]] || command_die "$command: --pane requires <pane-target>"
  if resolved="$(resolve_pane "$target" 2>/dev/null)" && [[ -n "$resolved" ]]; then
    :
  elif [[ -n "$allow_missing" && "$target" =~ ^%[0-9]+$ ]]; then
    # pane-exited/pane-died supplies canonical identity after the pane is gone.
    resolved="$target"
  else
    command_die "$command: cannot resolve pane '$target'"
  fi
  # shellcheck disable=SC2034 # assignment is through the caller-selected nameref
  destination="$resolved"
}

signal_problem_set () {   # [--pane <pane-target>] <contributor> <key> <ok|warn|fail> [<message>...]
  local kind=session origin="" contributor key level message
  if [[ "${1:-}" == --pane ]]; then
    (( $# >= 2 )) || command_die "problem set: --pane requires <pane-target>"
    kind=pane; origin="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "problem set: unknown option '$1'"
  fi
  contributor="${1:-}"; key="${2:-}"; level="${3:-}"
  shift $(( $# < 3 ? $# : 3 )); message="$*"
  _signal_validate_contributor "problem set" "$contributor"
  _signal_validate_key "problem set" "$key"
  _signal_validate_condition "problem set" "$level" "$message"
  if [[ "$kind" == pane ]]; then _signal_problem_resolve_pane origin "problem set" "$origin"
  else origin="$(command_current_session)"; fi
  _signal_apply global server problem _signal_problem_claim_set_unlocked \
    "$kind" "$origin" "$contributor" "$key" "$level" "$message"
}

signal_problem_close () {   # [--pane <pane-target>|--session <session-target>] [<contributor> [<key>]]
  local kind=session origin="" contributor="" key="" target=""
  case "${1:-}" in
    --pane)
      (( $# >= 2 )) || command_die "problem close: --pane requires <pane-target>"
      kind=pane; target="$2"; shift 2 ;;
    --session)
      (( $# >= 2 )) || command_die "problem close: --session requires <session-target>"
      target="$2"; shift 2 ;;
    -*) command_die "problem close: unknown option '$1'" ;;
  esac
  (( $# <= 2 )) || command_die "problem close: too many arguments"
  [[ "${1:-}" != --pane && "${1:-}" != --session && \
     "${2:-}" != --pane && "${2:-}" != --session ]] || \
    command_die "problem close: options must precede arguments"
  contributor="${1:-}"; key="${2:-}"
  [[ -z "$contributor" ]] || _signal_validate_contributor "problem close" "$contributor"
  [[ -z "$key" ]] || _signal_validate_key "problem close" "$key"
  if [[ "$kind" == pane ]]; then
    _signal_problem_resolve_pane origin "problem close" "$target" allow-missing-canonical
  elif [[ -n "$target" ]]; then
    if origin="$(resolve_session_target "$target" 2>/dev/null)" && [[ -n "$origin" ]]; then
      :
    elif [[ "$target" =~ ^\$[0-9]+$ ]]; then
      # session-closed supplies canonical identity after the session is gone.
      origin="$target"
    else
      command_die "problem close: cannot resolve session '$target'"
    fi
  else origin="$(command_current_session)"; fi
  _signal_apply global server problem _signal_problem_close_unlocked \
    "$kind" "$origin" "$contributor" "$key"
}

signal_problem_clear () {   # <contributor> <key>
  (( $# == 2 )) || command_die "problem clear: need exactly <contributor> <key>"
  _signal_validate_contributor "problem clear" "$1"
  _signal_validate_key "problem clear" "$2"
  _signal_apply global server problem _signal_problem_clear_unlocked "$1" "$2"
}

signal_problem_ack () {   # <contributor> <key>
  (( $# == 2 )) || command_die "problem ack: need exactly <contributor> <key>"
  _signal_validate_contributor "problem ack" "$1"
  _signal_validate_key "problem ack" "$2"
  _signal_apply global server problem _signal_problem_ack_unlocked "$1" "$2"
}

signal_problem_resolve () {   # <contributor> <key>
  (( $# == 2 )) || command_die "problem resolve: need exactly <contributor> <key>"
  _signal_validate_contributor "problem resolve" "$1"
  _signal_validate_key "problem resolve" "$2"
  _signal_apply global server problem _signal_problem_resolve_unlocked "$1" "$2"
}

signal_problem_show () {   # [--all] [<contributor> [<key>]]
  local visibility=active-only contributor="" key="" seen_all=""
  while (( $# )) && [[ "$1" == -* ]]; do
    case "$1" in
      --all)
        [[ -z "$seen_all" ]] || command_die "problem show: duplicate --all"
        visibility=all; seen_all=1; shift ;;
      -*) command_die "problem show: unknown option '$1'" ;;
      *) command_die "problem show: unknown option '$1'" ;;
    esac
  done
  [[ "${1:-}" != --all && "${2:-}" != --all ]] || \
    command_die "problem show: options must precede arguments"
  (( $# <= 2 )) || command_die "problem show: too many arguments"
  contributor="${1:-}"; key="${2:-}"
  (( $# == 0 )) || _signal_validate_contributor "problem show" "$contributor"
  (( $# < 2 )) || _signal_validate_key "problem show" "$key"
  _signal_with_transaction global server problem _signal_problem_show_unlocked \
    "$visibility" "$contributor" "$key"
}

# Shared reporting path for Airline-owned layout and runner contributors. Their
# canonical session is origin identity only; visibility and reduction are global.
signal_problem_report () {   # <session> <contributor> <key> <ok|warn|fail> <message>
  _signal_apply global server problem _signal_problem_claim_set_unlocked \
    session "$1" "$2" "$3" "$4" "${5:-}"
}

signal_problem_install_hooks () {
  hook_set "pane-exited[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' problem close --pane '#{hook_pane}'\""
  hook_set "pane-died[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' problem close --pane '#{hook_pane}'\""
  hook_set "session-closed[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' problem close --session '#{hook_session}'\""
}

# vim: ft=bash

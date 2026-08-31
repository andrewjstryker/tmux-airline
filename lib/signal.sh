#!/usr/bin/env bash
#
# signal.sh — status, health, problems, and transient status consumption.
#
# Status is window-scoped display state: it is message-free and may be transient.
# Health is a persistent keyed window condition. Problems are a server-global
# lifecycle ledger whose active claims retain their pane or session origin.
#
# Signal owns validation, transactional mutation, projection orchestration, redraw
# gating, and the consume-on-view hook.

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
  local id tuple desired has_rc=0
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"

  tuple="$(coll_get_window "$owner" health "$id")" || return
  coll_has_window "$owner" health "$id" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"

  if [[ "$level" == ok ]]; then
    if (( has_rc == 1 )) && [[ -z "$tuple" ]]; then return 0; fi
    coll_unregister_window "$owner" health "$id" || return
  else
    desired="$(printf '%s\t%s' "$level" "$message")"
    if (( has_rc == 0 )) && [[ "$tuple" == "$desired" ]]; then return 0; fi
    coll_set_window "$owner" health "$id" "$level" "$message" || return
  fi

  destination=1
}

_signal_health_show_unlocked () {   # <window> [<contributor> [<key>]]
  local owner="$1" contributor="${2:-}" key="${3:-}" id
  local members member tuple level message member_contributor member_key
  if [[ -n "$key" ]]; then
    id="$(_signal_claim_id "$contributor" "$key")"
    coll_get_window "$owner" health "$id"
    return
  fi
  members="$(coll_members_window "$owner" health)" || return
  for member in $members; do
    member_contributor="${member%%:*}"; member_key="${member#*:}"
    [[ -z "$contributor" || "$member_contributor" == "$contributor" ]] || continue
    tuple="$(coll_get_window "$owner" health "$member")" || return
    IFS=$'\t' read -r level message <<< "$tuple"
    command_show_row "$member_contributor" "$member_key  $level${message:+  $message}"
  done
}

#-----------------------------------------------------------------------------#
# Status — window display state, optionally consumed after viewing
#-----------------------------------------------------------------------------#

_signal_ensure_transient_hook () {
  opt_set_global focus-events on || return
  hook_set "pane-focus-out[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline.sh' status clear -t #{window_id}\""
}

_signal_status_set_unlocked () {   # <destination> <window> <key> <value> <transient>
  local -n destination="$1"
  local win="$2" key="$3" value="$4" transient="$5" tuple desired has_rc=0
  destination=""
  tuple="$(coll_get_window "$win" status "$key")" || return
  coll_has_window "$win" status "$key" || has_rc=$?
  (( has_rc <= 1 )) || return "$has_rc"
  desired="$(printf '%s\t%s' "$value" "$transient")"
  if (( has_rc == 0 )) && [[ "$tuple" == "$desired" ]]; then return 0; fi
  coll_set_window "$win" status "$key" "$value" "$transient" || return
  destination=1
}

signal_status_set () {   # <key> <value> [--transient] [-t <window>]
  local key value transient="" win="" seen_transient="" seen_target=""
  local -a positionals=()
  while (( $# )); do
    case "$1" in
      --transient)
        [[ -z "$seen_transient" ]] || command_die "status set: duplicate --transient"
        transient=1; seen_transient=1; shift
        ;;
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "status set: -t requires <window>"
        [[ -z "$seen_target" ]] || command_die "status set: duplicate -t"
        [[ "$2" != -t && "$2" != --transient ]] || \
          command_die "status set: -t requires <window>"
        win="$2"; seen_target=1; shift 2
        ;;
      -*) command_die "status set: unknown option '$1'" ;;
      *) positionals+=("$1"); shift ;;
    esac
  done
  (( ${#positionals[@]} == 2 )) || command_die "status set: need exactly <key> <value>"
  key="${positionals[0]}"; value="${positionals[1]}"
  _signal_validate_key "status set" "$key"
  _signal_status_valid "$value" || command_die "status set: invalid value '$value'"
  _signal_resolve_window win "status set" "$win"
  _signal_apply window "$win" status _signal_status_set_unlocked \
    "$win" "$key" "$value" "$transient" || return
  [[ -z "$transient" ]] || _signal_ensure_transient_hook
}

_signal_status_clear_unlocked () {   # <destination> <window> [<key>]
  local -n destination="$1"
  local win="$2" key="${3:-}" tuple transient members has_rc=0
  destination=""
  if [[ -n "$key" ]]; then
    tuple="$(coll_get_window "$win" status "$key")" || return
    coll_has_window "$win" status "$key" || has_rc=$?
    (( has_rc <= 1 )) || return "$has_rc"
    if (( has_rc == 1 )) && [[ -z "$tuple" ]]; then return 0; fi
    coll_unregister_window "$win" status "$key" || return
    destination=1
    return 0
  fi

  # A keyless clear is the lifecycle operation used by the focus hook: remove
  # every claim whose contributor marked it transient, but preserve sticky claims.
  members="$(coll_members_window "$win" status)" || return
  for key in $members; do
    tuple="$(coll_get_window "$win" status "$key")" || return
    transient="${tuple#*$'\t'}"
    [[ "$transient" == 1 ]] || continue
    coll_unregister_window "$win" status "$key" || return
    destination=1
  done
}

signal_status_clear () {   # [<key>] [-t <window>]
  local key win="" seen_target=""; local -a positionals=()
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "status clear: -t requires <window>"
        [[ -z "$seen_target" ]] || command_die "status clear: duplicate -t"
        [[ "$2" != -t && "$2" != --transient ]] || \
          command_die "status clear: -t requires <window>"
        win="$2"; seen_target=1; shift 2
        ;;
      -*) command_die "status clear: unknown option '$1'" ;;
      *) positionals+=("$1"); shift ;;
    esac
  done
  (( ${#positionals[@]} <= 1 )) || command_die "status clear: too many arguments"
  key="${positionals[0]:-}"
  (( ${#positionals[@]} == 0 )) || _signal_validate_key "status clear" "$key"
  _signal_resolve_window win "status clear" "$win"
  _signal_apply window "$win" status _signal_status_clear_unlocked "$win" "$key"
}

_signal_status_show_unlocked () {   # <window> [<key>]
  local win="$1" key="${2:-}" tuple level transient member members
  if [[ -n "$key" ]]; then
    tuple="$(coll_get_window "$win" status "$key")" || return
    printf '%s\n' "${tuple%%$'\t'*}"
    return 0
  fi
  members="$(coll_members_window "$win" status)" || return
  for member in $members; do
    tuple="$(coll_get_window "$win" status "$member")" || return
    IFS=$'\t' read -r level transient <<< "$tuple"
    command_show_row "$member" "$level${transient:+  (transient)}"
  done
}

signal_status_show () {   # [<key>] [-t <window>]
  local key="" win="" seen_target=""; local -a positionals=()
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || command_die "status show: -t requires <window>"
        [[ -z "$seen_target" ]] || command_die "status show: duplicate -t"
        [[ "$2" != -t && "$2" != --transient ]] || \
          command_die "status show: -t requires <window>"
        win="$2"; seen_target=1; shift 2
        ;;
      -*) command_die "status show: unknown option '$1'" ;;
      *) positionals+=("$1"); shift ;;
    esac
  done
  (( ${#positionals[@]} <= 1 )) || command_die "status show: too many arguments"
  key="${positionals[0]:-}"
  (( ${#positionals[@]} == 0 )) || _signal_validate_key "status show" "$key"
  _signal_resolve_window win "status show" "$win"
  _signal_with_transaction window "$win" status _signal_status_show_unlocked "$win" "$key"
}

#-----------------------------------------------------------------------------#
# Health public boundary
#-----------------------------------------------------------------------------#

signal_health_set () {   # [-t <window>] <contributor> <key> <ok|warn|fail> [<message>...]
  local win="" contributor key level message
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 4 )) || [[ -z "$2" ]]; then command_die "health set: -t requires <window>"; fi
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

signal_health_clear () {   # [-t <window>] <contributor> <key>
  local win="" contributor key
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 4 )) || [[ -z "$2" ]]; then command_die "health clear: -t requires <window>"; fi
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

signal_health_show () {   # [-t <window>] [<contributor> [<key>]]
  local win="" contributor="" key=""
  if [[ "${1:-}" == -t ]]; then
    if (( $# < 2 )) || [[ -z "$2" ]]; then command_die "health show: -t requires <window>"; fi
    win="$2"; shift 2
  elif [[ "${1:-}" == -* ]]; then
    command_die "health show: unknown option '$1'"
  fi
  (( $# <= 2 )) || command_die "health show: too many arguments"
  contributor="${1:-}"; key="${2:-}"
  if (( $# > 0 )); then _signal_validate_contributor "health show" "$contributor"; fi
  if (( $# > 1 )); then _signal_validate_key "health show" "$key"; fi
  _signal_resolve_window win "health show" "$win"
  _signal_with_transaction window "$win" health _signal_health_show_unlocked \
    "$win" "$contributor" "$key"
}

#-----------------------------------------------------------------------------#
# Global problem lifecycle ledger
#-----------------------------------------------------------------------------#
# `problem` members are logical ledger entries:
#   <badge-level|none>\t<active|closed|cleared>\t<last-level>\t<last-message>
# `problem-claim` members are active assertions:
#   <contributor>\t<problem-key>\t<pane|session>\t<origin-id>\t<level>\t<message>
# Closed claims are removed; a closed ledger entry retains the last diagnostic.
# Resolution removes both the claims and ledger entry.

_signal_problem_claim_id () { printf '%s:%s:%s:%s' "$1" "$2" "$3" "$4"; }

_signal_problem_ledger_set () {   # <destination> <key> <active|closed|cleared> <level> <message>
  local -n destination="$1"
  local key="$2" state="$3" level="$4" message="$5" badge=none desired current
  destination=""
  [[ "$state" == active ]] && badge="$level"
  desired="$(printf '%s\t%s\t%s\t%s' "$badge" "$state" "$level" "$message")"
  current="$(coll_get_global problem "$key")" || return
  [[ "$current" != "$desired" ]] || return 0
  coll_set_global problem "$key" "$badge" "$state" "$level" "$message" || return
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
  members="$(coll_members_global problem-claim)" || return
  for member in $members; do
    tuple="$(coll_get_global problem-claim "$member")" || return
    IFS=$'\t' read -r claim_contributor claim_key kind origin level message <<< "$tuple"
    [[ "$claim_contributor" == "$contributor" && "$claim_key" == "$key" ]] || continue
    case "$level" in warn) rank=1 ;; fail) rank=2 ;; *) continue ;; esac
    (( rank > best )) && { best=$rank; max="$level"; max_message="$message"; }
  done

  ledger="$(coll_get_global problem "$id")" || return
  if [[ -n "$max" ]]; then
    state=active
    if [[ -n "$ledger" ]]; then
      IFS=$'\t' read -r badge state last_level last_message <<< "$ledger"
      [[ "$state" == cleared ]] || state=active
    fi
    _signal_problem_ledger_set ledger_changed "$id" "$state" "$max" "$max_message" || return
    destination="$ledger_changed"
  elif [[ "$empty" == resolve-when-empty ]]; then
    if coll_has_global problem "$id"; then
      coll_unregister_global problem "$id" || return
      destination=1
    fi
  elif [[ -n "$ledger" ]]; then
    IFS=$'\t' read -r badge state last_level last_message <<< "$ledger"
    [[ "$state" == cleared ]] || state=closed
    _signal_problem_ledger_set ledger_changed "$id" "$state" "$last_level" "$last_message" || return
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
  tuple="$(coll_get_global problem-claim "$id")" || return
  if [[ "$level" == ok ]]; then
    [[ -n "$tuple" ]] || return 0
    coll_unregister_global problem-claim "$id" || return
    claim_changed=1
    _signal_problem_recompute ledger_changed "$contributor" "$key" resolve-when-empty || return
  else
    desired="$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$contributor" "$key" "$kind" "$origin" "$level" "$message")"
    if [[ "$tuple" != "$desired" ]]; then
      coll_set_global problem-claim "$id" "$contributor" "$key" "$kind" "$origin" "$level" "$message" || return
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
  members="$(coll_members_global problem-claim)" || return
  for member in $members; do
    tuple="$(coll_get_global problem-claim "$member")" || return
    IFS=$'\t' read -r claim_contributor claim_key claim_kind claim_origin level message <<< "$tuple"
    [[ "$claim_kind" == "$kind" && "$claim_origin" == "$origin" ]] || continue
    [[ -z "$contributor" || "$claim_contributor" == "$contributor" ]] || continue
    [[ -z "$key" || "$claim_key" == "$key" ]] || continue
    coll_unregister_global problem-claim "$member" || return
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

_signal_problem_clear_unlocked () {   # <destination> <contributor> <key>
  local -n destination="$1"
  local contributor="$2" key="$3" id tuple badge state level message ledger_changed=""
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"
  tuple="$(coll_get_global problem "$id")" || return
  [[ -n "$tuple" ]] || return 0
  IFS=$'\t' read -r badge state level message <<< "$tuple"
  [[ "$state" != cleared ]] || return 0
  _signal_problem_ledger_set ledger_changed "$id" cleared "$level" "$message" || return
  destination="$ledger_changed"
}

_signal_problem_resolve_unlocked () {   # <destination> <contributor> <key>
  local -n destination="$1"
  local contributor="$2" key="$3" id members member tuple claim_contributor claim_key
  local kind origin level message changed=""
  destination=""
  id="$(_signal_claim_id "$contributor" "$key")"
  members="$(coll_members_global problem-claim)" || return
  for member in $members; do
    tuple="$(coll_get_global problem-claim "$member")" || return
    IFS=$'\t' read -r claim_contributor claim_key kind origin level message <<< "$tuple"
    [[ "$claim_contributor" == "$contributor" && "$claim_key" == "$key" ]] || continue
    coll_unregister_global problem-claim "$member" || return
    changed=1
  done
  if coll_has_global problem "$id"; then
    coll_unregister_global problem "$id" || return
    changed=1
  fi
  [[ -n "$changed" ]] || return 0
  destination=1
}

_signal_problem_show_unlocked () {   # <active-only|all> [<contributor> [<key>]]
  local visibility="$1" wanted_contributor="${2:-}" wanted_key="${3:-}"
  local keys id contributor key ledger badge state level message
  local members member tuple claim_contributor claim_key kind origin claim_level claim_message
  keys="$(coll_members_global problem)" || return
  members="$(coll_members_global problem-claim)" || return
  for id in $keys; do
    contributor="${id%%:*}"; key="${id#*:}"
    [[ -z "$wanted_contributor" || "$contributor" == "$wanted_contributor" ]] || continue
    [[ -z "$wanted_key" || "$key" == "$wanted_key" ]] || continue
    ledger="$(coll_get_global problem "$id")" || return
    IFS=$'\t' read -r badge state level message <<< "$ledger"
    [[ "$visibility" == all || "$state" == active ]] || continue
    command_show_row "$contributor" "$key  $state  $level${message:+  $message}"
    for member in $members; do
      tuple="$(coll_get_global problem-claim "$member")" || return
      IFS=$'\t' read -r claim_contributor claim_key kind origin claim_level claim_message <<< "$tuple"
      [[ "$claim_contributor" == "$contributor" && "$claim_key" == "$key" ]] || continue
      command_show_row "  $kind:$origin" "$claim_level${claim_message:+  $claim_message}"
    done
  done
}

_signal_problem_resolve_pane () {   # <destination> <command> <target>
  local -n destination="$1"
  local command="$2" target="$3" resolved
  [[ -n "$target" ]] || command_die "$command: --pane requires <pane-id>"
  resolved="$(resolve_pane "$target")" || command_die "$command: cannot resolve pane '$target'"
  [[ -n "$resolved" ]] || command_die "$command: cannot resolve pane '$target'"
  # shellcheck disable=SC2034 # assignment is through the caller-selected nameref
  destination="$resolved"
}

signal_problem_set () {   # [--pane <pane-id>] <contributor> <key> <ok|warn|fail> [<message>...]
  local kind=session origin="" contributor key level message
  if [[ "${1:-}" == --pane ]]; then
    (( $# >= 2 )) || command_die "problem set: --pane requires <pane-id>"
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

signal_problem_close () {   # [--pane <pane-id>|--session <session-id>] [<contributor> [<key>]]
  local kind=session origin="" contributor="" key=""
  case "${1:-}" in
    --pane)
      (( $# >= 2 )) || command_die "problem close: --pane requires <pane-id>"
      kind=pane; origin="$2"; shift 2 ;;
    --session)
      (( $# >= 2 )) || command_die "problem close: --session requires <session-id>"
      origin="$2"; shift 2 ;;
    -*) command_die "problem close: unknown option '$1'" ;;
  esac
  (( $# <= 2 )) || command_die "problem close: too many arguments"
  contributor="${1:-}"; key="${2:-}"
  [[ -z "$contributor" ]] || _signal_validate_contributor "problem close" "$contributor"
  [[ -z "$key" ]] || _signal_validate_key "problem close" "$key"
  if [[ "$kind" == pane ]]; then
    [[ "$origin" =~ ^%[0-9]+$ ]] || command_die "problem close: invalid pane id '$origin'"
  elif [[ -n "$origin" ]]; then
    [[ "$origin" =~ ^\$[0-9]+$ ]] || command_die "problem close: invalid session id '$origin'"
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

signal_problem_resolve () {   # <contributor> <key>
  (( $# == 2 )) || command_die "problem resolve: need exactly <contributor> <key>"
  _signal_validate_contributor "problem resolve" "$1"
  _signal_validate_key "problem resolve" "$2"
  _signal_apply global server problem _signal_problem_resolve_unlocked "$1" "$2"
}

signal_problem_show () {   # [--all] [<contributor> [<key>]]
  local visibility=active-only contributor="" key="" seen_all=""; local -a positionals=()
  while (( $# )); do
    case "$1" in
      --all)
        [[ -z "$seen_all" ]] || command_die "problem show: duplicate --all"
        visibility=all; seen_all=1; shift ;;
      -*) command_die "problem show: unknown option '$1'" ;;
      *) positionals+=("$1"); shift ;;
    esac
  done
  (( ${#positionals[@]} <= 2 )) || command_die "problem show: too many arguments"
  contributor="${positionals[0]:-}"; key="${positionals[1]:-}"
  (( ${#positionals[@]} == 0 )) || _signal_validate_contributor "problem show" "$contributor"
  (( ${#positionals[@]} < 2 )) || _signal_validate_key "problem show" "$key"
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

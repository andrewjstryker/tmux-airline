#!/usr/bin/env bash
#
# api.sh — the CLI command handlers (the logic behind every verb).
#
# `airline` is just the parser/dispatcher; the work lives here. Each handler owns
# input validation (the one place input is checked — against render.sh's predicates)
# and then drives the layers: opt_* / coll_* to mutate state, `render` to produce the
# bar. Sourced on top of tmux.sh + collections.sh + render.sh.
#
# The verb grammar is uniform across nouns: `set X v` / `clear X` / `show [X]`
# (+ `use <file>` for the static nouns). The set/clear *behaviour* splits on the
# state model — dynamic nouns (status, health) are live: write + re-project a badge
# + redraw; static nouns (theme, segment) stage a public @airline-* option that the
# next `apply` renders.

# shellcheck shell=bash

if ! declare -F render >/dev/null; then
  printf 'api.sh: load render.sh (and its layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

die () { printf 'airline: %s\n' "$*" >&2; exit 2; }

usage () {
  cat <<'EOF'
airline — tmux-airline CLI

Lifecycle:
  airline init                 seed defaults + binds + publish path, then render
  airline apply                render the bar from the source of truth
  airline suspend | resume     nested-session dim / passthrough
  airline help

Dynamic nouns (airline manages — live):
  airline status  set <key> <active|result|attention> [--transient] [-t <win>]
  airline status  clear <key> [-t <win>]
  airline status  show [<key>] [-t <win>]
  airline health  set <key> <ok|alert|stress> [--transient] [-t <win>]
  airline health  clear <key> [-t <win>]
  airline health  show [<key>] [-t <win>]

Static nouns (you own — public @airline-* options; staged, rendered at apply):
  airline theme    set <element> <color> | clear <element> | show [<element>]
  airline theme    use <name|path>
  airline segment  set <slot> <format>   | clear <slot>    | show [<slot>]
  airline segment  use <name|path>

  --transient clears the signal when you focus away from its window.
EOF
}

#-----------------------------------------------------------------------------#
# Lifecycle
#-----------------------------------------------------------------------------#

# True when no segment slot is set yet (a fresh install) — gates default seeding.
_segments_unset () {
  local s
  for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    [[ -n "$(pub_get "segment-$s")" ]] && return 1
  done
  return 0
}

# Bootstrap. Publish the CLI path, bind F12, and on first run seed defaults behind a
# sentinel (without clobbering user config or runtime state on a reload); then render.
cmd_init () {
  prv_set_global "$AIRLINE_KEY_CLI" "$AIRLINE_DIR/airline"
  key_bind root F12 "run-shell \"$AIRLINE_DIR/airline suspend\""
  key_bind off  F12 "run-shell \"$AIRLINE_DIR/airline resume\""

  if [[ "$(prv_get_global "$AIRLINE_KEY_DEFAULTS")" != 1 ]]; then
    [[ -z "$(pub_get inner-bg)" ]] && source_file "$AIRLINE_DIR/themes/dark"
    _segments_unset && source_file "$AIRLINE_DIR/bundles/default"
    prv_set_global "$AIRLINE_KEY_DEFAULTS" 1
  fi
  render || true
}

cmd_apply () { render || true; }

# Load a tmux config file (a theme or bundle of `set -g @airline-*` lines), then
# render. <name> is a path, or a bare name resolved under <subdir>/ (themes|bundles).
cmd_use () {   # <subdir> <name|path>
  local subdir="$1" name="${2:-}"; [[ -n "$name" ]] || die "$subdir use: need <file|name>"
  local file=""
  if   [[ -f "$name" ]];                        then file="$name"
  elif [[ -f "$AIRLINE_DIR/$subdir/$name" ]];   then file="$AIRLINE_DIR/$subdir/$name"
  else die "$subdir use: no such file: $name"; fi
  source_file "$file"
  render || true
}

cmd_suspend () {
  prv_set_global "$AIRLINE_KEY_SUSPENDED" 1
  opt_set_global prefix None
  opt_set_global key-table off
  render || true
}

cmd_resume () {
  prv_set_global "$AIRLINE_KEY_SUSPENDED" 0
  opt_unset_global prefix
  opt_unset_global key-table
  render || true
}

#-----------------------------------------------------------------------------#
# Transient (consume-on-view)
#-----------------------------------------------------------------------------#

_ensure_unfocus_hook () {
  opt_set_global focus-events on
  hook_set "pane-focus-out[90]" "run-shell -b \"$AIRLINE_DIR/airline _unfocus #{window_id}\""
}

# Drop every transient contributor on <window>, then re-project both badges once.
cmd_unfocus () {
  local win="${1:-}"; [[ -n "$win" ]] || return 0
  local changed="" ns key f1 f2
  for ns in status health; do
    for key in $(coll_members_window "$win" "$ns"); do
      IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$key")"
      [[ "$f2" == 1 ]] && { coll_unregister_window "$win" "$ns" "$key"; changed=1; }
    done
  done
  [[ -n "$changed" ]] || return 0
  status_project "$win" || true
  health_project "$win" || true
  redraw
}

#-----------------------------------------------------------------------------#
# Dynamic nouns — status & health (live: write + re-project a badge + redraw)
#-----------------------------------------------------------------------------#

_signal_set () {   # <ns> <validator> <key> <value> [--transient] [-t <win>]
  local ns="$1" valid="$2"; shift 2
  local key="" value="" transient="" win="" ; local -a pos=()
  while (( $# )); do
    case "$1" in
      --transient) transient=1; shift ;;
      -t)          win="${2:-}"; shift 2 ;;
      *)           pos+=("$1"); shift ;;
    esac
  done
  key="${pos[0]:-}"; value="${pos[1]:-}"
  [[ -n "$key" ]] || die "$ns set: need <key>"
  "$valid" "$value" || die "$ns set: invalid value '$value'"
  [[ -n "$win" ]] || win="$(current_window)"
  coll_set_window "$win" "$ns" "$key" "$value" "$transient"
  [[ -n "$transient" ]] && _ensure_unfocus_hook
  "${ns}_project" "$win" && redraw
  return 0
}

_signal_clear () {   # <ns> <key> [-t <win>]
  local ns="$1"; shift
  local key="" win=""
  while (( $# )); do
    case "$1" in -t) win="${2:-}"; shift 2 ;; *) key="$1"; shift ;; esac
  done
  [[ -n "$key" ]] || die "$ns clear: need <key>"
  [[ -n "$win" ]] || win="$(current_window)"
  coll_unregister_window "$win" "$ns" "$key"
  "${ns}_project" "$win" && redraw
  return 0
}

_signal_show () {   # <ns> [<key>] [-t <win>]
  local ns="$1"; shift
  local key="" win="" f1 f2 k
  while (( $# )); do
    case "$1" in -t) win="${2:-}"; shift 2 ;; *) key="$1"; shift ;; esac
  done
  [[ -n "$win" ]] || win="$(current_window)"
  if [[ -n "$key" ]]; then
    IFS=$'\t' read -r f1 _ <<< "$(coll_get_window "$win" "$ns" "$key")"
    printf '%s\n' "$f1"
    return 0
  fi
  for k in $(coll_members_window "$win" "$ns"); do
    IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$k")"
    printf '%-16s %s%s\n' "$k" "$f1" "${f2:+  (transient)}"
  done
}

cmd_status () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   _signal_set   status _status_level_valid "$@" ;;
    clear) _signal_clear status "$@" ;;
    show)  _signal_show  status "$@" ;;
    ""|-h|--help) usage ;;
    *) die "unknown status command: $verb" ;;
  esac
}

cmd_health () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   _signal_set   health _health_severity_valid "$@" ;;
    clear) _signal_clear health "$@" ;;
    show)  _signal_show  health "$@" ;;
    ""|-h|--help) usage ;;
    *) die "unknown health command: $verb" ;;
  esac
}

#-----------------------------------------------------------------------------#
# Static nouns — theme & segment (public @airline-* options; set stages, apply renders)
#-----------------------------------------------------------------------------#

# <key-prefix> is the bare-key prefix WITHIN the public namespace: "" for theme
# (the key is the element) or "segment-" for segments. pub_* applies the @airline-
# prefix; api never spells it.
_static_set () {   # <key-prefix> <validator> <X> <value>
  local keypfx="$1" valid="$2" x="${3:-}" value="${4:-}"
  [[ -n "$x" ]] || die "set: need a target"
  "$valid" "$x" || die "set: unknown target '$x'"
  pub_set "${keypfx}${x}" "$value"   # stage a public option; `apply` renders
}

_static_clear () {   # <key-prefix> <validator> <X>
  local keypfx="$1" valid="$2" x="${3:-}"
  [[ -n "$x" ]] || die "clear: need a target"
  "$valid" "$x" || die "clear: unknown target '$x'"
  pub_unset "${keypfx}${x}"
}

_static_show () {   # <key-prefix> <validator> <list-array-name> [<X>]
  local keypfx="$1" valid="$2" listname="$3" x="${4:-}"
  if [[ -n "$x" ]]; then
    "$valid" "$x" || die "show: unknown target '$x'"
    pub_get "${keypfx}${x}"
    return 0
  fi
  local -n all="$listname"; local k
  for k in "${all[@]}"; do printf '%-12s %s\n' "$k" "$(pub_get "${keypfx}${k}")"; done
}

cmd_theme () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   _static_set   "" _theme_element_valid "$@" ;;
    clear) _static_clear "" _theme_element_valid "$@" ;;
    show)  _static_show  "" _theme_element_valid AIRLINE_THEME_ELEMENTS "$@" ;;
    use)   cmd_use themes "$@" ;;
    ""|-h|--help) usage ;;
    *) die "unknown theme command: $verb" ;;
  esac
}

cmd_segment () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   _static_set   "segment-" _segment_slot_valid "$@" ;;
    clear) _static_clear "segment-" _segment_slot_valid "$@" ;;
    show)  _static_show  "segment-" _segment_slot_valid AIRLINE_SEGMENT_SLOTS "$@" ;;
    use)   cmd_use bundles "$@" ;;
    ""|-h|--help) usage ;;
    *) die "unknown segment command: $verb" ;;
  esac
}

# vim: ft=bash

#!/usr/bin/env bash
#
# collections.sh — dynamic keyed collections.
#
# Status and health hold per-window contributors; problem holds session-scoped
# widget failures. Tmux's flat option store has no collection concept, so this
# adds one mechanically. It is domain-free: namespace and severity ordering
# arrive as data (see coll_reduce); it knows nothing about glyphs or severities.
#
# Built entirely on lib/tmux.sh's opt_* functions — it makes NO direct tmux calls, so
# it stays OFF the architecture-lint allowlist while tmux.sh remains the sole
# caller. Static architecture checks enforce the dependency on tmux.sh.
#
# Storage — two shapes, each one option split with bash IFS (no awk/jq/subshell):
#
#   @airline-<ns>          registry: a space-delimited list of keys (membership)
#   @airline-<ns>-<key>    that entry's fixed-arity tuple, tab-delimited
#
# Names are data: membership is the registry list; we never glob/parse @airline-*
# option names to discover entries. Keys are only ever CONSTRUCTED from (ns, key),
# so a key may safely contain '-'. One delimiter per option: the registry is
# space-delimited (keys hold no spaces); tuples are tab-delimited (free-text fields
# may contain spaces, never tabs). `set` writes the whole tuple, so field positions
# stay fixed.

# shellcheck shell=bash

#-----------------------------------------------------------------------------#
# Option I/O, scope-polymorphic. Scope and target are explicit so session names,
# session ids, and window ids are all ordinary data. These are the ONLY bridge to
# the option layer; everything below goes through them.
#-----------------------------------------------------------------------------#
_coll_oget () {   # <global|session|window> <target> <name>
  case "$1" in
    global)  opt_get_global "$3" ;;
    session) opt_get_session "$2" "$3" ;;
    window)  opt_get_window "$2" "$3" ;;
  esac
}
_coll_oset () {   # <global|session|window> <target> <name> <value>
  case "$1" in
    global)  opt_set_global "$3" "$4" ;;
    session) opt_set_session "$2" "$3" "$4" ;;
    window)  opt_set_window "$2" "$3" "$4" ;;
  esac
}
_coll_ounset () { # <global|session|window> <target> <name>
  case "$1" in
    global)  opt_unset_global "$3" ;;
    session) opt_unset_session "$2" "$3" ;;
    window)  opt_unset_window "$2" "$3" ;;
  esac
}

# Option names — constructed, never parsed. The PRIVATE prefix itself belongs to
# tmux.sh (prv_name, DESIGN.md §State model); collections owns only the key SHAPE —
# the <ns> registry and <ns>-<key> tuple layout — and asks prv_name to apply the
# double dash. So this file holds the scheme but not the literal prefix.
_coll_reg () { prv_name "$1"; }           # ns       → registry option  (@airline--<ns>)
_coll_key () { prv_name "$1-$2"; }        # ns key   → tuple option     (@airline--<ns>-<key>)

# Public name constructor: the private tuple option for (ns, key). The single home
# for the @airline--<ns>-<key> scheme, so callers never hand-build a private name.
coll_optname () { _coll_key "$@"; }                    # <ns> <key> → option name

#-----------------------------------------------------------------------------#
# Private cores — operate on (scope, target, ns, …); public wrappers bake scope.
#-----------------------------------------------------------------------------#

_coll_members () {   # <scope> <target> <ns> → space-delimited keys, registry order
  _coll_oget "$1" "$2" "$(_coll_reg "$3")"
}

_coll_has () {       # <scope> <target> <ns> <key> (exit status)
  case " $(_coll_members "$1" "$2" "$3") " in *" $4 "*) return 0 ;; *) return 1 ;; esac
}

_coll_register () {  # <scope> <target> <ns> <key> add to registry TAIL
  local scope="$1" target="$2" ns="$3" key="$4" cur
  cur="$(_coll_members "$scope" "$target" "$ns")"
  case " $cur " in *" $key "*) return 0 ;; esac
  _coll_oset "$scope" "$target" "$(_coll_reg "$ns")" "${cur:+$cur }$key"
}

_coll_prepend () {   # <scope> <target> <ns> <key> add to registry HEAD
  local scope="$1" target="$2" ns="$3" key="$4" cur
  cur="$(_coll_members "$scope" "$target" "$ns")"
  case " $cur " in *" $key "*) return 0 ;; esac
  _coll_oset "$scope" "$target" "$(_coll_reg "$ns")" "$key${cur:+ $cur}"
}

_coll_unregister () {  # <scope> <target> <ns> <key> drop member + tuple
  local scope="$1" target="$2" ns="$3" key="$4" cur out="" k
  cur="$(_coll_members "$scope" "$target" "$ns")"
  for k in $cur; do [[ "$k" == "$key" ]] || out="${out:+$out }$k"; done
  if [[ -n "$out" ]]; then _coll_oset "$scope" "$target" "$(_coll_reg "$ns")" "$out"
  else _coll_ounset "$scope" "$target" "$(_coll_reg "$ns")"; fi
  _coll_ounset "$scope" "$target" "$(_coll_key "$ns" "$key")"
}

_coll_get () {       # <scope> <target> <ns> <key> → tuple ("" if unset)
  _coll_oget "$1" "$2" "$(_coll_key "$3" "$4")"
}

_coll_set () {       # <scope> <target> <ns> <key> <field…> register + write tuple
  local scope="$1" target="$2" ns="$3" key="$4"; shift 4
  _coll_register "$scope" "$target" "$ns" "$key"
  # Tab-join the fields in a subshell so IFS never leaks into _coll_oset — the
  # option layer (and the AIRLINE_TMUX shim) must run with the default IFS.
  _coll_oset "$scope" "$target" "$(_coll_key "$ns" "$key")" "$(IFS=$'\t'; printf '%s' "$*")"
}

# Reduce the collection to the highest-ranked first-field value among its members.
# <order> is a space-delimited ranking, low→high (e.g. "ok warn fail"); the
# winner is the member whose first tuple field ranks highest. Values absent from
# <order> are ignored; empty result when no member carries a ranked value. The
# ranking is passed in as data — collections owns no severity vocabulary.
_coll_reduce () {    # <scope> <target> <ns> <order>
  local scope="$1" target="$2" ns="$3" order="$4"
  local key tuple val o w rank best=-1 result=""
  for key in $(_coll_members "$scope" "$target" "$ns"); do
    tuple="$(_coll_get "$scope" "$target" "$ns" "$key")"
    val="${tuple%%$'\t'*}"                 # first field
    rank=-1; w=0
    for o in $order; do [[ "$o" == "$val" ]] && { rank=$w; break; }; ((w++)); done
    (( rank > best )) && { best=$rank; result="$val"; }
  done
  printf '%s' "$result"
}

#-----------------------------------------------------------------------------#
# Exported collection interface — mirrors opt_* scope suffixes.
#-----------------------------------------------------------------------------#

# --- global scope ---
coll_register_global   () { _coll_register   global "" "$@"; }
coll_prepend_global    () { _coll_prepend    global "" "$@"; }
coll_unregister_global () { _coll_unregister global "" "$@"; }
coll_has_global        () { _coll_has        global "" "$@"; }
coll_members_global    () { _coll_members    global "" "$@"; }
coll_get_global        () { _coll_get        global "" "$@"; }
coll_set_global        () { _coll_set        global "" "$@"; }
coll_reduce_global     () { _coll_reduce     global "" "$@"; }

# --- session scope (explicit session id/name first) ---
coll_register_session   () { _coll_register   session "$@"; }
coll_prepend_session    () { _coll_prepend    session "$@"; }
coll_unregister_session () { _coll_unregister session "$@"; }
coll_has_session        () { _coll_has        session "$@"; }
coll_members_session    () { _coll_members    session "$@"; }
coll_get_session        () { _coll_get        session "$@"; }
coll_set_session        () { _coll_set        session "$@"; }
coll_reduce_session     () { _coll_reduce     session "$@"; }

# --- window scope (explicit window id first, per opt_*_window) ---
coll_register_window   () { _coll_register   window "$@"; }
coll_prepend_window    () { _coll_prepend    window "$@"; }
coll_unregister_window () { _coll_unregister window "$@"; }
coll_has_window        () { _coll_has        window "$@"; }
coll_members_window    () { _coll_members    window "$@"; }
coll_get_window        () { _coll_get        window "$@"; }
coll_set_window        () { _coll_set        window "$@"; }
coll_reduce_window     () { _coll_reduce     window "$@"; }

# vim: ft=bash

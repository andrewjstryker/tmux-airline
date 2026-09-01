#!/usr/bin/env bash
#
# collections.sh — dynamic keyed collections.
#
# Tmux's flat option store has no collection concept, so this adds one mechanically.
# Every operation takes scope first and treats namespace, keys, tuple fields, and
# reduction order as data. Domain modules choose ownership and meaning; this layer
# knows nothing about statuses, health, problems, glyphs, or severities.
#
# Built entirely on lib/tmux.sh's opt_* functions — it makes NO direct tmux calls, so
# it stays OFF the architecture-lint allowlist while tmux.sh remains the sole
# caller. Static architecture checks enforce the dependency on tmux.sh.
#
# Storage — two shapes, each one option split with bash IFS (no awk/jq/subshell):
#
#   @airline--<ns>          registry: a space-delimited list of keys (membership)
#   @airline--<ns>-<key>    that entry's fixed-arity tuple, tab-delimited
#
# Names are data: membership is the registry list; we never glob/parse @airline-*
# option names to discover entries. Keys are only ever CONSTRUCTED from (ns, key),
# so a key may safely contain '-'. One delimiter per option: the registry is
# space-delimited (keys hold no spaces); tuples are tab-delimited (free-text fields
# may contain spaces, never tabs). `set` writes the whole tuple, so field positions
# stay fixed.

# shellcheck shell=bash

#-----------------------------------------------------------------------------#
# Option names. Generic scope-first opt_* calls below are the only bridge to the
# option layer.
#-----------------------------------------------------------------------------#

# Option names — constructed, never parsed. The PRIVATE prefix itself belongs to
# tmux.sh (prv_name, DESIGN.md §State model); collections owns only the key SHAPE —
# the <ns> registry and <ns>-<key> tuple layout — and asks prv_name to apply the
# double dash. So this file holds the scheme but not the literal prefix.
_coll_reg () { prv_name "$1"; }           # ns       → registry option  (@airline--<ns>)
_coll_key () { prv_name "$1-$2"; }        # ns key   → tuple option     (@airline--<ns>-<key>)

#-----------------------------------------------------------------------------#
# Private cores — pass through (scope, owner, namespace, …) tuples unchanged.
#-----------------------------------------------------------------------------#

_coll_members () {   # <scope> <owner> <ns> → space-delimited keys, registry order
  opt_get "$1" "$2" "$(_coll_reg "$3")"
}

_coll_has () {       # <scope> <owner> <ns> <key> (exit status)
  local members
  members="$(_coll_members "$1" "$2" "$3")" || return 2
  case " $members " in *" $4 "*) return 0 ;; *) return 1 ;; esac
}

_coll_register () {  # <scope> <owner> <ns> <key> add to registry TAIL
  local scope="$1" owner="$2" ns="$3" key="$4" cur
  cur="$(_coll_members "$scope" "$owner" "$ns")" || return
  case " $cur " in *" $key "*) return 0 ;; esac
  opt_set "$scope" "$owner" "$(_coll_reg "$ns")" "${cur:+$cur }$key"
}

_coll_prepend () {   # <scope> <owner> <ns> <key> add to registry HEAD
  local scope="$1" owner="$2" ns="$3" key="$4" cur
  cur="$(_coll_members "$scope" "$owner" "$ns")" || return
  case " $cur " in *" $key "*) return 0 ;; esac
  opt_set "$scope" "$owner" "$(_coll_reg "$ns")" "$key${cur:+ $cur}"
}

_coll_unregister () {  # <scope> <owner> <ns> <key> drop member + tuple
  local scope="$1" owner="$2" ns="$3" key="$4" cur out="" k
  cur="$(_coll_members "$scope" "$owner" "$ns")" || return
  for k in $cur; do [[ "$k" == "$key" ]] || out="${out:+$out }$k"; done
  if [[ -n "$out" ]]; then opt_set "$scope" "$owner" "$(_coll_reg "$ns")" "$out" || return
  else opt_unset "$scope" "$owner" "$(_coll_reg "$ns")" || return; fi
  opt_unset "$scope" "$owner" "$(_coll_key "$ns" "$key")"
}

_coll_get () {       # <scope> <owner> <ns> <key> → tuple ("" if unset)
  opt_get "$1" "$2" "$(_coll_key "$3" "$4")"
}

_coll_set () {       # <scope> <owner> <ns> <key> <field…> register + write tuple
  local scope="$1" owner="$2" ns="$3" key="$4"; shift 4
  _coll_register "$scope" "$owner" "$ns" "$key" || return
  # Tab-join the fields in a subshell so IFS never leaks into opt_set — the
  # option layer (and the AIRLINE_TMUX shim) must run with the default IFS.
  opt_set "$scope" "$owner" "$(_coll_key "$ns" "$key")" "$(IFS=$'\t'; printf '%s' "$*")"
}

# Reduce the collection to the highest-ranked first-field value among its members.
# <order> is a space-delimited ranking, low→high (e.g. "ok warn fail"); the
# winner is the member whose first tuple field ranks highest. Values absent from
# <order> are ignored; empty result when no member carries a ranked value. The
# ranking is passed in as data — collections owns no severity vocabulary.
_coll_reduce () {    # <scope> <owner> <ns> <order>
  local scope="$1" owner="$2" ns="$3" order="$4"
  local key tuple val o w rank best=-1 result="" members
  members="$(_coll_members "$scope" "$owner" "$ns")" || return
  for key in $members; do
    tuple="$(_coll_get "$scope" "$owner" "$ns" "$key")" || return
    val="${tuple%%$'\t'*}"                 # first field
    rank=-1; w=0
    for o in $order; do [[ "$o" == "$val" ]] && { rank=$w; break; }; ((w++)); done
    (( rank > best )) && { best=$rank; result="$val"; }
  done
  printf '%s' "$result"
}

#-----------------------------------------------------------------------------#
# Exported collection interface. Scope is always the first argument and its
# canonical owner is always second. This layer neither validates nor translates
# that tuple; tmux.sh owns the mechanical boundary.
#-----------------------------------------------------------------------------#

coll_register   () { _coll_register   "$@"; }
coll_prepend    () { _coll_prepend    "$@"; }
coll_unregister () { _coll_unregister "$@"; }
coll_has        () { _coll_has        "$@"; }
coll_members    () { _coll_members    "$@"; }
coll_get        () { _coll_get        "$@"; }
coll_set        () { _coll_set        "$@"; }
coll_reduce     () { _coll_reduce     "$@"; }

# vim: ft=bash

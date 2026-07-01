#!/usr/bin/env bash
#
# collections.sh — dynamic keyed collections (status and health only).
#
# status and health each hold 0-or-more dynamic entries — lanes lit on a window,
# health contributors reporting in — which tmux's flat option store has no concept
# of. This adds exactly that, and only for those two. It is mechanical and
# domain-free: the namespace ("status" / "health") arrives as the `ns` argument,
# and severity ordering arrives as data too (see coll_reduce). It knows nothing
# about glyphs, tokens, or severities.
#
# Built entirely on tmux.sh's opt_* functions — it makes NO direct tmux calls, so
# it stays OFF the architecture-lint allowlist while tmux.sh remains the sole
# caller. Assumes tmux.sh is sourced first (the guard below enforces it).
#
# Storage — two shapes, each one option split with bash IFS (no awk/jq/subshell):
#
#   @airline-<ns>          registry: a space-delimited list of keys (membership)
#   @airline-<ns>-<key>    that entry's fixed-arity tuple, tab-delimited
#
# Names are data: membership is the registry list; we never glob/parse @airline-*
# option names to discover entries. Keys are only ever CONSTRUCTED from (ns, key),
# so a key may safely contain '-'. One delimiter per option: the registry is
# space-delimited (keys hold no spaces); the tuple is tab-delimited (its one
# arbitrary field, a status glyph, is never a tab). `set` writes the whole tuple,
# so field positions stay fixed.

# shellcheck shell=bash

if ! declare -F opt_get_global >/dev/null; then
  printf 'collections.sh: load tmux.sh first\n' >&2
  return 1 2>/dev/null || exit 1
fi

#-----------------------------------------------------------------------------#
# Option I/O, scope-polymorphic. The first arg is the window id, or "" for global
# scope (a real window id is always "@<n>", never empty, so "" is unambiguous).
# These are the ONLY bridge to the option layer; everything below goes through
# them, so collections never names a scope twice.
#-----------------------------------------------------------------------------#
_coll_oget () {   # <win|""> <name>
  if [[ -n "$1" ]]; then opt_get_window "$1" "$2"; else opt_get_global "$2"; fi
}
_coll_oset () {   # <win|""> <name> <value>
  if [[ -n "$1" ]]; then opt_set_window "$1" "$2" "$3"; else opt_set_global "$2" "$3"; fi
}
_coll_ounset () { # <win|""> <name>
  if [[ -n "$1" ]]; then opt_unset_window "$1" "$2"; else opt_unset_global "$2"; fi
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
# Private cores — operate on (win, ns, …); the public wrappers bake the scope.
#-----------------------------------------------------------------------------#

_coll_members () {   # <win> <ns>   → space-delimited keys, registry order
  _coll_oget "$1" "$(_coll_reg "$2")"
}

_coll_has () {       # <win> <ns> <key>   (exit status)
  case " $(_coll_members "$1" "$2") " in *" $3 "*) return 0 ;; *) return 1 ;; esac
}

_coll_register () {  # <win> <ns> <key>   add to registry (idempotent)
  _coll_has "$1" "$2" "$3" && return 0
  local cur; cur="$(_coll_members "$1" "$2")"
  _coll_oset "$1" "$(_coll_reg "$2")" "${cur:+$cur }$3"
}

_coll_unregister () {  # <win> <ns> <key>   drop from registry AND unset its tuple
  local cur out="" k
  cur="$(_coll_members "$1" "$2")"
  for k in $cur; do [[ "$k" == "$3" ]] || out="${out:+$out }$k"; done
  if [[ -n "$out" ]]; then _coll_oset "$1" "$(_coll_reg "$2")" "$out"
  else _coll_ounset "$1" "$(_coll_reg "$2")"; fi
  _coll_ounset "$1" "$(_coll_key "$2" "$3")"
}

_coll_get () {       # <win> <ns> <key>   → the tab-delimited tuple ("" if unset)
  _coll_oget "$1" "$(_coll_key "$2" "$3")"
}

_coll_set () {       # <win> <ns> <key> <field…>   register + write the whole tuple
  local win="$1" ns="$2" key="$3"; shift 3
  _coll_register "$win" "$ns" "$key"
  # Tab-join the fields in a subshell so IFS never leaks into _coll_oset — the
  # option layer (and the AIRLINE_TMUX shim) must run with the default IFS.
  _coll_oset "$win" "$(_coll_key "$ns" "$key")" "$(IFS=$'\t'; printf '%s' "$*")"
}

# Reduce the collection to the highest-ranked first-field value among its members.
# <order> is a space-delimited ranking, low→high (e.g. "ok alert stress"); the
# winner is the member whose first tuple field ranks highest. Values absent from
# <order> are ignored; empty result when no member carries a ranked value. The
# ranking is passed in as data — collections owns no severity vocabulary.
_coll_reduce () {    # <win> <ns> <order>
  local win="$1" ns="$2" order="$3"
  local key tuple val o w rank best=-1 result=""
  for key in $(_coll_members "$win" "$ns"); do
    tuple="$(_coll_get "$win" "$ns" "$key")"
    val="${tuple%%$'\t'*}"                 # first field
    rank=-1; w=0
    for o in $order; do [[ "$o" == "$val" ]] && { rank=$w; break; }; ((w++)); done
    (( rank > best )) && { best=$rank; result="$val"; }
  done
  printf '%s' "$result"
}

#-----------------------------------------------------------------------------#
# Public API — mirrors opt_*'s scope suffix: _global, or _window <win>.
#-----------------------------------------------------------------------------#

# --- global scope ---
coll_register_global   () { _coll_register   "" "$@"; }   # <ns> <key>
coll_unregister_global () { _coll_unregister "" "$@"; }   # <ns> <key>
coll_has_global        () { _coll_has        "" "$@"; }   # <ns> <key>
coll_members_global    () { _coll_members    "" "$@"; }   # <ns>
coll_get_global        () { _coll_get        "" "$@"; }   # <ns> <key>
coll_set_global        () { _coll_set        "" "$@"; }   # <ns> <key> <field…>
coll_reduce_global     () { _coll_reduce     "" "$@"; }   # <ns> <order>

# --- window scope (explicit window id first, per opt_*_window) ---
coll_register_window   () { _coll_register   "$@"; }      # <win> <ns> <key>
coll_unregister_window () { _coll_unregister "$@"; }      # <win> <ns> <key>
coll_has_window        () { _coll_has        "$@"; }      # <win> <ns> <key>
coll_members_window    () { _coll_members    "$@"; }      # <win> <ns>
coll_get_window        () { _coll_get        "$@"; }      # <win> <ns> <key>
coll_set_window        () { _coll_set        "$@"; }      # <win> <ns> <key> <field…>
coll_reduce_window     () { _coll_reduce     "$@"; }      # <win> <ns> <order>

# vim: ft=bash

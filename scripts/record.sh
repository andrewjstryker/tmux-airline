#!/usr/bin/env bash
#
# record.sh — a namespaced record store over tmux options.
#
# airline's status lanes, status-bar segments, and health contributors are all
# the same shape: a named collection of records, each with attributes, persisted
# as tmux options and iterated in order. This is that shape, once.
#
# A record lives under a namespace `ns` with an `id`, an optional primary value,
# and named attributes:
#   @airline-<ns>-<id>           primary value
#   @airline-<ns>-<id>-<attr>    attribute
#   @airline-<ns>--roster        space-separated ids (membership, insert order)
#
# Membership is the explicit roster — keys are only ever *constructed* from
# (ns, id, attr), never parsed back — so ids may safely contain '-' and we never
# glob/disambiguate option names.
#
# `scope` is the leading argument of every op and is forwarded verbatim to tmux,
# selecting where records live:
#   "-g"                global
#   "-w"                the current window
#   "-w -t <target>"    a specific window
# It is word-split, so it must be passed unquoted-expandable (bash, not zsh).
#
# These call `tmux`, which the test harness overrides and the CLI points at the
# right server — same indirection as the rest of airline.

# SC2086: the unquoted $scope/$1 below is the documented word-splitting contract
# above — "-w -t @2" must reach tmux as separate args. Disabled for the module.
# shellcheck disable=SC2086

rec_key () {  # ns id [attr]   → the tmux option name
  if [[ -n "${3:-}" ]]; then printf '@airline-%s-%s-%s' "$1" "$2" "$3"
  else printf '@airline-%s-%s' "$1" "$2"; fi
}

_rec_roster_key () { printf '@airline-%s--roster' "$1"; }   # ns

# rec_get <scope> <ns> <id> <attr> [default]   (attr="" → primary value)
rec_get () {
  local scope="$1" ns="$2" id="$3" attr="$4" def="${5:-}" v
  v="$(tmux show-option $scope -qv "$(rec_key "$ns" "$id" "$attr")")"
  [[ -n "$v" ]] && printf '%s' "$v" || printf '%s' "$def"
}

# rec_set <scope> <ns> <id> <attr> <value>   (attr="" → primary value)
rec_set () {
  tmux set $1 "$(rec_key "$2" "$3" "$4")" "$5"
}

# rec_unset <scope> <ns> <id> <attr>
rec_unset () {
  tmux set $1 -u "$(rec_key "$2" "$3" "$4")" 2>/dev/null || true
}

# rec_ids <scope> <ns>   → roster ids, insertion order
rec_ids () {
  tmux show-option $1 -qv "$(_rec_roster_key "$2")"
}

# rec_has <scope> <ns> <id>   (exit status)
rec_has () {
  case " $(rec_ids "$1" "$2") " in *" $3 "*) return 0 ;; *) return 1 ;; esac
}

# rec_add <scope> <ns> <id>   add to roster (idempotent)
rec_add () {
  local scope="$1" ns="$2" id="$3" cur
  rec_has "$scope" "$ns" "$id" && return 0
  cur="$(rec_ids "$scope" "$ns")"
  tmux set $scope "$(_rec_roster_key "$ns")" "${cur:+$cur }$id"
}

# rec_del <scope> <ns> <id> [attr...]   drop from roster; unset primary + attrs
rec_del () {
  local scope="$1" ns="$2" id="$3"; shift 3
  local cur out="" w a
  cur="$(rec_ids "$scope" "$ns")"
  for w in $cur; do [[ "$w" == "$id" ]] || out="${out:+$out }$w"; done
  tmux set $scope "$(_rec_roster_key "$ns")" "$out"
  rec_unset "$scope" "$ns" "$id" ""
  for a in "$@"; do rec_unset "$scope" "$ns" "$id" "$a"; done
}

# rec_sorted <scope> <ns> <attr>   ids by ascending numeric attr (stable)
rec_sorted () {
  local scope="$1" ns="$2" attr="$3" id
  for id in $(rec_ids "$scope" "$ns"); do
    printf '%s %s\n' "$(rec_get "$scope" "$ns" "$id" "$attr" 0)" "$id"
  done | sort -n -s -k1,1 | awk '{print $2}'
}

# vim: ft=bash

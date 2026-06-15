#!/usr/bin/env bash

CURRENT_DIR="${AIRLINE_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

source "$CURRENT_DIR/scripts/shared.sh"
source "$CURRENT_DIR/scripts/record.sh"
source "$CURRENT_DIR/scripts/is_installed.sh"
source "$CURRENT_DIR/scripts/plugins/online.sh"
source "$CURRENT_DIR/scripts/plugins/prefix_highlight.sh"
source "$CURRENT_DIR/scripts/plugins/cpu.sh"
source "$CURRENT_DIR/scripts/plugins/battery.sh"

# Theme palette, keyed by role (primary, alert, ok, …). -gA so it stays global
# even when airline.tmux is sourced from inside a function (the test harness),
# which would otherwise scope it locally.
declare -gA THEME

# Every theme key (the @airline-<key> options a theme file sets, and the THEME
# keys airline reads). Single source of truth: load_theme populates THEME from
# this, and the theme contract test checks every theme defines all of them.
declare -ga AIRLINE_THEME_KEYS=(
  outer-bg middle-bg inner-bg
  secondary primary emphasized
  active special ok alert stress zoom copy monitor
)

# The subset of theme keys a palette token may name (the semantic colors, not
# the positional backgrounds or text weights), in render-precedence order.
# Single source of truth for palette_token_expr, used by the entry color, the
# status badges, and the health glyph. -ga for the same sourced-in-a-function
# reason as THEME above.
declare -ga AIRLINE_PALETTE_TOKENS=(active alert stress ok special monitor copy zoom)

apply_suspended_overrides () {
  THEME[outer-bg]="${THEME[inner-bg]}"
  THEME[middle-bg]="${THEME[inner-bg]}"
  THEME[emphasized]="${THEME[secondary]}"
  THEME[primary]="${THEME[secondary]}"
  THEME[active]="${THEME[secondary]}"
  THEME[special]="${THEME[secondary]}"
  THEME[ok]="${THEME[secondary]}"
  THEME[zoom]="${THEME[secondary]}"
  THEME[copy]="${THEME[secondary]}"
  THEME[monitor]="${THEME[secondary]}"
}

# Source a theme file and populate THEME from the @airline-* options it sets.
# The single theme-population path: airline's startup and the test harness both
# call this, so the option list lives in exactly one place. Defaults to the
# @airline-theme option (or "dark") but accepts an explicit theme name, which
# the tests use. Applies the suspended dimming overrides when in that mode.
load_theme () {
  local theme="${1:-$(get_tmux_option @airline-theme "dark")}" key
  tmux source-file "$CURRENT_DIR/themes/$theme"

  for key in "${AIRLINE_THEME_KEYS[@]}"; do
    THEME[$key]=$(get_tmux_option "@airline-$key")
  done

  if [[ "$(get_tmux_option @airline-suspended 0)" == "1" ]]; then
    apply_suspended_overrides
  fi
}

#-----------------------------------------------------------------------------#
#
# Chevrons
#
#-----------------------------------------------------------------------------#

chevron () {
  local left_bg="$1"
  local right_bg="$2"
  local chev="$3"

  echo "#[fg=$right_bg,bg=$left_bg]$chev"
}

chev_right () {
  local left_bg="$1"
  local right_bg="$2"
  chevron "$right_bg" "$left_bg" ""
}

chev_left () {
  local left_bg="$1"
  local right_bg="$2"
  chevron "$left_bg" "$right_bg" ""
}

#-----------------------------------------------------------------------------#
#
# Palette token resolution
#
#-----------------------------------------------------------------------------#

# Build a tmux format expression that maps an option holding a palette token
# (active, alert, stress, …) to its theme color, falling back to $fallback when
# the option is empty or holds an unknown token. Evaluated per window at render
# time. The token list (AIRLINE_PALETTE_TOKENS) lives in one place, so the entry
# color, the status badges, and the health glyph all resolve colors identically.
palette_token_expr () {
  local option="$1" fallback="$2"
  local expr="$fallback" tok
  for tok in "${AIRLINE_PALETTE_TOKENS[@]}"; do
    expr="#{?#{==:#{$option},$tok},${THEME[$tok]},$expr}"
  done
  printf '%s' "$expr"
}

#-----------------------------------------------------------------------------#
#
# Window entry color — internal only (tmux modes > airline baseline)
#
#-----------------------------------------------------------------------------#
# A window entry has a single "signal color" slot. Because the focused window is
# drawn reverse-video — its background is the highlight, and the flat background
# color becomes the knockout foreground — that slot is rendered as the *fore-
# ground* on inactive windows and as the *highlight background* on the focused
# window. Only airline writes it, from two internal sources, in order:
#
#   tmux modes (zoom > copy > monitor)  >  baseline (focus / last / normal)
#
# Plugins never touch the entry color; they speak through badges instead. zoom
# and monitor-activity read as 1/0 in a format (truthiness-safe); pane_in_mode
# marks copy/view mode on the window's active pane.

# The zoom > copy > monitor precedence, in one place. `fmt` is a printf template
# applied to each mode's color; `fallback` is emitted when no mode is active.
_mode_expr () {
  local fmt="$1" fallback="$2"
  # SC2059: $fmt is a caller-supplied printf template ('%s' or '#[fg=%s]'), used
  # as the format on purpose — that's the parameter's whole job.
  # shellcheck disable=SC2059
  printf '#{?#{window_zoomed_flag},%s,#{?#{pane_in_mode},%s,#{?monitor-activity,%s,%s}}}' \
    "$(printf "$fmt" "${THEME[zoom]}")" \
    "$(printf "$fmt" "${THEME[copy]}")" \
    "$(printf "$fmt" "${THEME[monitor]}")" \
    "$fallback"
}

# Highlight background for the focused window: the active mode's color (as a bare
# color), else the active highlight. Chevrons follow this so the focus block
# stays one filled unit.
window_mode_hi () { _mode_expr '%s' "${THEME[active]}"; }

# Foreground override for inactive windows: a mode recolors the name (as an
# #[fg=…] directive); empty when no mode is active, so the normal/last/activity/
# bell styles apply unchanged.
window_mode_fg () { _mode_expr '#[fg=%s]' ''; }

#-----------------------------------------------------------------------------#
#
# Badges — the plugin-facing API (driven by the `airline` CLI)
#
#-----------------------------------------------------------------------------#
# Two badge channels flank the window name. Plugins never set the backing
# options by hand — the `airline` CLI owns the layout and validates input; the
# @airline-status-* / @airline-health-* options below are private.
#
#   status : a durable, ordered stack of named lanes. A lane is registered once
#            (glyph + priority); a plugin then lights it on a window with a
#            palette token, or clears it. Many lanes can show at once; they
#            render left→right by ascending priority, to the RIGHT of the name.
#   health : a map keyed by contributor. Each writes a severity (ok|alert|
#            stress) under its own key; airline reduces to the max and shows ONE
#            glyph in that severity's color in the LEFT gutter. ok / none → no
#            glyph, so a clean gutter means healthy.

AIRLINE_SEVERITIES="ok alert stress"

# --- validation -------------------------------------------------------------

_is_palette_token () {
  local t
  for t in "${AIRLINE_PALETTE_TOKENS[@]}"; do [[ "$t" == "$1" ]] && return 0; done
  return 1
}
_is_severity ()  { [[ " $AIRLINE_SEVERITIES " == *" $1 "* ]]; }
_is_lane_name () { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]]; }

# Print a CLI error and return 2. Use as: <check> || { _err "msg"; return; }
# (the bare `return` propagates _err's status 2 out of the calling function).
_err () { echo "airline: $*" >&2; return 2; }

# Force a status-line redraw. Setting a status/health option changes a value the
# window-status-format references live, but tmux only re-evaluates the bar on
# status-interval or incidental events — so without this a badge would lag by up
# to status-interval seconds. The roster-changing ops redraw via _airline_rebuild
# instead; the per-window set/clear (and the unfocus hook) call this directly.
_redraw () { tmux refresh-client -S 2>/dev/null || true; }   # no client → harmless

# --- status lanes (a "status" record store) ---------------------------------
# glyph + priority live globally (the registry); the lit token and its transient
# flag live per window. Option names are unchanged, so the render exprs in
# set_window_formats still reference @airline-status-<lane> directly.

_status_sorted_lanes () { rec_sorted -g status prio; }
_lane_registered ()     { rec_has   -g status "$1"; }

# Window scope string from trailing target args ("" → current window).
_wscope () { printf -- '-w%s' "${*:+ $*}"; }

# Parse the trailing args shared by `status set` / `health set`: an optional
# --transient flag (anywhere) plus an optional `-t <target>`. Sets two globals
# for the caller — _SIG_TRANSIENT (0/1) and _SIG_WSCOPE (the window scope
# string). Returns via globals rather than echo so it can be called directly,
# not in a $( ) subshell that would discard the flag.
_parse_signal_args () {
  _SIG_TRANSIENT=0
  local args=()
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--transient" ]]; then _SIG_TRANSIENT=1; shift; else args+=("$1"); shift; fi
  done
  _SIG_WSCOPE="$(_wscope "${args[@]}")"
}

# register <lane> [glyph] [priority]   idempotent; rebuilds the bar.
airline_status_register () {
  local lane="$1" glyph="${2:-●}" prio="${3:-50}"
  _is_lane_name "$lane"     || { _err "invalid lane name: $lane"; return; }
  [[ "$prio" =~ ^[0-9]+$ ]] || { _err "priority must be an integer: $prio"; return; }
  rec_set -g status "$lane" glyph "$glyph"
  rec_set -g status "$lane" prio  "$prio"
  rec_add -g status "$lane"
  _airline_rebuild
}

# unregister <lane>   drop the lane; rebuilds the bar.
airline_status_unregister () {
  rec_del -g status "$1" glyph prio
  _airline_rebuild
}

# set <lane> <token> [--transient] [-t target]   light the lane on a window.
airline_status_set () {
  local lane="$1" token="$2"; shift 2
  _parse_signal_args "$@"; local ws="$_SIG_WSCOPE"
  _lane_registered "$lane"   || { _err "lane not registered: $lane"; return; }
  _is_palette_token "$token" || { _err "invalid token: $token"; return; }
  # Redraw only when the rendered token actually moves. The bar shows the token,
  # not the transient flag, so we compare against what's already there and gate on
  # that — re-lighting the same token (the common case) is a write but no redraw.
  local before; before="$(rec_get "$ws" status "$lane" "")"
  rec_set "$ws" status "$lane" "" "$token"
  if (( _SIG_TRANSIENT )); then
    rec_set "$ws" status "$lane" transient 1
    _ensure_unfocus_hook
  else
    rec_unset "$ws" status "$lane" transient
  fi
  if [[ "$token" != "$before" ]]; then _redraw; fi
}

# clear <lane> [-t target]
airline_status_clear () {
  local lane="$1"; shift
  local ws; ws="$(_wscope "$@")"
  local before; before="$(rec_get "$ws" status "$lane" "")"
  rec_unset "$ws" status "$lane" ""
  rec_unset "$ws" status "$lane" transient
  if [[ -n "$before" ]]; then _redraw; fi   # only if a badge was actually lit
}

# list   lanes by priority: name, priority, glyph, current value on the window.
airline_status_list () {
  local lane
  while IFS= read -r lane; do
    [[ -z "$lane" ]] && continue
    printf '%s\tprio=%s\tglyph=%s\tvalue=%s\n' "$lane" \
      "$(rec_get -g status "$lane" prio 50)" \
      "$(rec_get -g status "$lane" glyph ●)" \
      "$(rec_get -w status "$lane" "")"
  done < <(_status_sorted_lanes)
}

# --- health (a per-window "health" record store, reduced by max severity) ---
# Each contributor is a per-window record (severity as the primary value).
# airline reduces the roster to the worst severity and caches it in the option
# below, which the gutter renders. stress > alert > ok; ok/none → cleared.
#
# This is airline's one piece of *derived* state: a cache of max(health records),
# kept in sync only by _health_reduce. It exists because a tmux format can't walk
# the roster to compute the max live, so we precompute the scalar where the
# format can read it. Internal — never set by hand; like every @airline-* name
# it's private and reached only through this one accessor.
AIRLINE_HEALTH_REDUCED="@airline-health"

# Reduce the health roster to its worst severity and write the cached scalar (the
# bar renders this, not the per-key records). A plain idempotent writer — callers
# that gate a redraw read this option before and after, so the change detection
# stays local to them. _health_reduced_value reads it back for that comparison.
_health_reduced_value () {   # <wscope>
  # SC2086: $ws is a word-split tmux scope ("-w -t @2"); see scripts/record.sh.
  # shellcheck disable=SC2086
  tmux show-option $1 -qv "$AIRLINE_HEALTH_REDUCED"
}

_health_reduce () {   # <wscope>
  local ws="$1" key sev best=0 max="" r
  for key in $(rec_ids "$ws" health); do
    sev="$(rec_get "$ws" health "$key" "")"
    case "$sev" in stress) r=3 ;; alert) r=2 ;; ok) r=1 ;; *) r=0 ;; esac
    (( r > best )) && { best=$r; max="$sev"; }
  done
  [[ "$max" != "stress" && "$max" != "alert" ]] && max=""   # ok/none → cleared
  # SC2086: $ws is a word-split tmux scope ("-w -t @2"); see scripts/record.sh.
  # shellcheck disable=SC2086
  if [[ -n "$max" ]]; then tmux set $ws "$AIRLINE_HEALTH_REDUCED" "$max"
  else tmux set $ws -u "$AIRLINE_HEALTH_REDUCED" 2>/dev/null || true; fi
}

# set <key> <severity> [--transient] [-t target]
airline_health_set () {
  local key="$1" sev="$2"; shift 2
  _parse_signal_args "$@"; local ws="$_SIG_WSCOPE"
  _is_lane_name "$key" || { _err "invalid health key: $key"; return; }
  _is_severity "$sev"  || { _err "severity must be ok|alert|stress: $sev"; return; }
  rec_set "$ws" health "$key" "" "$sev"
  rec_add "$ws" health "$key"
  if (( _SIG_TRANSIENT )); then
    rec_set "$ws" health "$key" transient 1
    _ensure_unfocus_hook
  else
    rec_unset "$ws" health "$key" transient
  fi
  # Redraw only when the reduced (rendered) severity moves — a contributor that
  # doesn't change the max writes a record but triggers no redraw.
  local before; before="$(_health_reduced_value "$ws")"
  _health_reduce "$ws"
  if [[ "$(_health_reduced_value "$ws")" != "$before" ]]; then _redraw; fi
}

# clear <key> [-t target]
airline_health_clear () {
  local key="$1"; shift
  local ws; ws="$(_wscope "$@")"
  rec_del "$ws" health "$key" transient
  local before; before="$(_health_reduced_value "$ws")"
  _health_reduce "$ws"
  if [[ "$(_health_reduced_value "$ws")" != "$before" ]]; then _redraw; fi
}

# list   each contributor's severity + the reduced result on the window.
airline_health_list () {
  local ws key; ws="$(_wscope "$@")"
  for key in $(rec_ids "$ws" health); do
    printf '%s\t%s\n' "$key" "$(rec_get "$ws" health "$key" "")"
  done
  # shellcheck disable=SC2086  # $ws is a word-split tmux scope (see record.sh)
  printf 'reduced\t%s\n' "$(tmux show-option $ws -qv "$AIRLINE_HEALTH_REDUCED")"
}

# Rebuild everything a roster change can affect — window formats and both status
# bars. Needs the palette, so load the theme first; all of it is idempotent.
_airline_rebuild () {
  load_theme
  set_window_formats
  tmux set -gq status-left  "$(_build_status_left)"
  tmux set -gq status-right "$(_build_status_right)"
}

# --- consume-on-view (transient signals) ------------------------------------
# A signal set with --transient clears itself once you've viewed the window and
# moved on. The setter can't observe being seen, so airline does it: on
# pane-focus-out it hands the window that lost focus to `airline _unfocus`, which
# clears that window's --transient lanes/keys. Sticky signals (no --transient)
# are left to their setter.

# Fixed hook index — indexing makes (re)registration idempotent, so a reload or
# repeated --transient never stacks duplicate copies (set-hook -a would).
AIRLINE_HOOK_IDX_UNFOCUS=90

# Register the focus hook and enable focus-events (which the feature needs).
# Called lazily, only when a --transient signal is set, so airline doesn't turn
# focus reporting on for users who never use transience.
_ensure_unfocus_hook () {
  tmux set -g focus-events on
  tmux set-hook -g "pane-focus-out[$AIRLINE_HOOK_IDX_UNFOCUS]" \
    "run-shell -b \"$CURRENT_DIR/airline _unfocus #{window_id}\""
}

# Clear every --transient signal on <window>, then re-reduce health and redraw.
# Invoked by the pane-focus-out hook with the window that lost focus. Roster-
# driven (status lanes are a global registry; health keys a per-window one), so
# no option-name globbing or parsing — just check each record's transient flag.
airline_unfocus () {
  local win="$1" ws lane key changed=0
  [[ -n "$win" ]] || return 0
  ws="$(_wscope -t "$win")"
  for lane in $(rec_ids -g status); do
    if [[ -n "$(rec_get "$ws" status "$lane" transient)" ]]; then
      rec_unset "$ws" status "$lane" ""
      rec_unset "$ws" status "$lane" transient
      changed=1
    fi
  done
  for key in $(rec_ids "$ws" health); do
    if [[ -n "$(rec_get "$ws" health "$key" transient)" ]]; then
      rec_del "$ws" health "$key" transient
      changed=1
    fi
  done
  if (( changed )); then
    _health_reduce "$ws"
    _redraw
  fi
  return 0
}

#-----------------------------------------------------------------------------#
#
# Build status line components
#
#-----------------------------------------------------------------------------#

# The left and right status bars are a registered, ordered stack of segments —
# not six fixed slots. Each segment has a side (left|right), a priority
# (ascending = closer to the window list), a background tier (outer|middle|inner)
# for the powerline depth, and content. Content is either a literal tmux format
# (--format, for plugins/users) or a built-in generator (--gen, for the shipped
# widgets, so they re-render under the current theme). Like the status lanes, the
# roster is CLI-managed and changing it rebuilds the bar; @airline-segment-* are
# private. Plugins add segments with `airline segment`, never by hand.

# Built-in segment content generators for the widgets that need real work. The
# plugin widgets (online/prefix/cpu) are just their configure_* functions, used
# as generators directly; only these two need wrapping.
_seg_host () { hostname | cut -d '.' -f 1; }
_seg_date () {
  local d="%Y-%m-%d %H:%M" b
  b="$(configure_battery)"
  [[ -n "$b" ]] && d="$d $b"
  printf '%s' "$d"
}

# Registered segment ids on a side, ascending priority (stable on ties). One
# unified "segment" roster; side is an attribute we filter on at render time.
_segments_sorted () {
  local side="$1" id
  for id in $(rec_sorted -g segment prio); do
    [[ "$(rec_get -g segment "$id" side)" == "$side" ]] && printf '%s\n' "$id"
  done
}

# Resolve a segment's background tier. A segment's tier is normally *derived*
# from its depth in the side stack — the powerline gradient is a function of
# position, so the caller shouldn't hand-maintain (and risk mismatching) it:
# the block at the outer edge is `outer`, the next in is `middle`, the rest
# `inner`. The edge is the far end from the window list, which is index 0 on the
# left but the last index on the right. A stored tier is an explicit override
# (the `--tier` flag); empty means derive. `idx`/`count` are the segment's
# position in its side stack.
_segment_tier () {
  local side="$1" idx="$2" count="$3" seg="$4" override d
  override="$(rec_get -g segment "$seg" tier "")"
  [[ -n "$override" ]] && { printf '%s' "$override"; return; }
  if [[ "$side" == left ]]; then d="$idx"; else d=$(( count - 1 - idx )); fi
  case "$d" in 0) printf outer ;; 1) printf middle ;; *) printf inner ;; esac
}

# Resolve a segment's content: run its generator, else its stored format.
_segment_content () {
  local name="$1" gen
  gen="$(rec_get -g segment "$name" gen)"
  if [[ -n "$gen" ]]; then "$gen"; else rec_get -g segment "$name" format; fi
}

# Low-level define (no rebuild). Trailing arg is --gen <fn> or --format <fmt>.
# tier "" means derive from position (see _segment_tier); a non-empty tier is a
# stored override.
_segment_define () {
  local name="$1" side="$2" prio="$3" tier="$4"; shift 4
  local gen="" fmt=""
  case "${1:-}" in --gen) gen="$2" ;; --format) fmt="$2" ;; esac
  rec_set -g segment "$name" side   "$side"
  rec_set -g segment "$name" prio   "$prio"
  rec_set -g segment "$name" tier   "$tier"
  rec_set -g segment "$name" gen    "$gen"
  rec_set -g segment "$name" format "$fmt"
  rec_add -g segment "$name"
}

# Compose status-left: blocks left→right, each followed by a chevron into the
# next segment's tier (or the inner-bg window list after the last one).
_build_status_left () {
  local fg="${THEME[emphasized]}" out="" seg bg next_bg i
  local -a segs=()
  while IFS= read -r seg; do [[ -n "$seg" ]] && segs+=("$seg"); done < <(_segments_sorted left)
  local n=${#segs[@]}
  for (( i = 0; i < n; i++ )); do
    seg="${segs[i]}"
    bg="${THEME[$(_segment_tier left "$i" "$n" "$seg")-bg]}"
    if (( i + 1 < n )); then
      next_bg="${THEME[$(_segment_tier left "$((i+1))" "$n" "${segs[i+1]}")-bg]}"
    else
      next_bg="${THEME[inner-bg]}"
    fi
    out+="#[fg=$fg,bg=$bg] $(_segment_content "$seg") $(chev_right "$bg" "$next_bg")"
  done
  printf '%s' "$out"
}

# Compose status-right: each segment preceded by a chevron from the previous
# tier (the inner-bg window list before the first one).
_build_status_right () {
  local fg="${THEME[emphasized]}" out="" seg bg prev_bg="${THEME[inner-bg]}" i
  local -a segs=()
  while IFS= read -r seg; do [[ -n "$seg" ]] && segs+=("$seg"); done < <(_segments_sorted right)
  local n=${#segs[@]}
  for (( i = 0; i < n; i++ )); do
    seg="${segs[i]}"
    bg="${THEME[$(_segment_tier right "$i" "$n" "$seg")-bg]}"
    out+="$(chev_left "$prev_bg" "$bg")#[fg=$fg,bg=$bg] $(_segment_content "$seg") "
    prev_bg="$bg"
  done
  printf '%s' "$out"
}

# Register the shipped default segments, once per server (sentinel-gated so a
# reload doesn't clobber user customization). Their content regenerates on each
# rebuild via the generators, so widgets follow the active theme and plugin set.
register_default_segments () {
  [[ "$(get_tmux_option @airline-defaults-done 0)" == "1" ]] && return
  # No explicit tier: each segment's background is derived from its depth in the
  # side stack (see _segment_tier), which reproduces the outer→middle→inner
  # gradient these priorities lay out.
  _segment_define online left  10 "" --gen configure_online
  _segment_define host   left  20 "" --gen _seg_host
  _segment_define prefix right 10 "" --gen configure_prefix_highlight
  _segment_define cpu    right 20 "" --gen configure_cpu
  _segment_define date   right 30 "" --gen _seg_date
  tmux set -g @airline-defaults-done 1
}

# --- CLI: airline segment ---------------------------------------------------

# register <name> --side left|right --format <tmux-format>
#                 [--priority N] [--tier outer|middle|inner]   (idempotent; rebuilds)
#
# --side and --format are required: a segment must declare which stack it joins,
# and content is the whole point of one. --priority defaults to 50. --tier is an
# OVERRIDE — omit it and the background is derived from the segment's depth in
# the stack (see _segment_tier); pass it only to force a specific tier.
airline_segment_register () {
  local name="${1:-}"; shift || true
  local side="" prio=50 tier="" fmt=""
  _is_lane_name "$name" || { _err "invalid segment name: $name"; return; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --side)     side="$2"; shift 2 ;;
      --priority) prio="$2"; shift 2 ;;
      --tier)     tier="$2"; shift 2 ;;
      --format)   fmt="$2";  shift 2 ;;
      *) _err "unknown segment option: $1"; return ;;
    esac
  done
  case "$side" in left|right) ;; "") _err "segment requires --side left|right"; return ;;
                  *) _err "side must be left|right: $side"; return ;; esac
  [[ -z "$tier" ]] || case "$tier" in outer|middle|inner) ;;
                  *) _err "tier must be outer|middle|inner: $tier"; return ;; esac
  [[ "$prio" =~ ^[0-9]+$ ]] || { _err "priority must be an integer: $prio"; return; }
  [[ -n "$fmt" ]] || { _err "segment requires --format <tmux-format>"; return; }
  _segment_define "$name" "$side" "$prio" "$tier" --format "$fmt"
  _airline_rebuild
}

# unregister <name>   (drop the segment; rebuilds the bar)
airline_segment_unregister () {
  rec_del -g segment "$1" side prio tier gen format
  _airline_rebuild
}

# list   segments per side, in render order: name, side, priority, tier. The
# tier shown is the *resolved* one (derived from position unless overridden), so
# the listing matches what the bar actually renders.
airline_segment_list () {
  local side seg i
  for side in left right; do
    local -a segs=()
    while IFS= read -r seg; do [[ -n "$seg" ]] && segs+=("$seg"); done < <(_segments_sorted "$side")
    local n=${#segs[@]}
    for (( i = 0; i < n; i++ )); do
      seg="${segs[i]}"
      printf '%s\tside=%s\tprio=%s\ttier=%s\n' "$seg" "$side" \
        "$(rec_get -g segment "$seg" prio 50)" \
        "$(_segment_tier "$side" "$i" "$n" "$seg")"
    done
  done
}

set_window_formats () {
  local template bg
  template="$(get_tmux_option @airline-tmpl-window '#I:#W')"
  bg="${THEME[inner-bg]}"

  # Entry color: tmux modes > baseline, in the single signal slot (fg when
  # inactive, highlight bg when focused — see "Window entry color" above).
  local mode_fg hi_expr
  mode_fg="$(window_mode_fg)"
  hi_expr="$(window_mode_hi)"

  # Health gutter (left): one glyph at the window's reduced severity; empty when
  # healthy. Status stack (right): one glyph per lit lane, ascending priority.
  local hglyph health_expr status_expr="" lane glyph
  hglyph="$(get_tmux_option @airline-health-glyph "●")"
  health_expr="#{?${AIRLINE_HEALTH_REDUCED},#[fg=$(palette_token_expr "$AIRLINE_HEALTH_REDUCED" "${THEME[primary]}")]$hglyph ,}"
  while IFS= read -r lane; do
    [[ -z "$lane" ]] && continue
    glyph="$(rec_get -g status "$lane" glyph ●)"
    status_expr+="#{?$(rec_key status "$lane"), #[fg=$(palette_token_expr "$(rec_key status "$lane")" "${THEME[primary]}")]$glyph,}"
  done < <(_status_sorted_lanes)

  tmux set -gq window-status-separator-string " "

  # inactive: health gutter, then #[default] to restore the applicable style so
  # the gutter glyph's color can't bleed into the name, then the mode fg (if a
  # mode is active), the name, and finally the status stack.
  tmux set -gq window-status-format \
    "${health_expr}#[default]${mode_fg}${template}${status_expr}"

  # baseline positional styles for inactive windows
  tmux set -gq window-status-style "fg=${THEME[primary]} bg=$bg"
  tmux set -gq window-status-last-style "fg=${THEME[emphasized]} bg=$bg"
  tmux set -gq window-status-activity-style "fg=${THEME[alert]} bg=$bg"
  tmux set -gq window-status-bell-style "fg=${THEME[stress]} bg=$bg"

  # focused window: a reverse-video block. The highlight bg is the active mode's
  # color, else the normal active highlight; the chevrons follow it. The name is
  # knocked out in inner-bg (#[fg=$bg]); the health gutter and status stack sit
  # inside the block, each setting its own fg.
  tmux set -gq window-status-current-format \
    "$(chev_right "$bg" "$hi_expr") ${health_expr}#[fg=$bg]${template}${status_expr} $(chev_left "$hi_expr" "$bg")"
}

#-----------------------------------------------------------------------------#
#
# Set status elements
#
#-----------------------------------------------------------------------------#

main () {
  # Publish the CLI path so cooperating plugins can drive airline without
  # guessing the install location: `"$(tmux show -gqv @airline-cli)" status …`.
  # One well-known option, consistent with airline's everything-via-options model.
  tmux set -gq @airline-cli "$CURRENT_DIR/airline"

  # Configure panes, use highlight color for active panes
  tmux set -gq pane-border-style "fg=${THEME[primary]}"
  tmux set -gq pane-active-border-style "fg=${THEME[active]}"
  tmux set -gq display-panes-color "${THEME[primary]}"
  tmux set -gq display-panes-active-color "${THEME[active]}"

  # Build the status bar
  tmux set -gq status-style "fg=${THEME[secondary]} bg=${THEME[inner-bg]}"

  # Configure window status
  set_window_formats

  # Status-bar segments: register the shipped defaults (once), then compose.
  register_default_segments
  tmux set -gq status-left-style  "fg=${THEME[primary]} bg=${THEME[outer-bg]}"
  tmux set -gq status-right-style "fg=${THEME[primary]} bg=${THEME[outer-bg]}"
  tmux set -gq status-left  "$(_build_status_left)"
  tmux set -gq status-right "$(_build_status_right)"

  tmux set -gq clock-mode-color "${THEME[special]}"

  tmux bind -T root F12 run-shell "$CURRENT_DIR/airline suspend"
  tmux bind -T off  F12 run-shell "$CURRENT_DIR/airline resume"

}

#-----------------------------------------------------------------------------#
#
# Suspend / resume (for nested sessions) — invoked via the `airline` CLI
#
#-----------------------------------------------------------------------------#

# Disable the outer prefix and dim the bar so keystrokes pass to the inner
# session. main() rebuilds the bar with the suspended palette (load_theme
# applies the dimming when @airline-suspended is 1).
airline_suspend () {
  tmux set -g @airline-suspended 1
  tmux set -g prefix None
  tmux set -g key-table off
  load_theme
  main
}

# Restore the outer prefix, key-table, and normal palette.
airline_resume () {
  tmux set -g @airline-suspended 0
  tmux set -u prefix
  tmux set -u key-table
  load_theme
  main
}

# Skip startup when sourced as a library: by the test harness (AIRLINE_TESTING)
# or by the `airline` CLI (AIRLINE_LIB_ONLY), which both want the functions
# without building the bar.
if [[ "${AIRLINE_TESTING:-}" != "1" && "${AIRLINE_LIB_ONLY:-}" != "1" ]]; then
  load_theme
  main
fi

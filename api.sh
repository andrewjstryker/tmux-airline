#!/usr/bin/env bash
#
# api.sh — the public command API and its private implementation.
#
# This layer holds no command dispatch or help: that is the CLI's job in `airline`.
# Each public api_* function establishes context and owns the complete operation;
# underscore-prefixed helpers are private implementation. The API owns input
# validation and drives the layers below (opt_* / coll_* to mutate state, `render`
# to produce the bar). Sourced on top of tmux.sh +
# collections.sh + render.sh + runner.sh.
#
# The verb grammar (in `airline`) splits on the state model these functions implement.
# Dynamic nouns (status, health, problem) are live and scriptable: set + re-project a
# badge + redraw. Static config nouns (palette, segment) are read-only at the CLI;
# runner adds process-lifecycle orchestration over those existing signals. Users
# provide global defaults through `.tmux.conf`; palette/layout selections create
# session overrides. We read the effective values and `apply` bakes rendered
# configuration while ephemeral runner updates remain live.

# shellcheck shell=bash

if ! declare -F runner_classifier_load >/dev/null; then
  printf 'api.sh: load runner.sh (and its layers) first\n' >&2
  return 1 2>/dev/null || exit 1
fi

die () { printf 'airline: %s\n' "$*" >&2; exit 2; }

# Public API entry points resolve their execution context through tmux. An inherited
# AIRLINE_SESSION is deliberately not consulted: that variable is output supplied to
# a running layout, not a hidden user-facing target mechanism.
_require_current_session () {
  local session
  session="$(current_session)"
  [[ -n "$session" ]] || die "cannot resolve current session"
  printf '%s' "$session"
}

# Store one session problem and refresh its aggregate projection. This is the shared
# write path for the public command and airline's own managed components.
# `ok` is a recovery event, not retained state. Return 0 only when the visible badge
# changed, allowing the public path to skip redundant redraws.
_problem_store_unlocked () {   # <session> <key> <ok|warn|fail> [<message>]
  local session="$1" key="$2" level="$3" message="${4:-}" tuple desired
  local changed="" projected=1
  if [[ "$level" == ok ]]; then
    tuple="$(coll_get_session "$session" problem "$key")"
    if coll_has_session "$session" problem "$key" || [[ -n "$tuple" ]]; then
      coll_unregister_session "$session" problem "$key"
      changed=1
    fi
  else
    tuple="$(coll_get_session "$session" problem "$key")"
    desired="$(printf '%s\t%s' "$level" "$message")"
    if ! coll_has_session "$session" problem "$key" || [[ "$tuple" != "$desired" ]]; then
      coll_set_session "$session" problem "$key" "$level" "$message"
      changed=1
    fi
  fi
  if [[ -n "$changed" ]] && problem_project "$session"; then projected=0; fi
  return "$projected"
}

_problem_store () {   # <session> <key> <ok|warn|fail> [<message>]
  with_session_transaction "$1" problem _problem_store_unlocked "$@"
}

# One "label   value" row — the single home for the `show` column width, so every
# noun's show and the top-level summary align identically.
_show_row () { printf '%-12s %s\n' "$1" "$2"; }

#-----------------------------------------------------------------------------#
# Lifecycle
#-----------------------------------------------------------------------------#

# True when no segment slot is set yet (a fresh install) — gates default seeding.
_segments_unset () {   # <session>
  local session="$1" s
  for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    [[ -n "$(pub_get_session "$session" "segment-$s")" ]] && return 1
  done
  return 0
}

# Bootstrap (the `init` command). Publish the CLI path and, on first run, seed defaults
# behind a sentinel (without clobbering user config or runtime state on a reload); then
# render.
_init () {   # <session>
  local session="$1"
  # The CLI path is the ONE published (public) option — the bootstrap handle, since a
  # script can't call the API to discover where the API lives. Everything else about
  # airline's state is read through the CLI, never a private option. Airline binds no
  # keys — a user wires their own (e.g. `bind F12 run "#{@airline-cli} state toggle"`).
  pub_set "$AIRLINE_KEY_CLI" "$AIRLINE_DIR/airline"
  # tmux loads plugins once per server, but airline owns session-local runtime
  # state. Seed each later session through one indexed global infrastructure hook.
  hook_set "after-new-session[90]" \
    "run-shell -b \"'$AIRLINE_DIR/airline' _init-session '#{session_id}'\""

  # Register airline's own shipped config dirs on each loadable kind's search path.
  # (segment is not loadable — it's public options a layout sets, or the user sets.)
  _path_register_self "$session" palette "$AIRLINE_DIR/palettes"
  _path_register_self "$session" adapter "$AIRLINE_DIR/adapters"
  _path_register_self "$session" layout  "$AIRLINE_DIR/layouts"
  _path_register_self "$session" classifier "$AIRLINE_DIR/classifiers"
  _path_register_self "$session" filter "$AIRLINE_DIR/filters"
  _path_register_self "$session" probe "$AIRLINE_DIR/probes"
  _path_register_self "$session" runner  "$AIRLINE_DIR/runners"

  # First run only (sentinel): apply the default of each axis the user hasn't set —
  # the default PALETTE if no palette is present, the default LAYOUT (which brings its
  # own segments) if no segments are. `default` is a name on the search path, so a
  # user's own `default` (registered earlier) wins. Renders deferred to the final one.
  if [[ "$(prv_get_session "$session" "$AIRLINE_KEY_DEFAULTS")" != 1 ]]; then
    [[ -z "$(pub_get_session "$session" inner-bg)" ]] && _load_config "$session" palette default
    _segments_unset "$session" && _apply_layout "$session" adaptive
    prv_set_session "$session" "$AIRLINE_KEY_DEFAULTS" 1
  fi
  render "$session" || true
}

# Render, unless we're mid-layout (a layout defers to one redraw at the end via a
# local _AIRLINE_DEFER that dynamic scoping makes visible to the nested use handlers).
_render () {   # <session>
  [[ -n "${_AIRLINE_DEFER:-}" ]] && return 0
  render "$1" || true
}

# The `apply` command: re-run the active layout (re-applies its adapters against the
# current palette and re-sets its segments), then render. This is the re-apply engine —
# a palette swap is `palette use X` (or a raw set) followed by apply.
_apply () {   # <session>
  local session="$1" lay
  lay="$(prv_get_session "$session" layout)"
  [[ -n "$lay" && -n "$(_layout_file "$session" "$lay")" ]] && _apply_layout "$session" "$lay"
  render "$session" || true
}

# The top-level `show` command: the active configuration. The non-noun globals first
# (the bootstrap handle, lifecycle state, and the search paths), then each CONFIG noun's
# own bare `show` — the noun reports its own active state, so nothing is printed twice (a
# palette/layout name shows once, inside its section). The dynamic per-window nouns
# (status/health/problem) are NOT global config, so they're excluded — inspect them
# through their own `show` commands. Mirrors exactly what each `<noun> show` prints bare.
_show_config () {   # <session>
  local session="$1"
  _show_row cli   "$(pub_get cli)"              # the one public (bootstrap) handle
  _show_row state "$(_state_word "$session")"  # lifecycle (active | suspended)
  printf '\npaths:\n'                           # catalog resolution, priority order
  local k
  for k in palette adapter layout classifier filter probe runner; do
    _show_row "$k" "$(coll_members_session "$session" "$(_path_ns "$k")")"
  done
  printf '\npalette:\n'; _palette_show "$session"
  printf '\nsegment:\n'; _static_show "$session" "segment-" _segment_slot_valid AIRLINE_SEGMENT_SLOTS
  printf '\nadapter:\n'; _adapter_show "$session"
  printf '\nlayout:\n';  _layout_show "$session"
}

#-----------------------------------------------------------------------------#
# Search paths — registered catalogs and the `use` mechanism
#-----------------------------------------------------------------------------#
# Each config kind (palette, layout/segment, adapter) has an ordered search PATH of
# directories, stored via collections.sh: the kind's registry list IS the path, in
# priority order. `<kind> use <name>` resolves <name> to the FIRST matching file on
# that path (or a literal path when it contains '/'), sources it, and renders.
# airline registers its own shipped dir per kind at init. (`register` to add more —
# piece 2.) Limitation: the path lives in a space-delimited registry, so a directory
# containing a space is unsupported — config/plugin dirs don't have spaces.

_path_ns () { printf 'path-%s' "$1"; }        # kind → collection ns

# Register airline's own shipped dir for a kind (idempotent; skips if absent).
_path_register_self () {   # <session> <kind> <dir>
  local session="$1" kind="$2" dir="$3"
  [[ -d "$dir" ]] && coll_register_session "$session" "$(_path_ns "$kind")" "$dir"
}

# Resolve a bare <name> to the first hit walking the kind's path. Names are simple
# (no '/'): `use` only reaches BLESSED locations — `register` a dir to add one; there
# is no literal-path escape hatch (we don't load/execute from arbitrary paths).
# Echoes the file path, empty when unresolved.
_path_resolve () {   # <session> <kind> <name>
  local session="$1" kind="$2" name="$3" dir
  [[ "$name" == */* ]] && return          # not a bare name → unresolvable here
  for dir in $(coll_members_session "$session" "$(_path_ns "$kind")"); do
    [[ -f "$dir/$name" ]] && { printf '%s' "$dir/$name"; return; }
  done
}

# List every bare name resolvable on the kind's path — the catalog selection surface.
# One name per line, deduped in path order (a shadowing user dir collapses with the
# shipped name it overrides). The read-side counterpart to _path_resolve; the shared
# core of every noun's `available` verb (palette / adapter / layout).
_path_available () {   # <session> <kind>
  local session="$1" kind="$2" dir f name seen=" "
  for dir in $(coll_members_session "$session" "$(_path_ns "$kind")"); do
    [[ -d "$dir" ]] || continue
    for f in "$dir"/*; do
      [[ -f "$f" ]] || continue
      name="${f##*/}"
      case "$seen" in *" $name "*) continue ;; esac
      seen+="$name "; printf '%s\n' "$name"
    done
  done
}

# Prepend a dir to a kind's search path — the one trust boundary: registering a dir
# blesses it, and only then can `use` reach names inside it.
_register () {   # <session> <kind> <dir>
  local session="$1" kind="$2" dir="${3:-}"
  [[ -n "$dir" ]] || die "$kind register: need <dir>"
  [[ -d "$dir" ]] || die "$kind register: no such directory: $dir"
  coll_prepend_session "$session" "$(_path_ns "$kind")" "$dir"
}

# Resolve each bare name on the kind's path, source the tmux conf, record it active
# (@airline--<kind>). NO render — the caller renders: `palette use` re-applies via
# `apply`, so a palette swap re-runs the layout and re-colours its adapters. Only
# `palette` is loadable now (segment is set by layouts), but the mechanism stays generic.
_load_config () {   # <session> <kind> <name...>
  local session="$1" kind="$2"; shift 2
  [[ $# -gt 0 ]] || die "$kind use: need <name>"
  local name file
  for name in "$@"; do                    # multi-target: later files compose over earlier
    [[ "$name" != */* ]] || die "$kind use: '$name' — use a bare name (register a dir to add locations)"
    file="$(_path_resolve "$session" "$kind" "$name")"
    [[ -n "$file" ]] || die "$kind use: '$name' not found on the $kind path"
    source_file_session "$session" "$file"
    prv_set_session "$session" "$kind" "$name" # active selection (last wins)
  done
}

# adapter use <name>: DYNAMIC — an adapter is a bash snippet that sets a plugin's
# @<plugin>-* options from the current palette. Resolve it on the adapter path, load
# PALETTE, then `source` the snippet (bash, not source-file) so it can read PALETTE
# and call opt_set_session. Reached through a layout (piece C); the layout's stored
# path is re-run on a palette change, which re-runs this and re-applies the colours.
# Resolve <path> to an absolute path (dir resolved via cd+pwd; the file itself is
# checked by the caller). `load` records this so a later `apply`, running from another
# cwd, still finds it.
_abspath () {   # <path> → absolute
  local dir base
  dir="$(dirname -- "$1")"; base="$(basename -- "$1")"
  printf '%s/%s' "$(cd -- "$dir" 2>/dev/null && pwd)" "$base"
}

# Run one adapter file: load PALETTE, then source the snippet so it can set the
# plugin's @<plugin>-* options from PALETTE. The shared core of `use` and `load`.
_source_adapter () {   # <session> <file>
  # AIRLINE_SESSION is consumed by the sourced adapter contract.
  # shellcheck disable=SC2034
  local AIRLINE_SESSION="$1" file="$2"
  _palette_load
  # shellcheck source=/dev/null
  source "$file"
}

# adapter use <name...>: resolve each bare name on the adapter path and run it, then
# record it in the active set (`adapters` collection) for `adapter show`.
_apply_adapter () {   # <session> <name...>
  local session="$1"; shift
  [[ $# -gt 0 ]] || die "adapter use: need <name>"
  local name file
  for name in "$@"; do
    [[ "$name" != */* ]] || die "adapter use: '$name' — bare name (or 'adapter load <path>')"
    file="$(_path_resolve "$session" adapter "$name")"
    [[ -n "$file" ]] || die "adapter use: '$name' not found on the adapter path"
    _source_adapter "$session" "$file"
    coll_register_session "$session" adapters "$name" # applied in this session
  done
}

# adapter load <path>: run a one-off adapter script by path (no path walk). Unlike
# `layout load`, the record is for DISCOVERY, not re-run: `apply` re-runs the layout,
# which re-invokes its adapters — so we keep only the applied name (the basename) for
# `adapter show`, not the path. A durable custom adapter lives in a layout that
# `adapter load`s it. The user owns the file (it sources arbitrary bash).
_load_adapter () {   # <session> <path>
  local session="$1" path="${2:-}"; [[ -n "$path" ]] || die "adapter load: need <path>"
  local abs; abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || die "adapter load: no such file: $path"
  _source_adapter "$session" "$abs"
  coll_register_session "$session" adapters "${abs##*/}"
}

# Resolve a layout HANDLE to a file: a bare name (from `use`/default) → the search
# path; a path (from `load`, recorded absolute) → itself. The slash tells them apart —
# reusing the invariant that names never contain '/'.
_layout_file () {   # <session> <handle> → file (empty if unresolved)
  local session="$1" handle="$2"
  if [[ "$handle" == */* ]]; then [[ -f "$handle" ]] && printf '%s' "$handle"
  else _path_resolve "$session" layout "$handle"; fi
}

# A layout is a SHELL SCRIPT. Record <handle> as active, then EXECUTE the file with
# `airline` on PATH and AIRLINE_DIR in the env — so it composes by calling
# `airline adapter use …` (dynamic) and writing its segment options directly with
# `$AIRLINE_TMUX set -t "$AIRLINE_SESSION"` (segments are just options), and may
# `source` helpers (e.g.
# the TPM probe). `apply` re-runs the recorded handle — the re-apply engine.
#
# Orthogonality (a layout must not set the palette) is a CONVENTION, not enforced. The
# re-entrancy guard makes a violation benign: while a layout runs, @airline--applying is
# set, so a nested `apply`/`palette use` renders but does NOT re-enter the layout — no
# apply→layout→apply loop. A failed script is contained, surfaced as a session
# problem, and cleared automatically after a later successful application.
_apply_layout () {   # <session> <handle>  (bare name, or absolute path from load)
  local session="$1" handle="${2:-}" file rc=0
  local layout_dir="$AIRLINE_DIR" layout_cli="$AIRLINE_DIR/airline" layout_path="$AIRLINE_DIR:$PATH"
  [[ "$(prv_get_session "$session" applying)" == 1 ]] && return 0
  file="$(_layout_file "$session" "$handle")"
  [[ -n "$file" ]] || die "layout: '$handle' not found"
  prv_set_session "$session" layout "$handle"
  prv_set_session "$session" applying 1
  _clear_segments "$session" # clean slate — the layout owns the arrangement
  _clear_adapters "$session" # …and owns its adapter set
  # AIRLINE_TMUX (the seam, defaulted to plain tmux) lets a layout set its segment
  # options directly and cheaply with an explicit session target — no airline subprocess.
  # _AIRLINE_DEFER=1 reaches the nested `airline …` calls via the env, so their renders
  # are suppressed (_render); the caller renders ONCE after this returns.
  AIRLINE_DIR="$layout_dir" AIRLINE_CLI="$layout_cli" \
    AIRLINE_SESSION="$session" AIRLINE_TMUX="${AIRLINE_TMUX:-tmux}" \
    _AIRLINE_DEFER=1 PATH="$layout_path" bash "$file" || rc=$?
  prv_set_session "$session" applying 0
  if (( rc == 0 )); then
    _problem_store "$session" airline-layout ok "" || true
  else
    _problem_store "$session" airline-layout fail "layout '$handle' exited with status $rc" || true
  fi
}

# Unset every segment slot. The clean slate a layout starts from, so it only sets what
# it wants and a switch leaves nothing stale. Safe because init applies a default layout
# ONLY when no segments are set — a "define the options yourself" user never runs a
# layout, so this never wipes their directly-set segment options.
_clear_segments () {   # <session>
  local session="$1" s; for s in "${AIRLINE_SEGMENT_SLOTS[@]}"; do
    pub_set_session "$session" "segment-$s" ""
  done
}

# Drop every recorded active adapter — the clean slate a layout starts from, so the
# active set reflects only what the current layout applied. Ad-hoc `adapter use` outside
# a layout just appends; only a layout switch clears (mirrors _clear_segments).
_clear_adapters () {   # <session>
  local session="$1" a
  for a in $(coll_members_session "$session" adapters); do
    coll_unregister_session "$session" adapters "$a"
  done
}

# layout use <name>: curated — a bare name on the layout path.
_layout_use () {   # <session> <name>
  local session="$1" name="${2:-}"; [[ -n "$name" ]] || die "layout use: need <name>"
  [[ "$name" != */* ]] || die "layout use: '$name' — bare name (or 'layout load <path>')"
  _apply_layout "$session" "$name"
}

# layout load <path>: one-off — run a layout script by path, recording the ABSOLUTE
# path so `apply` re-runs it from any cwd.
_layout_load () {   # <session> <path>
  local session="$1" path="${2:-}"; [[ -n "$path" ]] || die "layout load: need <path>"
  local abs; abs="$(_abspath "$path")"
  [[ -f "$abs" ]] || die "layout load: no such file: $path"
  _apply_layout "$session" "$abs"
}

# layout show: bare → the active layout summarized (its `name` and the resolved file
# `path`, labeled — human); `show name` → the recorded handle, raw; `show path` → the
# resolved file, raw (handy for a `load`ed layout, whose handle already IS a path).
_layout_show () {   # <session> [name|path]
  local session="$1" x="${2:-}" handle; handle="$(prv_get_session "$session" layout)"
  case "$x" in
    name) printf '%s\n' "$handle" ;;
    path) printf '%s\n' "$(_layout_file "$session" "$handle")" ;;
    "")   _show_row name "$handle"
          _show_row path "$(_layout_file "$session" "$handle")" ;;
    *)    die "layout show: unknown field '$x' (name | path)" ;;
  esac
}

#-----------------------------------------------------------------------------#
# Runner catalogs and ephemeral composition of classifier, filter, and probe elements
#-----------------------------------------------------------------------------#

_runner_element_file () {   # <session> <kind> <bare-name>
  local session="$1" kind="$2" name="$3"
  [[ "$kind" == classify ]] && kind=classifier
  _path_resolve "$session" "$kind" "$name"
}

_runner_element_show () {   # <session> <classifier|filter|probe> <name>
  local session="$1" kind="$2" name="${3:-}" file summary usage="" interval=""
  [[ -n "$name" ]] || die "$kind show: need <name>"
  [[ "$name" != */* ]] || die "$kind show: need a bare name"
  file="$(_path_resolve "$session" "$kind" "$name")"
  [[ -n "$file" ]] || die "$kind show: '$name' not found on the $kind path"
  case "$kind" in
    classifier)
      runner_classifier_load "$file" || die "classifier show: '$name' is invalid"
      summary="$AIRLINE_CLASSIFIER_SUMMARY"
      ;;
    filter)
      runner_filter_load "$file" || die "filter show: '$name' is invalid"
      summary="$AIRLINE_FILTER_SUMMARY"
      ;;
    probe)
      runner_probe_load "$file" || die "probe show: '$name' is invalid"
      summary="$AIRLINE_PROBE_SUMMARY"
      usage="$AIRLINE_PROBE_USAGE"
      interval="${AIRLINE_RUNNER_PROBE_INTERVAL:-5} seconds"
      ;;
  esac
  _show_row name "$name"
  _show_row summary "$summary"
  [[ "$kind" == probe ]] && _show_row arguments "${usage:-none}"
  [[ "$kind" == probe ]] && _show_row interval "$interval"
  _show_row path "$file"
}

_runner_definition_show () {   # <session> <name> [<runner-arg>...]
  local session="$1" name="${2:-}" file probe_args=""; shift 2 || true
  [[ -n "$name" ]] || die "runner show: need <name>"
  [[ "$name" != */* ]] || die "runner show: need a bare name"
  file="$(_path_resolve "$session" runner "$name")"
  [[ -n "$file" ]] || die "runner show: '$name' not found on the runner path"
  runner_definition_load "$file" || die "runner show: '$name' is invalid"
  runner_definition_metadata || die "runner show: '$name' has invalid metadata"
  runner_definition_configure "$@" || die "runner show: '$name' produced an invalid configuration"
  if (( ${#AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]} )); then
    printf -v probe_args '%q ' "${AIRLINE_RUNNER_CONFIG_PROBE_ARGS[@]}"
    probe_args="${probe_args% }"
  fi
  _show_row name "$name"
  _show_row summary "$AIRLINE_RUNNER_SUMMARY"
  _show_row arguments "${AIRLINE_RUNNER_USAGE:-none}"
  _show_row classifier "${AIRLINE_RUNNER_CONFIG_CLASSIFIER:-basic}"
  _show_row filter "${AIRLINE_RUNNER_CONFIG_FILTER:-none}"
  [[ -n "$AIRLINE_RUNNER_CONFIG_FILTER_MERGE" ]] && _show_row filter-input merged-stderr
  _show_row probe "${AIRLINE_RUNNER_CONFIG_PROBE:-none}"
  [[ -n "$probe_args" ]] && _show_row probe-args "$probe_args"
  _show_row path "$file"
}

_runner_problem () {   # <session> <key> <ok|warn|fail> [<message>]
  _problem_store "$@" && redraw
  return 0
}

# Globals intentionally cross the filter's background subshell boundary. Each CLI
# invocation owns one run, so concurrent jobs live in separate processes and cannot
# collide here; their tmux contributors are pane-qualified below.
AIRLINE_RUNNER_SESSION=""
AIRLINE_RUNNER_WINDOW=""
AIRLINE_RUNNER_FILTER_KEY=""
AIRLINE_RUNNER_FILTER_PROBLEM=""
AIRLINE_RUNNER_FILTER_LAST=""
AIRLINE_RUNNER_PROBE_KEY=""
AIRLINE_RUNNER_PROBE_PROBLEM=""
AIRLINE_RUNNER_PROBE_LAST=""

_runner_problem_key () {   # <element> <load|classify|filter|probe>
  local name="${1##*/}"
  name="${name//[^a-zA-Z0-9_-]/-}"
  printf 'airline-runner-%s-%s' "$name" "$2"
}

_runner_filter_report () {   # <ok|warn|fail>
  local condition="${1:-}"
  if ! _condition_level_valid "$condition"; then
    _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_FILTER_PROBLEM" fail \
      "runner filter emitted invalid condition '${condition}'"
    return 1
  fi
  _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_FILTER_PROBLEM" ok ""
  [[ "$condition" == "$AIRLINE_RUNNER_FILTER_LAST" ]] && return 0
  AIRLINE_RUNNER_FILTER_LAST="$condition"
  _signal_set health _condition_level_valid ok \
    "$AIRLINE_RUNNER_FILTER_KEY" "$condition" -t "$AIRLINE_RUNNER_WINDOW"
}

_runner_probe_report () {   # <ok|warn|fail>
  local condition="${1:-}"
  if ! _condition_level_valid "$condition"; then
    _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_PROBE_PROBLEM" fail \
      "runner probe emitted invalid condition '${condition}'"
    return 1
  fi
  _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_PROBE_PROBLEM" ok ""
  [[ "$condition" == "$AIRLINE_RUNNER_PROBE_LAST" ]] && return 0
  AIRLINE_RUNNER_PROBE_LAST="$condition"
  _signal_set health _condition_level_valid ok \
    "$AIRLINE_RUNNER_PROBE_KEY" "$condition" -t "$AIRLINE_RUNNER_WINDOW"
}

_runner_probe_error () {
  _runner_problem "$AIRLINE_RUNNER_SESSION" "$AIRLINE_RUNNER_PROBE_PROBLEM" fail \
    "runner probe failed or emitted an invalid condition"
}

_runner_finish () {   # <condition> <window> <key>
  local condition="$1" win="$2" key="$3"
  case "$condition" in
    ok)
      _signal_set health _condition_level_valid ok "$key" ok -t "$win"
      _signal_set status _status_level_valid "" "$key" result --transient -t "$win"
      ;;
    warn|fail)
      _signal_set health _condition_level_valid ok "$key" "$condition" --transient -t "$win"
      _signal_set status _status_level_valid "" "$key" attention --transient -t "$win"
      ;;
  esac
}

# Parsed runner specification. The CLI composes at most one element of each type for
# one operation. Probe arguments end at the next recognized runner option, at `--`
# for run, or at argv exhaustion for watch.
AIRLINE_RUNNER_PLACEMENT=here
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
  local session="$1" mode="$2" name file boundary=""; shift 2
  local -a placement=() extra=() command=()
  AIRLINE_RUNNER_INVOCATION_ARGV=()

  while [[ "${1:-}" == --here || "${1:-}" == --pane || "${1:-}" == --window ]]; do
    placement+=("$1"); shift
  done

  if (( $# == 0 )) || [[ "$1" == --* ]]; then
    AIRLINE_RUNNER_INVOCATION_ARGV=("${placement[@]}" "$@")
    return 0
  fi

  name="$1"; shift
  [[ "$name" != */* ]] || die "runner $mode: runner must be a bare name"
  file="$(_path_resolve "$session" runner "$name")"
  [[ -n "$file" ]] || die "runner $mode: runner '$name' not found"
  runner_definition_load "$file" || die "runner $mode: runner '$name' is invalid"
  runner_definition_metadata || die "runner $mode: runner '$name' has invalid metadata"

  if [[ "$mode" == run ]]; then
    while (( $# )); do
      if [[ "$1" == -- ]]; then
        boundary=1; shift; command=("$@"); break
      fi
      extra+=("$1"); shift
    done
    [[ -n "$boundary" && ${#command[@]} -gt 0 ]] || \
      die "runner run: named runner '$name' needs -- <command>"
    runner_definition_configure "${extra[@]}" || \
      die "runner run: runner '$name' produced an invalid configuration"
    runner_definition_project run
    AIRLINE_RUNNER_INVOCATION_ARGV=(
      "${placement[@]}" "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}" -- "${command[@]}"
    )
  else
    runner_definition_configure "$@" || \
      die "runner watch: runner '$name' produced an invalid configuration"
    if ! runner_definition_project watch; then
      die "runner watch: runner '$name' has no probe"
    fi
    AIRLINE_RUNNER_INVOCATION_ARGV=(
      "${placement[@]}" "${AIRLINE_RUNNER_DEFINITION_ARGV[@]}"
    )
  fi
}

_runner_spec_token () {
  case "${1:-}" in
    --here|--pane|--window|--classify|--filter|--probe|--) return 0 ;;
    *) return 1 ;;
  esac
}

_runner_parse () {   # <run|watch> [spec...]
  local mode="$1"; shift
  AIRLINE_RUNNER_PLACEMENT=here
  AIRLINE_RUNNER_CLASSIFIER=""
  AIRLINE_RUNNER_FILTER=""
  AIRLINE_RUNNER_FILTER_MERGE=""
  AIRLINE_RUNNER_PROBE=""
  AIRLINE_RUNNER_PROBE_ARGS=()
  AIRLINE_RUNNER_COMMAND=()

  while (( $# )); do
    case "$1" in
      --here)   AIRLINE_RUNNER_PLACEMENT=here; shift ;;
      --pane)   AIRLINE_RUNNER_PLACEMENT=pane; shift ;;
      --window) AIRLINE_RUNNER_PLACEMENT=window; shift ;;
      --classify)
        [[ "$mode" == run ]] || die "runner watch: --classify is not applicable"
        [[ -z "$AIRLINE_RUNNER_CLASSIFIER" ]] || die "runner run: classifier already specified"
        [[ $# -ge 2 && -n "$2" ]] || die "runner run: --classify requires <name>"
        AIRLINE_RUNNER_CLASSIFIER="$2"; shift 2 ;;
      --filter)
        [[ "$mode" == run ]] || die "runner watch: --filter is not applicable"
        [[ -z "$AIRLINE_RUNNER_FILTER" ]] || die "runner run: filter already specified"
        [[ $# -ge 2 && -n "$2" ]] || die "runner run: --filter requires <name>"
        AIRLINE_RUNNER_FILTER="$2"; shift 2
        if [[ "${1:-}" == --merge-stderr ]]; then AIRLINE_RUNNER_FILTER_MERGE=1; shift; fi
        ;;
      --probe)
        [[ -z "$AIRLINE_RUNNER_PROBE" ]] || die "runner $mode: probe already specified"
        [[ $# -ge 2 && -n "$2" ]] || die "runner $mode: --probe requires <name>"
        AIRLINE_RUNNER_PROBE="$2"; shift 2
        while (( $# )) && ! _runner_spec_token "$1"; do
          AIRLINE_RUNNER_PROBE_ARGS+=("$1"); shift
        done
        ;;
      --)
        [[ "$mode" == run ]] || die "runner watch: unexpected -- (watch ends at end of arguments)"
        shift; AIRLINE_RUNNER_COMMAND=("$@"); break ;;
      --merge-stderr) die "runner $mode: --merge-stderr must immediately follow --filter <name>" ;;
      *) die "runner $mode: unknown option '$1'" ;;
    esac
  done

  if [[ "$mode" == run ]]; then
    [[ ${#AIRLINE_RUNNER_COMMAND[@]} -gt 0 ]] || die "runner run: need -- <command>"
    [[ -n "$AIRLINE_RUNNER_CLASSIFIER" ]] || AIRLINE_RUNNER_CLASSIFIER=basic
  else
    [[ -n "$AIRLINE_RUNNER_PROBE" ]] || die "runner watch: need --probe <name> [<arg>...]"
  fi
}

_runner_validate_spec () {   # <session> <run|watch>
  local session="$1" mode="$2" file
  if [[ "$mode" == run ]]; then
    file="$(_runner_element_file "$session" classify "$AIRLINE_RUNNER_CLASSIFIER")" || \
      die "runner run: classifier '$AIRLINE_RUNNER_CLASSIFIER' not found"
    runner_classifier_valid "$file" || die "runner run: classifier '$AIRLINE_RUNNER_CLASSIFIER' is invalid"
    if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
      file="$(_runner_element_file "$session" filter "$AIRLINE_RUNNER_FILTER")" || \
        die "runner run: filter '$AIRLINE_RUNNER_FILTER' not found"
      runner_filter_valid "$file" || die "runner run: filter '$AIRLINE_RUNNER_FILTER' is invalid"
    fi
  fi
  if [[ -n "$AIRLINE_RUNNER_PROBE" ]]; then
    file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")" || \
      die "runner $mode: probe '$AIRLINE_RUNNER_PROBE' not found"
    runner_probe_valid "$file" || die "runner $mode: probe '$AIRLINE_RUNNER_PROBE' is invalid"
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
    AIRLINE_RUNNER_SPEC_ARGV+=(--probe "$AIRLINE_RUNNER_PROBE" "${AIRLINE_RUNNER_PROBE_ARGS[@]}")
  fi
  [[ "$mode" == run ]] && AIRLINE_RUNNER_SPEC_ARGV+=(-- "${AIRLINE_RUNNER_COMMAND[@]}")
}

# Run one command in the calling pane. The process is started as a child so airline
# can observe it; explicit stdin inheritance preserves current-pane interaction and
# stdout/stderr remain visible in the pane. A filter gets a tee'd copy of its declared
# stream; a probe performs sequential periodic observations without overlapping.
_runner_execute () {   # <session> <retain:0|1>; uses parsed run specification
  local session="$1" retain="$2" file pane win key filter_key probe_key
  local load_problem classify_problem filter_problem probe_problem streams=""
  local child_pid filter_pid="" probe_pid="" rc=0 signal="" condition

  pane="$(current_pane)"
  win="$(resolve_window "$pane")"
  key="runner-${pane#%}"
  filter_key="$key-filter"
  probe_key="$key-probe"
  load_problem="$(_runner_problem_key "$AIRLINE_RUNNER_CLASSIFIER" load)"
  classify_problem="$(_runner_problem_key "$AIRLINE_RUNNER_CLASSIFIER" classify)"
  filter_problem="$(_runner_problem_key "$AIRLINE_RUNNER_FILTER" filter)"
  probe_problem="$(_runner_problem_key "$AIRLINE_RUNNER_PROBE" probe)"
  [[ "$retain" == 1 ]] && runner_retain_pane "$pane"

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
  _runner_problem "$session" "$load_problem" ok ""

  _signal_set health _condition_level_valid ok "$key" ok -t "$win"
  _signal_set health _condition_level_valid ok "$filter_key" ok -t "$win"
  _signal_set health _condition_level_valid ok "$probe_key" ok -t "$win"
  _signal_set status _status_level_valid "" "$key" active -t "$win"

  if [[ -n "$AIRLINE_RUNNER_FILTER" ]]; then
    streams=stdout
    if ! runner_stream_prepare "$streams"; then
      runner_stream_cleanup
      _runner_problem "$session" "$filter_problem" fail "runner filter '$AIRLINE_RUNNER_FILTER' could not prepare"
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
  AIRLINE_RUNNER_WINDOW="$win"
  AIRLINE_RUNNER_FILTER_KEY="$filter_key"
  AIRLINE_RUNNER_FILTER_PROBLEM="$filter_problem"
  AIRLINE_RUNNER_FILTER_LAST=""
  AIRLINE_RUNNER_PROBE_KEY="$probe_key"
  AIRLINE_RUNNER_PROBE_PROBLEM="$probe_problem"
  AIRLINE_RUNNER_PROBE_LAST=""
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
    _runner_problem "$session" "$filter_problem" fail "runner filter '$AIRLINE_RUNNER_FILTER' failed"
  fi
  if [[ -n "$streams" ]]; then
    runner_stream_cleanup
    trap - EXIT
  fi
  _signal_set health _condition_level_valid ok "$filter_key" ok -t "$win"
  _signal_set health _condition_level_valid ok "$probe_key" ok -t "$win"
  (( rc > 128 )) && signal="$((rc - 128))"

  if condition="$(runner_classifier_run "$rc" "$signal")"; then
    _runner_problem "$session" "$classify_problem" ok ""
  else
    condition=fail
    _runner_problem "$session" "$classify_problem" fail \
      "runner classifier '$AIRLINE_RUNNER_CLASSIFIER' failed or emitted an invalid condition"
  fi
  _runner_finish "$condition" "$win" "$key"
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
      if [[ "$mode" == run ]]; then _runner_execute "$session" 0
      else _runner_watch_execute "$session" 0; fi
      ;;
    pane|window)
      pane="$(current_pane)"; cwd="$(current_path)"
      if [[ "$AIRLINE_RUNNER_PLACEMENT" == pane ]]; then
        spawned="$(runner_open_pane "$pane" "$cwd" env \
          "AIRLINE_DIR=$AIRLINE_DIR" "AIRLINE_TMUX=${AIRLINE_TMUX:-tmux}" \
          "$AIRLINE_DIR/airline" "_$mode" "${AIRLINE_RUNNER_SPEC_ARGV[@]}")"
      else
        spawned="$(runner_open_window "$session" "$cwd" env \
          "AIRLINE_DIR=$AIRLINE_DIR" "AIRLINE_TMUX=${AIRLINE_TMUX:-tmux}" \
          "$AIRLINE_DIR/airline" "_$mode" "${AIRLINE_RUNNER_SPEC_ARGV[@]}")"
      fi
      # Arm retention from both sides of the spawn boundary. The child does it
      # before validation; the parent closes the scheduler race before a very
      # short-lived child can be reaped under load.
      runner_retain_pane "$spawned"
      printf '%s\n' "$spawned"
      ;;
  esac
}

# Watch external state without manufacturing a placeholder command.
_runner_watch_execute () {   # <session> <retain:0|1>; uses parsed watch specification
  local session="$1" retain="$2" file pane win key probe_key probe_problem
  local interval watch_pid="$BASHPID" watch_rc=0 sleep_pid=""

  pane="$(current_pane)"
  win="$(resolve_window "$pane")"
  key="runner-${pane#%}-watch"
  probe_key="$key-probe"
  probe_problem="$(_runner_problem_key "$AIRLINE_RUNNER_PROBE" probe)"
  [[ "$retain" == 1 ]] && runner_retain_pane "$pane"

  file="$(_runner_element_file "$session" probe "$AIRLINE_RUNNER_PROBE")"
  runner_probe_load "$file" || return 2
  _runner_problem "$session" "$(_runner_problem_key "$AIRLINE_RUNNER_PROBE" load)" ok ""

  AIRLINE_RUNNER_SESSION="$session"
  AIRLINE_RUNNER_WINDOW="$win"
  AIRLINE_RUNNER_PROBE_KEY="$probe_key"
  AIRLINE_RUNNER_PROBE_PROBLEM="$probe_problem"
  AIRLINE_RUNNER_PROBE_LAST=""
  interval="${AIRLINE_RUNNER_PROBE_INTERVAL:-5}"

  _signal_set health _condition_level_valid ok "$probe_key" ok -t "$win"
  _signal_set status _status_level_valid "" "$key" active -t "$win"

  trap 'watch_rc=130; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' INT
  trap 'watch_rc=143; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' TERM
  trap 'watch_rc=129; [[ -n "$sleep_pid" ]] && kill "$sleep_pid" 2>/dev/null || true' HUP
  while (( watch_rc == 0 )); do
    if runner_probe_once "$watch_pid" "${AIRLINE_RUNNER_PROBE_ARGS[@]}"; then
      _runner_probe_report "$AIRLINE_RUNNER_PROBE_CONDITION"
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

  _signal_clear health "$probe_key" -t "$win"
  _signal_clear status "$key" -t "$win"
  return "$watch_rc"
}

# The active/suspended state. `suspend` mutes the palette (the derived flat look, via
# _palette_load) and traps the prefix so keys pass through — the nested-session signal
# "this tmux is dormant." `resume` restores. The flat/vibrant colour is derived, not a
# second palette. State is private; read it through `state show`, not the option.
_state_word () {   # <session>
  [[ "$(prv_get_session "$1" "$AIRLINE_KEY_SUSPENDED")" == 1 ]] && echo suspended || echo active
}

_state_set () {   # <session> <1=suspended|0=active>
  local session="$1" value="$2"
  prv_set_session "$session" "$AIRLINE_KEY_SUSPENDED" "$value"
  if [[ "$value" == 1 ]]; then
    opt_set_session "$session" prefix None
    opt_set_session "$session" key-table off
  else
    opt_unset_session "$session" prefix
    opt_unset_session "$session" key-table
  fi
  render "$session" || true
}

#-----------------------------------------------------------------------------#
# Transient (consume-on-view)
#-----------------------------------------------------------------------------#

_ensure_unfocus_hook () {
  opt_set_global focus-events on
  hook_set "pane-focus-out[90]" "run-shell -b \"$AIRLINE_DIR/airline _unfocus #{window_id}\""
}

# Drop one namespace's transient contributors and re-project its badge. The caller
# runs this inside that window collection's transaction.
_unfocus_namespace_unlocked () {   # <window> <status|health>
  local win="$1" ns="$2" changed="" key f1 f2
  for key in $(coll_members_window "$win" "$ns"); do
    IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$key")"
    [[ "$f2" == 1 ]] && { coll_unregister_window "$win" "$ns" "$key"; changed=1; }
  done
  [[ -n "$changed" ]] || return 1
  "${ns}_project" "$win"
}

# The internal `_unfocus` hook callback. Status and health use separate locks in a
# fixed order; each collection mutation and projection is one window transaction.
_unfocus () {
  local win="${1:-}" ns changed=""; [[ -n "$win" ]] || return 0
  win="$(resolve_window "$win")"
  for ns in status health; do
    with_window_transaction "$win" "$ns" _unfocus_namespace_unlocked "$win" "$ns" && changed=1
  done
  [[ -n "$changed" ]] && redraw
  return 0
}

#-----------------------------------------------------------------------------#
# Dynamic nouns — status & health (live: write + re-project a badge + redraw)
#-----------------------------------------------------------------------------#

_signal_set_unlocked () {   # <ns> <clear-value|""> <key> <value> <transient> <window>
  local ns="$1" clear_value="$2" key="$3" value="$4" transient="$5" win="$6"
  if [[ -n "$clear_value" && "$value" == "$clear_value" ]]; then
    coll_unregister_window "$win" "$ns" "$key"
  else
    coll_set_window "$win" "$ns" "$key" "$value" "$transient"
  fi
  "${ns}_project" "$win"
}

_signal_set () {   # <ns> <validator> <clear-value|""> <key> <value> [--transient] [-t <win>]
  local ns="$1" valid="$2" clear_value="$3"; shift 3
  local key="" value="" transient="" win="" ; local -a pos=()
  while (( $# )); do
    case "$1" in
      --transient) transient=1; shift ;;
      -t)
        [[ $# -ge 2 && -n "$2" ]] || die "$ns set: -t requires <window>"
        win="$2"
        shift 2
        ;;
      *)           pos+=("$1"); shift ;;
    esac
  done
  key="${pos[0]:-}"; value="${pos[1]:-}"
  [[ -n "$key" ]] || die "$ns set: need <key>"
  "$valid" "$value" || die "$ns set: invalid value '$value'"
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  with_window_transaction "$win" "$ns" _signal_set_unlocked \
    "$ns" "$clear_value" "$key" "$value" "$transient" "$win" && redraw
  [[ -n "$transient" ]] && _ensure_unfocus_hook
  return 0
}

_signal_clear_unlocked () {   # <ns> <key> <window>
  local ns="$1" key="$2" win="$3"
  coll_unregister_window "$win" "$ns" "$key"
  "${ns}_project" "$win"
}

_signal_clear () {   # <ns> <key> [-t <win>]
  local ns="$1"; shift
  local key="" win=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || die "$ns clear: -t requires <window>"
        win="$2"
        shift 2
        ;;
      *) key="$1"; shift ;;
    esac
  done
  [[ -n "$key" ]] || die "$ns clear: need <key>"
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  with_window_transaction "$win" "$ns" _signal_clear_unlocked "$ns" "$key" "$win" && redraw
  return 0
}

_signal_show_unlocked () {   # <ns> <window> [<key>]
  local ns="$1" win="$2" key="${3:-}" f1 f2 k
  if [[ -n "$key" ]]; then
    IFS=$'\t' read -r f1 _ <<< "$(coll_get_window "$win" "$ns" "$key")"
    printf '%s\n' "$f1"
    return 0
  fi
  for k in $(coll_members_window "$win" "$ns"); do
    IFS=$'\t' read -r f1 f2 <<< "$(coll_get_window "$win" "$ns" "$k")"
    _show_row "$k" "$f1${f2:+  (transient)}"
  done
}

_signal_show () {   # <ns> [<key>] [-t <win>]
  local ns="$1"; shift
  local key="" win=""
  while (( $# )); do
    case "$1" in
      -t)
        [[ $# -ge 2 && -n "$2" ]] || die "$ns show: -t requires <window>"
        win="$2"
        shift 2
        ;;
      *) key="$1"; shift ;;
    esac
  done
  [[ -n "$win" ]] || win="$(current_window)"
  win="$(resolve_window "$win")"
  with_window_transaction "$win" "$ns" _signal_show_unlocked "$ns" "$win" "$key"
}

#-----------------------------------------------------------------------------#
# Session problems — cooperating widgets report failures encountered by one
# session's configured components. Mutation requires that session as input and
# never infers or writes another session. A bare show is intentionally server-wide.
#-----------------------------------------------------------------------------#

_problem_session () {   # <verb> <session-target>
  local verb="$1" target="${2:-}" session
  [[ -n "$target" ]] || die "problem $verb: need <session>"
  session="$(resolve_session_target "$target")"
  [[ -n "$session" ]] || die "problem $verb: cannot resolve session '$target'"
  printf '%s' "$session"
}

_problem_set () {   # <session> <key> <level> [<message...>]
  local target="${1:-}" key="${2:-}" level="${3:-}" message session
  shift $(( $# < 3 ? $# : 3 ))
  message="$*"
  session="$(_problem_session set "$target")"
  [[ -n "$key" ]] || die "problem set: need <key>"
  [[ "$key" != *[[:space:]]* ]] || die "problem set: key must not contain whitespace"
  _condition_level_valid "$level" || die "problem set: invalid level '$level'"
  if [[ "$level" != ok ]]; then
    [[ -n "$message" ]] || die "problem set: need <message>"
    [[ "$message" != *$'\t'* ]] || die "problem set: message must not contain a tab"
  fi
  _problem_store "$session" "$key" "$level" "$message" && redraw
  return 0
}

_problem_clear () {   # <session> <key>
  local target="${1:-}" key="${2:-}" session
  (( $# <= 2 )) || die "problem clear: too many arguments"
  session="$(_problem_session clear "$target")"
  [[ -n "$key" ]] || die "problem clear: need <key>"
  _problem_store "$session" "$key" ok "" && redraw
  return 0
}

_problem_show_session_unlocked () {   # <session> [<key>] [<grouped=1>]
  local session="$1" key="${2:-}" grouped="${3:-}" tuple level message k members
  if [[ -n "$key" ]]; then
    coll_get_session "$session" problem "$key"
    return 0
  fi
  members="$(coll_members_session "$session" problem)"
  if [[ -n "$grouped" && -n "$members" ]]; then printf '%s:\n' "$session"; fi
  for k in $members; do
    tuple="$(coll_get_session "$session" problem "$k")"
    IFS=$'\t' read -r level message <<< "$tuple"
    _show_row "${grouped:+  }$k" "$level${message:+  $message}"
  done
}

_problem_show_session () {   # <session> [<key>] [<grouped=1>]
  with_session_transaction "$1" problem _problem_show_session_unlocked "$@"
}

_problem_show () {   # [<session> [<key>]]; bare = every session with problems
  local target="${1:-}" key="${2:-}" session
  (( $# <= 2 )) || die "problem show: too many arguments"
  if [[ -n "$target" ]]; then
    session="$(_problem_session show "$target")"
    _problem_show_session "$session" "$key"
    return 0
  fi
  for session in $(list_sessions); do
    _problem_show_session "$session" "" 1
  done
}

# Transaction diagnostics. tmux.sh owns marker discovery, liveness checks, and
# recovery; the API owns only command validation and user-facing errors.
_lock_show () {
  (( $# == 0 )) || die "lock show: takes no arguments"
  transaction_list
}

_lock_clear () {   # <session|window> <target> <namespace>
  local scope="${1:-}" target="${2:-}" namespace="${3:-}" rc=0
  (( $# == 3 )) || die "lock clear: need <session|window> <target> <namespace>"
  transaction_clear "$scope" "$target" "$namespace" || rc=$?
  case "$rc" in
    0) ;;
    2) die "lock clear: invalid scope, target, namespace, or marker" ;;
    3) die "lock clear: no such outstanding transaction" ;;
    4) die "lock clear: transaction owner is still active" ;;
    *) die "lock clear: recovery failed" ;;
  esac
}

#-----------------------------------------------------------------------------#
# Static config nouns — palette & segment (public @airline-* options, read-only here)
#-----------------------------------------------------------------------------#
# Global defaults are written the idiomatic tmux way (`set -g @airline-…` in
# `.tmux.conf`); palette/layout runtime operations write session overrides. The CLI
# only *reads* individual values back for discovery. `apply` bakes the effective value.

# <key-prefix> is the bare-key prefix WITHIN the public namespace: "" for palette
# (the key is the element) or "segment-" for segments. pub_* applies the @airline-
# prefix; api never spells it.
_static_show () {   # <session> <key-prefix> <validator> <list-array-name> [<X>]
  local session="$1" keypfx="$2" valid="$3" listname="$4" x="${5:-}"
  if [[ -n "$x" ]]; then
    "$valid" "$x" || die "show: unknown target '$x'"
    pub_get_session "$session" "${keypfx}${x}"
    return 0
  fi
  local -n all="$listname"; local k
  for k in "${all[@]}"; do
    _show_row "$k" "$(pub_get_session "$session" "${keypfx}${k}")"
  done
}

# palette show: bare → the whole palette (its `name` field + every element, labeled —
# a human summary, don't parse it); `show name` → the active palette name, raw (the
# scripting read, replaces the old `current`); `show <element>` → one element, raw.
# `name` is a VIRTUAL field: it lives in the private selection, not a public option.
_palette_show () {   # <session> [name|<element>]
  local session="$1" x="${2:-}"
  [[ "$x" == name ]] && { prv_get_session "$session" palette; return 0; }
  [[ -z "$x" ]] && _show_row name "$(prv_get_session "$session" palette)"
  _static_show "$session" "" _palette_element_valid AIRLINE_PALETTE_ELEMENTS "$x"
}

# adapter show: iterate the active set — the adapters currently applied (recorded by
# every `use`/`load`), one per line. Bare-only, unlike palette/status: an adapter is a
# valueless name, so there is no per-member `show <x>` value to return. This is the
# MULTI-active noun — its "what's on" answer is a LIST, not a scalar `name`. (What you
# *could* apply is a different axis — `adapter available`, over the search path.)
_adapter_show () {   # <session>
  local session="$1" a
  for a in $(coll_members_session "$session" adapters); do printf '%s\n' "$a"; done
}

#-----------------------------------------------------------------------------#
# Public API — one entry point per CLI command
#-----------------------------------------------------------------------------#
# These are the only behaviour functions `airline` dispatches to. Session-owned
# commands ask tmux for the current session once, then pass its id explicitly through
# the private implementation. `_init-session` is the lifecycle-hook exception: tmux
# supplies an event target, which resolve_session normalizes before use.

api_init () { _init "$(_require_current_session)"; }
api_init_session () {   # <tmux-target>; internal lifecycle hook entry
  local session
  [[ -n "${1:-}" ]] || die "_init-session: need <target>"
  session="$(resolve_session "$1")"
  [[ -n "$session" ]] || die "cannot resolve target session: $1"
  _init "$session"
}
api_apply () { _apply "$(_require_current_session)"; }
api_show () { _show_config "$(_require_current_session)"; }

api_state_suspend () { _state_set "$(_require_current_session)" 1; }
api_state_resume () { _state_set "$(_require_current_session)" 0; }
api_state_toggle () {
  local session
  session="$(_require_current_session)"
  if [[ "$(_state_word "$session")" == suspended ]]; then
    _state_set "$session" 0
  else
    _state_set "$session" 1
  fi
}
api_state_show () { _state_word "$(_require_current_session)"; }

api_status_set () { _signal_set status _status_level_valid "" "$@"; }
api_status_clear () { _signal_clear status "$@"; }
api_status_show () { _signal_show status "$@"; }
api_health_set () { _signal_set health _condition_level_valid ok "$@"; }
api_health_clear () { _signal_clear health "$@"; }
api_health_show () { _signal_show health "$@"; }
api_problem_set () { _problem_set "$@"; }
api_problem_clear () { _problem_clear "$@"; }
api_problem_show () { _problem_show "$@"; }
api_lock_show () { _lock_show "$@"; }
api_lock_clear () { _lock_clear "$@"; }

api_palette_show () { local s; s="$(_require_current_session)"; _palette_show "$s" "$@"; }
api_palette_use () {
  local s; s="$(_require_current_session)"
  _load_config "$s" palette "$@"
  _apply "$s"
}
api_palette_available () { local s; s="$(_require_current_session)"; _path_available "$s" palette; }
api_palette_register () { local s; s="$(_require_current_session)"; _register "$s" palette "$@"; }

api_segment_show () {
  local s; s="$(_require_current_session)"
  _static_show "$s" "segment-" _segment_slot_valid AIRLINE_SEGMENT_SLOTS "$@"
}

api_adapter_use () {
  local s; s="$(_require_current_session)"
  _apply_adapter "$s" "$@"
  _render "$s"
}
api_adapter_load () {
  local s; s="$(_require_current_session)"
  _load_adapter "$s" "$@"
  _render "$s"
}
api_adapter_show () { _adapter_show "$(_require_current_session)"; }
api_adapter_available () { local s; s="$(_require_current_session)"; _path_available "$s" adapter; }
api_adapter_register () { local s; s="$(_require_current_session)"; _register "$s" adapter "$@"; }

api_layout_use () {
  local s; s="$(_require_current_session)"
  _layout_use "$s" "$@"
  render "$s" || true
}
api_layout_load () {
  local s; s="$(_require_current_session)"
  _layout_load "$s" "$@"
  render "$s" || true
}
api_layout_show () { local s; s="$(_require_current_session)"; _layout_show "$s" "$@"; }
api_layout_available () { local s; s="$(_require_current_session)"; _path_available "$s" layout; }
api_layout_register () { local s; s="$(_require_current_session)"; _register "$s" layout "$@"; }

api_classifier_show () { local s; s="$(_require_current_session)"; _runner_element_show "$s" classifier "$@"; }
api_classifier_available () { local s; s="$(_require_current_session)"; _path_available "$s" classifier; }
api_classifier_register () { local s; s="$(_require_current_session)"; _register "$s" classifier "$@"; }
api_filter_show () { local s; s="$(_require_current_session)"; _runner_element_show "$s" filter "$@"; }
api_filter_available () { local s; s="$(_require_current_session)"; _path_available "$s" filter; }
api_filter_register () { local s; s="$(_require_current_session)"; _register "$s" filter "$@"; }
api_probe_show () { local s; s="$(_require_current_session)"; _runner_element_show "$s" probe "$@"; }
api_probe_available () { local s; s="$(_require_current_session)"; _path_available "$s" probe; }
api_probe_register () { local s; s="$(_require_current_session)"; _register "$s" probe "$@"; }

api_runner_show () { local s; s="$(_require_current_session)"; _runner_definition_show "$s" "$@"; }
api_runner_available () { local s; s="$(_require_current_session)"; _path_available "$s" runner; }
api_runner_register () { local s; s="$(_require_current_session)"; _register "$s" runner "$@"; }
api_runner_run () { local s; s="$(_require_current_session)"; _runner_invoke "$s" run "$@"; }
api_runner_watch () { local s; s="$(_require_current_session)"; _runner_invoke "$s" watch "$@"; }

api_runner_exec () {   # <normalized-run-spec...>; internal spawned-pane entry
  local s
  s="$(_require_current_session)"
  runner_retain_pane "$(current_pane)"
  _runner_parse run "$@"
  _runner_validate_spec "$s" run
  _runner_execute "$s" 0
}

api_runner_watch_exec () {   # <normalized-watch-spec...>; internal spawned-pane entry
  local s
  s="$(_require_current_session)"
  runner_retain_pane "$(current_pane)"
  _runner_parse watch "$@"
  _runner_validate_spec "$s" watch
  _runner_watch_execute "$s" 0
}

api_unfocus () { _unfocus "$@"; }

# vim: ft=bash

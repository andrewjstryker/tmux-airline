#!/usr/bin/env bash
#
# airline.sh — the tmux-airline CLI: argument parsing, command grammar, dispatch,
# and help, all in one file. Read this to know the entire command surface.
#
# It locates the install, points the mechanical layer at the right tmux server,
# sources the internal behaviour stack under lib/, then parses argv and delegates
# each command once. The CLI is the public API; lib/ contains its implementation.
#
# Grammar: a few top-level verbs (init/apply/show/…) plus config, signal, diagnostic,
# lifecycle, and runner nouns, each with its own verb set. Every noun's verbs live in
# a cmd_<noun> dispatcher below; help is generated from the `#| …` markers on the
# case arms, so the grammar documents itself.

set -u

AIRLINE_DIR="${AIRLINE_DIR:-$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )}"

# Test/advanced seam: target a specific tmux server. AIRLINE_TMUX may carry args
# (e.g. "tmux -L mysock"); the word-splitting is intentional. tmux.sh's calls are
# late-bound, so defining this before sourcing is enough.
if [[ -n "${AIRLINE_TMUX:-}" ]]; then
  # shellcheck disable=SC2086
  tmux () { command ${AIRLINE_TMUX} "$@"; }
fi

# shellcheck source=lib/tmux.sh
source "$AIRLINE_DIR/lib/tmux.sh"
# shellcheck source=lib/collections.sh
source "$AIRLINE_DIR/lib/collections.sh"
# shellcheck source=lib/render.sh
source "$AIRLINE_DIR/lib/render.sh"
# shellcheck source=lib/runner.sh
source "$AIRLINE_DIR/lib/runner.sh"
# shellcheck source=lib/layout.sh
source "$AIRLINE_DIR/lib/layout.sh"
# shellcheck source=lib/lifecycle.sh
source "$AIRLINE_DIR/lib/lifecycle.sh"

#-----------------------------------------------------------------------------#
# Help — generated from the `#| …` markers on the case arms below, so the grammar
# is the single source of truth (no separate help text to keep in sync). Like `show`,
# it lists the top-level commands then recurses into each noun's dispatcher.
#-----------------------------------------------------------------------------#

# Print a source range's #|-annotated arms as "  verb   help". <file> <start> <end>.
_help_arms () {
  sed -n "/$2/,/$3/{ s/^[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_-]*\))[^#]*#|[[:space:]]*\(.*\)/\1\t\2/p; }" "$1" \
    | while IFS=$'\t' read -r v d; do printf '  %-9s %s\n' "$v" "$d"; done
}

# One noun's verbs — the recursion target (also `<noun> help`). The dispatchers live in
# THIS file, so that's where the arms are read from.
_help_noun () {   # <noun>
  printf '%s:\n' "$1"
  _help_arms "$AIRLINE_DIR/airline.sh" "^cmd_$1 () {" '^}'
}

usage () {
  printf 'airline — tmux-airline CLI\n\n'
  printf 'Commands:\n'
  _help_arms "$AIRLINE_DIR/airline.sh" '^case ' '^esac'
  local n
  for n in palette segment adapter layout classifier filter probe runner state status health problem lock; do
    printf '\n'; _help_noun "$n"
  done
  printf '\n  use loads a bare name from a registered dir; register blesses a location.\n'
  printf '  --transient clears a signal when you focus away from its window.\n'
}

#-----------------------------------------------------------------------------#
# Noun dispatchers — each parses its verb and makes exactly one delegated call.
# The `#| …` markers on the arms are the help source.
#-----------------------------------------------------------------------------#

cmd_state () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    suspend) lifecycle_state_suspend ;;   #| mute the palette + trap the prefix (session dormant)
    resume)  lifecycle_state_resume ;;    #| restore vibrant colours + release the prefix
    toggle)  lifecycle_state_toggle ;;    #| flip active/suspended
    show)    lifecycle_state_show ;;      #| print the current state (active | suspended)
    ""|-h|--help|help) _help_noun state ;;
    *) die "unknown state command: $verb" ;;
  esac
}

cmd_status () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   lifecycle_status_set "$@" ;;   #| <key> <active|result|attention> [--transient] [-t <win>]
    clear) lifecycle_status_clear "$@" ;; #| <key> [-t <win>]
    show)  lifecycle_status_show "$@" ;;  #| [<key>] [-t <win>] — a window's app-status
    ""|-h|--help|help) _help_noun status ;;
    *) die "unknown status command: $verb" ;;
  esac
}

cmd_health () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   lifecycle_health_set "$@" ;;   #| <key> <ok|warn|fail> [--transient] [-t <win>]
    clear) lifecycle_health_clear "$@" ;; #| <key> [-t <win>]
    show)  lifecycle_health_show "$@" ;;  #| [<key>] [-t <win>] — a window's health
    ""|-h|--help|help) _help_noun health ;;
    *) die "unknown health command: $verb" ;;
  esac
}

cmd_problem () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   lifecycle_problem_set "$@" ;;   #| <session> <key> <ok|warn|fail> [<message>]
    clear) lifecycle_problem_clear "$@" ;; #| <session> <key>
    show)  lifecycle_problem_show "$@" ;;  #| [<session> [<key>]] — all sessions, one session, or one problem
    ""|-h|--help|help) _help_noun problem ;;
    *) die "unknown problem command: $verb" ;;
  esac
}

cmd_lock () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)  lifecycle_lock_show "$@" ;;  #| list outstanding transactions and whether their owner is active or stale
    clear) lifecycle_lock_clear "$@" ;; #| <session|window> <target> <namespace> — release one stale lock
    ""|-h|--help|help) _help_noun lock ;;
    *) die "unknown lock command: $verb" ;;
  esac
}

cmd_palette () {
  # A palette element is a public option (@airline-<element>). `set -g` supplies a
  # user default; `use` installs a session override for the whole set. Like segment,
  # the per-element CLI path is read-only — `show` is the discovery surface (bare for humans,
  # `show <field>` a raw value for scripts; `show name` is the active-palette read).
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      layout_palette_show "$@" ;;      #| [name|<element>] — summary, or one field raw (`show name` for scripts)
    use)       layout_palette_use "$@" ;;       #| <name> — load a palette (re-applies the layout)
    available) layout_palette_available ;;      #| the palettes you can `use` (on the path)
    register)  layout_palette_register "$@" ;; #| <dir> — add a palette search dir
    ""|-h|--help|help) _help_noun palette ;;
    *) die "unknown palette command: $verb" ;;
  esac
}

cmd_segment () {
  # A segment is a public option. Users provide defaults with `set -g`; layouts write
  # explicit session overrides. This noun is read-only — `show` is the discovery
  # surface (bare `show` lists every slot).
  local verb="${1:-}"; shift || true
  case "$verb" in
    show) layout_segment_show "$@" ;;   #| [<slot>] — read one or all
    ""|-h|--help|help) _help_noun segment ;;
    *) die "unknown segment command: $verb" ;;
  esac
}

cmd_adapter () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    use)       layout_adapter_use "$@" ;;       #| <name> — apply the palette to a plugin
    load)      layout_adapter_load "$@" ;;      #| <path> — apply a one-off adapter script
    show)      layout_adapter_show ;;           #| the applied adapters, one per line
    available) layout_adapter_available ;;      #| the adapters you can `use` (on the path)
    register)  layout_adapter_register "$@" ;; #| <dir> — add an adapter search dir
    ""|-h|--help|help) _help_noun adapter ;;
    *) die "unknown adapter command: $verb" ;;
  esac
}

cmd_layout () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    use)       layout_use "$@" ;;       #| <name> — run a composition (adapters + segments)
    load)      layout_load "$@" ;;      #| <path> — run a one-off layout script (records it)
    show)      layout_show "$@" ;;      #| [name|path] — the active layout (summary, or one field raw)
    available) layout_available ;;      #| the layouts you can `use` (on the path)
    register)  layout_register "$@" ;; #| <dir> — add a layout search dir
    ""|-h|--help|help) _help_noun layout ;;
    *) die "unknown layout command: $verb" ;;
  esac
}

cmd_classifier () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      runner_classifier_show "$@" ;;      #| <name> — summary, contract, and resolved path
    available) runner_classifier_available ;;      #| the classifiers available to runner run
    register)  runner_classifier_register "$@" ;; #| <dir> — add a classifier search dir
    ""|-h|--help|help) _help_noun classifier ;;
    *) die "unknown classifier command: $verb" ;;
  esac
}

cmd_filter () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      runner_filter_show "$@" ;;      #| <name> — summary, contract, and resolved path
    available) runner_filter_available ;;      #| the filters available to runner run
    register)  runner_filter_register "$@" ;; #| <dir> — add a filter search dir
    ""|-h|--help|help) _help_noun filter ;;
    *) die "unknown filter command: $verb" ;;
  esac
}

cmd_probe () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      runner_probe_show "$@" ;;      #| <name> — summary, arguments, interval, and resolved path
    available) runner_probe_available ;;      #| the probes available to runner run/watch
    register)  runner_probe_register "$@" ;; #| <dir> — add a probe search dir
    ""|-h|--help|help) _help_noun probe ;;
    *) die "unknown probe command: $verb" ;;
  esac
}

cmd_runner () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      runner_show "$@" ;;       #| <name> [<arg>...] — one named composition with resolved defaults
    available) runner_available ;;       #| the named runner compositions on the path
    register)  runner_register "$@" ;;  #| <dir> — add a runner-composition search dir
    run)       runner_run "$@" ;;        #| [--here|--pane|--window] [<runner>] [composition] -- <command>...
    watch)     runner_watch "$@" ;;      #| [--here|--pane|--window] [<runner>] [composition] — probe until interrupted
    ""|-h|--help|help) _help_noun runner ;;
    *) die "unknown runner command: $verb" ;;
  esac
}

#-----------------------------------------------------------------------------#
# Dispatch — top-level verbs. Config/dynamic nouns delegate to their cmd_<noun>
# parser above; the rest delegate directly to their implementation function.
# Keeping dispatch in main makes the grammar behavior-testable without starting tmux.
#-----------------------------------------------------------------------------#
main () {
  local cmd="${1:-}"; shift || true
case "$cmd" in
    init)     lifecycle_init    "$@" ;;   #| seed defaults, register search paths, publish the CLI handle; then render
    apply)    lifecycle_apply   "$@" ;;   #| re-apply the layout and render from the source of truth
    show)     lifecycle_show    "$@" ;;   #| print the active configuration
    state)    cmd_state   "$@" ;;
    status)   cmd_status  "$@" ;;
    health)   cmd_health  "$@" ;;
    problem)  cmd_problem "$@" ;;
    lock)     cmd_lock    "$@" ;;
    palette)  cmd_palette "$@" ;;
    segment)  cmd_segment "$@" ;;
    adapter)  cmd_adapter "$@" ;;
    layout)   cmd_layout  "$@" ;;
    classifier) cmd_classifier "$@" ;;
    filter)     cmd_filter "$@" ;;
    probe)      cmd_probe "$@" ;;
    runner)   cmd_runner  "$@" ;;
    _init-session) lifecycle_init_session "$@" ;; # internal: after-new-session hook callback
    _unfocus) lifecycle_unfocus "$@" ;;           # internal: pane-focus-out hook callback
    _run)     runner_exec "$@" ;;        # internal: spawned-pane runner callback
    _watch)   runner_watch_exec "$@" ;;  # internal: spawned-pane watcher callback
    ""|-h|--help|help) usage ;;
    *) die "unknown command: $cmd (try: airline help)" ;;
esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi

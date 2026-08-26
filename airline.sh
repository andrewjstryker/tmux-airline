#!/usr/bin/env bash
#
# airline.sh — the tmux-airline CLI: argument parsing, command grammar, and
# dispatch. Read this together with rendered help to know the command surface.
#
# It locates the install, points the mechanical layer at the right tmux server,
# sources the internal behaviour stack under lib/, then parses argv and delegates
# each command once. The CLI is the public API; lib/ contains its implementation.
#
# Grammar: public commands follow a noun-verb pattern, apart from help. Two internal
# runner continuations remain top-level entry points pending runner simplification.
# Every noun's verbs live in a cmd_<noun> dispatcher below; help is generated from
# the `#| …` markers on the case arms, so the grammar documents itself.

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

AIRLINE_HELP_GROUP_NAMES=(Session Signals Diagnostics Layout Runner)
AIRLINE_HELP_GROUP_NOUNS=(
  'session'
  'signal status health problem'
  'lock'
  'palette segment adapter layout'
  'classifier filter probe runner'
)
AIRLINE_NOUNS="${AIRLINE_HELP_GROUP_NOUNS[*]}"
AIRLINE_HELP_SOURCE="$AIRLINE_DIR/airline.sh"
# shellcheck source=lib/help.sh
source "$AIRLINE_DIR/lib/help.sh"

#-----------------------------------------------------------------------------#
# Noun dispatchers — each parses its verb and makes exactly one delegated call.
# The `#| …` markers on the arms are the help source.
#-----------------------------------------------------------------------------#

cmd_session () {
  local verb="${1:-}"; shift || true
  # help:begin session
  case "$verb" in
    init)  lifecycle_init  "$@" ;; #| [-t <session>] — seed defaults, register paths, publish the CLI handle, and render
    apply) lifecycle_apply "$@" ;; #| — commit global option edits and render the session
    show)  lifecycle_show  "$@" ;; #| [state] — print the active configuration or raw session state
    suspend) lifecycle_session_suspend ;; #| — mute the palette + trap the prefix (session dormant)
    resume)  lifecycle_session_resume ;;  #| — restore vibrant colours + release the prefix
    toggle)  lifecycle_session_toggle ;;  #| — flip active/suspended
    *) die "unknown session command: $verb" ;;
  esac
  # help:end session
}

cmd_signal () {
  local verb="${1:-}"; shift || true
  # help:begin signal
  case "$verb" in
    clear-transient) lifecycle_signal_clear_transient "$@" ;; #| [-t <window>] — consume transient status and health for a window
    *) die "unknown signal command: $verb" ;;
  esac
  # help:end signal
}

cmd_status () {
  local verb="${1:-}"; shift || true
  # help:begin status
  case "$verb" in
    set)   lifecycle_status_set "$@" ;;   #| <status-key> <active|result|attention> [--transient] [-t <window>] — set app status
    clear) lifecycle_status_clear "$@" ;; #| <status-key> [-t <window>] — clear app status
    show)  lifecycle_status_show "$@" ;;  #| [<status-key>] [-t <window>] — show a window's app status
    *) die "unknown status command: $verb" ;;
  esac
  # help:end status
}

cmd_health () {
  local verb="${1:-}"; shift || true
  # help:begin health
  case "$verb" in
    set)   lifecycle_health_set "$@" ;;   #| <health-key> <ok|warn|fail> [--transient] [-t <window>] — set window health
    clear) lifecycle_health_clear "$@" ;; #| <health-key> [-t <window>] — clear window health
    show)  lifecycle_health_show "$@" ;;  #| [<health-key>] [-t <window>] — show a window's health
    *) die "unknown health command: $verb" ;;
  esac
  # help:end health
}

cmd_problem () {
  local verb="${1:-}"; shift || true
  # help:begin problem
  case "$verb" in
    set)   lifecycle_problem_set "$@" ;;   #| <session> <problem-key> <ok|warn|fail> [<message>] — set or recover a session problem
    clear) lifecycle_problem_clear "$@" ;; #| <session> <problem-key> — clear a session problem
    show)  lifecycle_problem_show "$@" ;;  #| [<session> [<problem-key>]] — show all sessions, one session, or one problem
    *) die "unknown problem command: $verb" ;;
  esac
  # help:end problem
}

cmd_lock () {
  local verb="${1:-}"; shift || true
  # help:begin lock
  case "$verb" in
    show)  lifecycle_lock_show "$@" ;;  #| — list outstanding transactions and owner state
    clear) lifecycle_lock_clear "$@" ;; #| <session|window> <target> <namespace> — release one stale lock
    *) die "unknown lock command: $verb" ;;
  esac
  # help:end lock
}

cmd_palette () {
  # A palette element is a public option (@airline-<element>). `set -g` supplies a
  # user input; `use` installs a private session snapshot for the whole set. Like segment,
  # the per-element CLI path is read-only — `show` is the discovery surface (bare for humans,
  # `show <field>` a raw value for scripts; `show name` is the active-palette read).
  local verb="${1:-}"; shift || true
  # help:begin palette
  case "$verb" in
    show)      layout_palette_show "$@" ;;      #| [name|<palette-element>] — show the palette summary or one raw field
    use)       layout_palette_use "$@" ;;       #| <palette> — load a complete palette and repaint adapters
    list)      layout_palette_list ;;           #| — list palettes on the search path
    register)  layout_palette_register "$@" ;; #| <dir> — add a palette search directory
    *) die "unknown palette command: $verb" ;;
  esac
  # help:end palette
}

cmd_segment () {
  # Users stage segment changes with `set -g`; validated layouts declare them through
  # their function contract. This noun is read-only — `show` reads the private snapshot.
  local verb="${1:-}"; shift || true
  # help:begin segment
  case "$verb" in
    show) layout_segment_show "$@" ;;   #| [<segment>] — show one segment or all segments
    *) die "unknown segment command: $verb" ;;
  esac
  # help:end segment
}

cmd_adapter () {
  local verb="${1:-}"; shift || true
  # help:begin adapter
  case "$verb" in
    use)       layout_adapter_use "$@" ;;       #| <adapter>... — apply palette roles to one or more plugins
    load)      layout_adapter_load "$@" ;;      #| <file> — apply a one-off adapter script
    show)      layout_adapter_show ;;           #| — list applied adapters
    list)      layout_adapter_list ;;           #| — list adapters on the search path
    register)  layout_adapter_register "$@" ;; #| <dir> — add an adapter search directory
    *) die "unknown adapter command: $verb" ;;
  esac
  # help:end adapter
}

cmd_layout () {
  local verb="${1:-}"; shift || true
  # help:begin layout
  case "$verb" in
    use)       layout_use "$@" ;;       #| <layout> — apply a named layout definition
    load)      layout_load "$@" ;;      #| <file> — apply and record a one-off layout definition
    show)      layout_show "$@" ;;      #| [name|path] — show active layout provenance
    list)      layout_list ;;           #| — list layouts on the search path
    register)  layout_register "$@" ;; #| <dir> — add a layout search directory
    *) die "unknown layout command: $verb" ;;
  esac
  # help:end layout
}

cmd_classifier () {
  local verb="${1:-}"; shift || true
  # help:begin classifier
  case "$verb" in
    show)      runner_classifier_show "$@" ;;      #| <classifier> — show summary, contract, and resolved path
    list)      runner_classifier_list ;;           #| — list classifiers available to runners
    register)  runner_classifier_register "$@" ;; #| <dir> — add a classifier search directory
    *) die "unknown classifier command: $verb" ;;
  esac
  # help:end classifier
}

cmd_filter () {
  local verb="${1:-}"; shift || true
  # help:begin filter
  case "$verb" in
    show)      runner_filter_show "$@" ;;      #| <filter> — show summary, contract, and resolved path
    list)      runner_filter_list ;;           #| — list filters available to runners
    register)  runner_filter_register "$@" ;; #| <dir> — add a filter search directory
    *) die "unknown filter command: $verb" ;;
  esac
  # help:end filter
}

cmd_probe () {
  local verb="${1:-}"; shift || true
  # help:begin probe
  case "$verb" in
    show)      runner_probe_show "$@" ;;      #| <probe> — show summary, arguments, interval, and resolved path
    list)      runner_probe_list ;;           #| — list probes available to runners
    register)  runner_probe_register "$@" ;; #| <dir> — add a probe search directory
    *) die "unknown probe command: $verb" ;;
  esac
  # help:end probe
}

cmd_runner () {
  local verb="${1:-}"; shift || true
  # help:begin runner
  case "$verb" in
    show)      runner_show "$@" ;;       #| <runner> [<arg>...] — show one named composition with resolved defaults
    list)      runner_list ;;            #| — list named runner compositions
    register)  runner_register "$@" ;;  #| <dir> — add a runner search directory
    run)       runner_run "$@" ;;        #| [--here|--pane [-h|-v]|--window] [<runner>] [--classify <classifier>] [--filter <filter> [--merge-stderr]] [--probe <probe> [<arg>...]] -- <command>... — run a command with monitoring
    watch)     runner_watch "$@" ;;      #| [--here|--pane [-h|-v]|--window] [<runner>] [--probe <probe> [<arg>...]] — watch probe state until interrupted
    *) die "unknown runner command: $verb" ;;
  esac
  # help:end runner
}

#-----------------------------------------------------------------------------#
# Dispatch — public nouns delegate to their cmd_<noun> parser above. Help and
# internal runner continuations are the only top-level exceptions.
# Keeping dispatch in main makes the grammar behavior-testable without starting tmux.
#-----------------------------------------------------------------------------#
main () {
  local cmd="${1:-}"; shift || true
  # help:begin root
  case "$cmd" in
    session)  cmd_session "$@" ;;
    signal)   cmd_signal  "$@" ;;
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
    _run)     runner_exec "$@" ;;        # internal: spawned-pane runner callback
    _watch)   runner_watch_exec "$@" ;;  # internal: spawned-pane watcher callback
    help)     help_command "$@" ;;      #| [<noun> [<verb>]] — show command help
    ""|-h|--help) help_command ;;
    *) die "unknown command: $cmd (try: airline help)" ;;
  esac
  # help:end root
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi

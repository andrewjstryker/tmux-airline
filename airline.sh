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
# is the single source of truth (no separate help text to keep in sync). The rendered
# grammar is also the input to the completion generator.
#-----------------------------------------------------------------------------#

# Raw tab-delimited command + annotation records from one case block.
_help_records () {   # <file> <start-regex> <end-regex>
  sed -n "/$2/,/$3/{ s/^[[:space:]]*\([a-zA-Z_][a-zA-Z0-9_-]*\))[^#]*#|[[:space:]]*\(.*\)/\1\t\2/p; }" "$1"
}

_help_arms () {
  _help_records "$@" | while IFS=$'\t' read -r command annotation; do
    printf '  %-11s %s\n' "$command" "$annotation"
  done
}

_help_noun () {   # <noun>
  printf '%s:\n' "$1"
  _help_arms "$AIRLINE_DIR/airline.sh" "^cmd_$1 () {" '^}'
}

_help_annotation () {   # <noun-or-empty> <command>
  local noun="$1" wanted="$2" command annotation
  local start='^case ' end='^esac'
  [[ -z "$noun" ]] || start="^cmd_$noun () {"
  while IFS=$'\t' read -r command annotation; do
    [[ "$command" == "$wanted" ]] || continue
    printf '%s' "$annotation"
    return 0
  done < <(_help_records "$AIRLINE_DIR/airline.sh" "$start" "$end")
  return 1
}

AIRLINE_NOUNS='state status health problem lock palette segment adapter layout classifier filter probe runner'

_help_usage () {
  printf 'airline — tmux-airline CLI\n\n'
  printf 'Usage: airline <command> [<argument>...]\n\n'
  printf 'Commands:\n'
  _help_arms "$AIRLINE_DIR/airline.sh" '^case ' '^esac'
  local n
  for n in $AIRLINE_NOUNS; do
    printf '\n'; _help_noun "$n"
  done
  printf '\n  use loads a bare name from a registered dir; register blesses a location.\n'
  printf '  --transient clears a signal when you focus away from its window.\n'
}

_help_command () {   # [<top-command|noun> [<verb>]]
  local first="${1:-}" second="${2:-}" annotation usage description
  (( $# <= 2 )) || die "help: too many command levels"
  [[ -n "$first" ]] || { _help_usage; return; }

  case " $AIRLINE_NOUNS " in
    *" $first "*)
      if [[ -z "$second" ]]; then
        printf 'Usage: airline %s <command>\n\n' "$first"
        _help_noun "$first"
        return
      fi
      annotation="$(_help_annotation "$first" "$second")" || \
        die "help: unknown command '$first $second'"
      ;;
    *)
      [[ -z "$second" ]] || die "help: '$first' has no subcommands"
      annotation="$(_help_annotation "" "$first")" || die "help: unknown command '$first'"
      ;;
  esac

  if [[ "$annotation" == "— "* ]]; then
    usage=""
    description="${annotation#— }"
  elif [[ "$annotation" == *" — "* ]]; then
    usage="${annotation%% — *}"
    description="${annotation#* — }"
  else
    usage=""
    description="$annotation"
  fi
  printf 'Usage: airline %s' "$first"
  [[ -z "$second" ]] || printf ' %s' "$second"
  [[ -z "$usage" ]] || printf ' %s' "$usage"
  printf '\n\n%s\n' "$description"
}

#-----------------------------------------------------------------------------#
# Noun dispatchers — each parses its verb and makes exactly one delegated call.
# The `#| …` markers on the arms are the help source.
#-----------------------------------------------------------------------------#

cmd_state () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    suspend) lifecycle_state_suspend ;;   #| — mute the palette + trap the prefix (session dormant)
    resume)  lifecycle_state_resume ;;    #| — restore vibrant colours + release the prefix
    toggle)  lifecycle_state_toggle ;;    #| — flip active/suspended
    show)    lifecycle_state_show ;;      #| — print the current state (active | suspended)
    *) die "unknown state command: $verb" ;;
  esac
}

cmd_status () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   lifecycle_status_set "$@" ;;   #| <status-key> <active|result|attention> [--transient] [-t <window>] — set app status
    clear) lifecycle_status_clear "$@" ;; #| <status-key> [-t <window>] — clear app status
    show)  lifecycle_status_show "$@" ;;  #| [<status-key>] [-t <window>] — show a window's app status
    *) die "unknown status command: $verb" ;;
  esac
}

cmd_health () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   lifecycle_health_set "$@" ;;   #| <health-key> <ok|warn|fail> [--transient] [-t <window>] — set window health
    clear) lifecycle_health_clear "$@" ;; #| <health-key> [-t <window>] — clear window health
    show)  lifecycle_health_show "$@" ;;  #| [<health-key>] [-t <window>] — show a window's health
    *) die "unknown health command: $verb" ;;
  esac
}

cmd_problem () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    set)   lifecycle_problem_set "$@" ;;   #| <session> <problem-key> <ok|warn|fail> [<message>] — set or recover a session problem
    clear) lifecycle_problem_clear "$@" ;; #| <session> <problem-key> — clear a session problem
    show)  lifecycle_problem_show "$@" ;;  #| [<session> [<problem-key>]] — show all sessions, one session, or one problem
    *) die "unknown problem command: $verb" ;;
  esac
}

cmd_lock () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)  lifecycle_lock_show "$@" ;;  #| — list outstanding transactions and owner state
    clear) lifecycle_lock_clear "$@" ;; #| <session|window> <target> <namespace> — release one stale lock
    *) die "unknown lock command: $verb" ;;
  esac
}

cmd_palette () {
  # A palette element is a public option (@airline-<element>). `set -g` supplies a
  # user input; `use` installs a private session snapshot for the whole set. Like segment,
  # the per-element CLI path is read-only — `show` is the discovery surface (bare for humans,
  # `show <field>` a raw value for scripts; `show name` is the active-palette read).
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      layout_palette_show "$@" ;;      #| [name|<palette-element>] — show the palette summary or one raw field
    use)       layout_palette_use "$@" ;;       #| <palette> — load a complete palette and repaint adapters
    available) layout_palette_available ;;      #| — list palettes on the search path
    register)  layout_palette_register "$@" ;; #| <dir> — add a palette search directory
    *) die "unknown palette command: $verb" ;;
  esac
}

cmd_segment () {
  # Users stage segment changes with `set -g`; validated layouts declare them through
  # their function contract. This noun is read-only — `show` reads the private snapshot.
  local verb="${1:-}"; shift || true
  case "$verb" in
    show) layout_segment_show "$@" ;;   #| [<segment>] — show one segment or all segments
    *) die "unknown segment command: $verb" ;;
  esac
}

cmd_adapter () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    use)       layout_adapter_use "$@" ;;       #| <adapter>... — apply palette roles to one or more plugins
    load)      layout_adapter_load "$@" ;;      #| <file> — apply a one-off adapter script
    show)      layout_adapter_show ;;           #| — list applied adapters
    available) layout_adapter_available ;;      #| — list adapters on the search path
    register)  layout_adapter_register "$@" ;; #| <dir> — add an adapter search directory
    *) die "unknown adapter command: $verb" ;;
  esac
}

cmd_layout () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    use)       layout_use "$@" ;;       #| <layout> — apply a named layout definition
    load)      layout_load "$@" ;;      #| <file> — apply and record a one-off layout definition
    show)      layout_show "$@" ;;      #| [name|path] — show active layout provenance
    available) layout_available ;;      #| — list layouts on the search path
    register)  layout_register "$@" ;; #| <dir> — add a layout search directory
    *) die "unknown layout command: $verb" ;;
  esac
}

cmd_classifier () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      runner_classifier_show "$@" ;;      #| <classifier> — show summary, contract, and resolved path
    available) runner_classifier_available ;;      #| — list classifiers available to runners
    register)  runner_classifier_register "$@" ;; #| <dir> — add a classifier search directory
    *) die "unknown classifier command: $verb" ;;
  esac
}

cmd_filter () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      runner_filter_show "$@" ;;      #| <filter> — show summary, contract, and resolved path
    available) runner_filter_available ;;      #| — list filters available to runners
    register)  runner_filter_register "$@" ;; #| <dir> — add a filter search directory
    *) die "unknown filter command: $verb" ;;
  esac
}

cmd_probe () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      runner_probe_show "$@" ;;      #| <probe> — show summary, arguments, interval, and resolved path
    available) runner_probe_available ;;      #| — list probes available to runners
    register)  runner_probe_register "$@" ;; #| <dir> — add a probe search directory
    *) die "unknown probe command: $verb" ;;
  esac
}

cmd_runner () {
  local verb="${1:-}"; shift || true
  case "$verb" in
    show)      runner_show "$@" ;;       #| <runner> [<arg>...] — show one named composition with resolved defaults
    available) runner_available ;;       #| — list named runner compositions
    register)  runner_register "$@" ;;  #| <dir> — add a runner search directory
    run)       runner_run "$@" ;;        #| [--here|--pane [-h|-v]|--window] [<runner>] [--classify <classifier>] [--filter <filter> [--merge-stderr]] [--probe <probe> [<arg>...]] -- <command>... — run a command with monitoring
    watch)     runner_watch "$@" ;;      #| [--here|--pane [-h|-v]|--window] [<runner>] [--probe <probe> [<arg>...]] — watch probe state until interrupted
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
    init)     lifecycle_init    "$@" ;;   #| — seed defaults, register paths, publish the CLI handle, and render
    apply)    lifecycle_apply   "$@" ;;   #| — commit global option edits and render the session
    show)     lifecycle_show    "$@" ;;   #| — print the active configuration
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
    help)     _help_command "$@" ;;      #| [<command> [<verb>]] — show command help
    ""|-h|--help) _help_command ;;
    *) die "unknown command: $cmd (try: airline help)" ;;
esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
  exit $?
fi

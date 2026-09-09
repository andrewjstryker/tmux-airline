# Process runners

This guide covers running commands and polling services. For ordinary bar setup,
see the [README](../README.md). Use `airline help runner` or
`airline help runner run` for the installed CLI grammar.

## Three ways to run work

1. **A command with defaults:** `airline runner run -- make test` uses the basic
   exit classifier.
2. **A named composition:** `airline runner run tap -- bats --formatter tap test/`
   selects a reusable combination of elements.
3. **An explicit specification:** `airline runner run --classify basic --filter tap
   -- bats --formatter tap test/` states that same combination directly.

The explicit specification is the normal form to which named compositions expand.
Placement and the child command belong to the invocation. `runner describe <name>`
reports the evaluated elements and supported modes before you launch work.

## Running and watching

Interactive programs with lifecycle hooks should call airline's `status` and
`health` API directly. Use a runner for non-interactive
lifecycles: `run` launches a command, while `watch` polls external state without
requiring a placeholder local job.

Airline ships `basic` as the implicit classifier, `tap` as a stream filter, and
`http` as a probe. Each is a first-class catalog with its own discovery commands:

```sh
airline classifier list
airline classifier describe basic
airline filter describe tap
airline probe describe http
```

Elements compose only for one invocation:

```sh
airline runner run -- make test
airline runner run --pane -- npm test
airline runner run --pane -h -- npm test
airline runner run --window -- cargo test
```

With no placement option, a runner executes synchronously in the current pane,
streams terminal I/O, and returns the command's original exit status. `--pane` and
`--window` launch in new tmux topology and print the new pane id. After `--pane`, the
native tmux `-h` and `-v` modifiers select the split orientation; bare `--pane` keeps
tmux's default.
Spawned panes are retained after exit so their output and native tmux exit status
remain available until dismissed.

A probe-only implementation can watch a remote service until interrupted:

```sh
airline runner watch --probe http http://localhost/health
airline runner watch --window --probe http endpoint1 endpoint2
```

Frequently used compositions can be named. The shipped `tap` composition supports
`run`; `http` supports both `run` and `watch`:

```sh
airline runner list
airline runner describe tap
airline runner run tap -- bats --formatter tap test/
airline runner watch http http://localhost/health
```

A runner catalog entry contains monitoring configuration, never the command. It is
expanded for that invocation and does not become active session state. With no
arguments, the shipped `http` runner checks
`http://localhost/health/live` and `http://localhost/health/ready`; supplied
endpoints replace those defaults. HTTP accepts `--expect <regex>`, `--timeout
<seconds>`, and `--connect-timeout <seconds>` before explicit endpoints; see
`airline probe describe http` and the [HTTP policy contract](runner-elements.md#shipped-contributor-policies).

While watching, status is `active` and probe reports drive health. Stopping the
watch clears status; contributors own recovery of their health claims.

`--pane [-h|-v]` and `--window` override the current-pane placement and are mutually
exclusive. Element arguments continue until the next reserved runner option. Keep each
element's arguments together; see the [argument contract](runner-elements.md#arguments-and-named-compositions).
For `run`, the bare `--` separates the airline specification from the command.

This lifecycle monitoring is independent of tmux's standard terminal monitoring.
Airline observes a process it runs: whether it is active, its changing health, and
how it exits. Tmux observes the containing terminal: activity, silence, and bells.
The signals may overlap in directing attention to a window, but neither implies or
configures the other. Users may invoke either system alone or combine them; runner
placement never changes `monitor-activity`, `monitor-silence`, or `monitor-bell`.

While a command runs, its window reports status `active`. On exit, airline maps the
runner's normalized result onto its existing channels:

| Result | Status | Health |
|--------|--------|--------|
| `ok` | `result` | clear |
| `warn` | `result` | `warn` + classifier diagnostic |
| `fail` | `result` | `fail` + classifier diagnostic |

Completion status is cleared after observation because the command output remains in
its pane.
Completion health is persistent and retains the classifier's opaque diagnostic;
Airline does not manufacture or interpret that text. A selected filter may interpret
a copied output stream to project live health with its own diagnostic. Its final
stream condition is retained independently of classifier health. Filter and probe authors own their keys and recovery; stopping the runner does not
clear their observations.

## Authoring runner elements

Runner elements are trusted shell files in independently registered classifier,
filter, and probe catalogs; shipped examples live under `runners/`. `run` uses the
`basic` classifier unless an explicit `--classify` is supplied. A classifier looks
like:

```bash
#| summary: Interpret pytest termination

airline_runner_classify() { # <exit-status> <signal>
  case "$1" in
    0) printf 'ok\n' ;;
    5) printf 'warn\tpytest collected no tests\n' ;;
    *) printf 'fail\tpytest failed with status %s\n' "$1" ;;
  esac
}
```

Register an implementation in its corresponding catalog, then compose one invocation:

```sh
airline classifier register ~/.config/airline/classifiers
airline runner run -- pytest
airline runner run --classify pytest -- make test
```

Filters receive copied command stdout; `--merge-stderr` includes stderr in that copy.
Probes perform bounded observations, with their stdout shown directly in the pane.
Both receive health and problem reporting functions that call the same mutations as
the CLI without launching another Airline process. The author supplies contributor
and key and decides when to report recovery.

```sh
airline runner run --filter tap -- bats --formatter tap test/
airline runner watch http http://localhost/health/live http://localhost/health/ready
```

The shipped TAP filter reports under `airline-tap` / `assertions`. The HTTP probe uses
`airline-http`, separate health keys for each endpoint, and a `curl` capability problem.
By default, each 2xx response recovers its endpoint; other responses or connection failures report
failure. Missing curl is a capability problem, and missing endpoints are a CLI error.
HTTP requests default to two-second connection and five-second total timeouts;
`--expect`, `--connect-timeout`, and `--timeout` configure this policy.

Core does not require a report on every observation or clear element claims when a
run/watch stops. The signal API reduces claims and applies its ordinary lifecycle
rules. See [runner element contracts](runner-elements.md) for callback signatures,
key ownership, validation, and recovery semantics.

## Authoring named compositions

Runner definitions are trusted shell files in an independently registered catalog;
shipped definitions live in `runners/definitions/`. A `#|` header declares the
discovery text and one required function builds a validated composition:

```bash
#| summary: Monitor a TAP-producing test command
#| usage:

airline_runner_configure() { # <configure-function> [<runner-arg>...]
  local configure="$1"; shift
  "$configure" classify basic
  "$configure" filter tap
}
```

`#| interval:` sets a probe's default pace. A composition may override it with
`"$configure" interval 30`, and any invocation overrides both with `--interval
<seconds>`, so a slow endpoint does not require its own copy of the probe.

Metadata uses the shared `#|` headers. The configuration callback accepts
`classify`, `filter`, `probe`, and `interval` declarations, validates their
arity and cardinality, and preserves arguments for every element as argv. It cannot specify `--`
or a command. Unexpected callback fields, duplicates, or stdout make the definition
invalid.

```bash
"$configure" classify <name> [<arg>...]
"$configure" filter <name> [<arg>...] [--merge-stderr]
"$configure" probe <name> [<arg>...]
```

See [runner element arguments](runner-elements.md#arguments-and-named-compositions)
for reserved tokens and argument boundaries. Arguments supplied after a named runner
are passed to its configuration function.
A definition can therefore provide defaults while allowing replacements. `run` uses
the complete configuration; `watch` uses only the probe, failing when the runner has
none. Placement remains an option on the `run` or `watch` invocation and cannot be
stored in a runner. There is no runner mode or separate watcher definition.
Register and inspect compositions like every other catalog:

```sh
airline runner register ~/.config/airline/runners
airline runner list
airline runner describe my-tests
```

A plugin that already owns richer scheduling or callbacks may instead call the
health API directly. That is an alternative to `watch`, not a distinction based on
whether the observed service is local or remote.

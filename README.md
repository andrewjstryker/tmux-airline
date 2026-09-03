# tmux-airline

A tmux status line inspired by vim-airline. Powerline-style chevrons, a layered
color hierarchy, swappable palettes, and a small CLI that lets plugins and your
own config drive the bar.

<p align="center">
  <img src="airline-screenshot.png" alt="tmux-airline screenshot" width="800">
</p>

Features:

- Three-tier status bar with powerline chevrons
- Swappable color **palettes** (dark, light, Solarized) — or your own
- Composable **layouts** that arrange the bar, plus a CLI to drive segments and
  per-window badges
- **Adapters** that recolor tmux-cpu, tmux-battery, tmux-online-status, and
  tmux-prefix-highlight from the active palette
- Discoverable process **runner catalogs** with exit classifiers, stream filters,
  state probes, named run/watch compositions, and pane/window placement
- Server-global widget **problems**, reduced to one extreme-right warning with
  full diagnostics available through the CLI
- Suspend/resume for nested tmux sessions

## Installation

This plugin requires **tmux 3.0+** and Bash 4+ (for associative arrays), and
has no other external dependencies. It is tested on tmux 3.4 and uses tmux
features available from 3.0 onward.

> **tmux 3.0** is needed for the format comparison operators (`#{==:…}`,
> `#{?…}` over user options) that drive the per-window entry color and the
> badge/segment rendering. On older tmux the status line will not render
> correctly.

### With [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm) (recommended)

Add to `.tmux.conf`:

```tmux
set -g @plugin 'andrewjstryker/tmux-airline'
```

Press `<prefix> + I` to install.

### Manual

```shell
git clone https://github.com/andrewjstryker/tmux-airline ~/clone/path
```

Add to the bottom of `.tmux.conf`:

```tmux
run-shell ~/clone/path/airline.tmux
```

Then reload:

```shell
tmux source-file ~/.tmux.conf
```

`airline.tmux` initializes the plugin and exposes the `airline` CLI. It binds
**no keys** — you wire your own where needed (see *Nested sessions* below).

### Put `airline` on your PATH

From the plugin directory, install its small launcher into `~/.local/bin`:

```shell
make install
```

Ensure `~/.local/bin` is on your `PATH`. To use another location, set `PREFIX`
or `BINDIR`:

```shell
make install PREFIX="$HOME"
make install BINDIR="$HOME/bin"
```

The launcher finds the active plugin through tmux, so it keeps working if TPM
moves the plugin directory. Tmux-airline must be initialized in the tmux server;
otherwise the launcher prints an actionable error. The same install places Bash
and Zsh completions under the prefix's standard `share` directories. Your shell
or completion manager must include those directories in its normal completion
search path.

## Core concepts

Five things, driven by one `airline` CLI:

| Concept     | What it is                                                        | You change it with            |
|-------------|-------------------------------------------------------------------|-------------------------------|
| **palette** | The colors — a set of named roles (`inner-bg`, `active`, `ok`, …) | `palette use`, or `set -g`    |
| **segment** | One powerline block's content, in a fixed slot                    | a layout, or `set -g`         |
| **layout**  | A composition that fills the slots (and picks adapters)           | `layout use`                  |
| **adapter** | A bridge that paints a third-party plugin from the palette        | `layout` (or `adapter use`)   |
| **runner**  | An ephemeral run/watch composition over monitoring primitives     | `runner run`, `runner watch`  |

Choose a palette for the colors and a layout for the arrangement. To change an
individual palette role or segment slot, set a global tmux option and run
`airline session apply`. Airline copies that input into the invoking session's private
configuration. Plugins and widgets can use status, health, and problem signals
to report live state without rebuilding the bar.

## Nested sessions (suspend/resume)

When running tmux inside tmux (e.g., a local session SSH'd into a remote one),
every layer looks identical and keystrokes only reach the outer session.
`airline session toggle` suspends the outer session:

- The outer prefix is disabled and keystrokes pass through to the inner session
- The outer status bar dims to a flat, muted palette so you can tell which
  layer is active

airline binds no keys itself; bind your own, using the published CLI handle so
it works wherever airline is installed. Because `suspend` switches tmux's
`key-table` to `off`, bind the toggle in **both** the `root` table (fires while
active) and the `off` table (fires while suspended), so one key round-trips:

```tmux
bind -T root F12 run "#{@airline-cli} session toggle"
bind -T off  F12 run "#{@airline-cli} session toggle"
```

Inspect the current state with `airline session show state` (`active` | `suspended`).

## Palettes

A palette is a set of named color **roles**. The bar, badges, and window colors
all reference roles, never raw colors — so swapping the palette recolors
everything at once.

### Backgrounds — the three chevron tiers

| Role        | Where                          |
|-------------|--------------------------------|
| `outer-bg`  | Left/right edge blocks         |
| `middle-bg` | The blocks one step in         |
| `inner-bg`  | Window list / center           |

### Content colors — text by visual weight

| Role         | Used for                      |
|--------------|-------------------------------|
| `secondary`  | Default / low-priority text   |
| `primary`    | Normal text                   |
| `emphasized` | Section labels, active text   |

### Semantic roles — color by meaning

| Role       | Meaning                        |
|------------|--------------------------------|
| `active`   | Current window, active pane    |
| `special`  | Clock, special modes           |
| `ok`       | Success / completion (green)   |
| `alert`    | Activity, degraded (amber)     |
| `stress`   | Bell, critical (red)           |
| `zoom`     | Zoomed pane indicator          |
| `copy`     | Copy mode indicator            |
| `monitor`  | Monitor mode indicator         |

`ok`/`alert`/`stress` form a green/amber/red triad. `ok` is for **discrete
success** (a job or agent that *finished well*) — a meter's "good" state is just
the normal baseline, so only event-based signals have a distinct "succeeded"
state to paint green.

### Choosing and overriding a palette

Airline ships several palettes and picks `default` on first run. Switch with
`palette use` — it reloads the colors and re-applies the bar:

```tmux
airline palette use dark
```

| Palette           | Description                                     |
|-------------------|-------------------------------------------------|
| `default`         | Airline's shipped look (256-color dark)         |
| `dark`            | Neutral dark, explicit 256-color codes          |
| `light`           | Neutral light, explicit 256-color codes         |
| `solarized-dark`  | Solarized dark (assumes a Solarized terminal)   |
| `solarized-light` | Solarized light (assumes a Solarized terminal)  |

`airline palette list` lists what's on the search path; `airline palette
show` prints the active palette and every role; `airline palette show name`
prints just the active name (for scripts).

Change individual roles with normal global tmux options, then apply them:

```tmux
set -g @airline-active "colour214"
set -g @airline-stress "colour196"
airline session apply
```

`apply` copies each explicitly set global role over the invoking session's private
snapshot. This is a manual edit, so `palette show name` becomes empty. Unsetting the
global option later stops it from being copied again; it does not reconstruct an
older palette value. Use `palette use <name>` again when you want the complete named
palette back. A named palette selection itself affects only the invoking session and
does not rewrite the global options.

A custom palette is a tmux file containing
`set-option @airline-<role> <color>` lines; `layouts/palettes/default` is a complete
example. Put the file in a directory, register that directory, and select the
palette by filename. A registered name shadows a shipped one:

```tmux
airline palette register ~/.config/airline/palettes
airline palette use my-palette
```

## Segments and layouts

The bar is the **window list** in the center, flanked by a left and a right
**segment stack**. There are six fixed slots — three per side — and the powerline
**tier** (which background, hence the depth gradient) is baked into each slot
name, so the gradient is automatic:

```
┌──────────┬──────────┬─────────┬──────────────┬─────────┬──────────┬──────────┐
│ left-out │ left-mid │ left-in │ window list  │ right-in│ right-mid│ right-out│
│ (outer)  │ (middle) │ (inner) │  (inner-bg)  │ (inner) │ (middle) │ (outer)  │
└──────────┴──────────┴─────────┴──────────────┴─────────┴──────────┴──────────┘
   ←────────── left stack ──────────→          ←────────── right stack ──────────→
```

| Slot        | Side  | Tier   |
|-------------|-------|--------|
| `left-out`  | left  | outer  |
| `left-mid`  | left  | middle |
| `left-in`   | left  | inner  |
| `right-in`  | right | inner  |
| `right-mid` | right | middle |
| `right-out` | right | outer  |

A segment's content is a normal tmux format string. You set it directly and
re-apply — the CLI reads segments back but does not write them:

```tmux
# put the kubectl context in the right-inner slot
set -g @airline-segment-right-in '#[fg=colour39]⎈ #(kubectl config current-context)'
airline session apply

# inspect the slots (bare = all, or name one)
airline segment show
airline segment show right-in
```

### Layouts

Usually you don't set slots by hand — a **layout** does. A layout is a script
that fills the slots (and turns on the matching adapters) as one composition.
`layout use` runs it once, captures its slots and adapters, and records it. A later
palette change repaints the recorded adapters without rerunning the layout script;
plain `apply` copies global edits and renders the committed arrangement:

```tmux
airline layout use minimal
airline layout show          # the active layout + its file
airline layout list     # what's on the layout path
```

| Layout     | What it composes                                                    |
|------------|---------------------------------------------------------------------|
| `adaptive` | Init's default — probes installed plugins, composes only what's present, degrades to session + date |
| `default`  | The standard full arrangement                                       |
| `full`     | Every slot populated                                                |
| `minimal`  | A pared-down bar                                                    |

Switching layouts starts from a clean slate, so a layout owns exactly the arrangement
it declares. A layout is trusted Bash with one required function. The function uses
its callback argument to declare segments and adapters:

```bash
airline_layout_configure () {
  local declare="$1"
  "$declare" segment left-out '#S'
  "$declare" segment right-mid '#{cpu_fg_color}#{cpu_icon}'
  "$declare" adapter use cpu
}
```

Airline validates the whole declaration before replacing private layout state.
Unknown or duplicate slots, invalid adapters, nested Airline commands, and stdout
are errors. Omitted slots are intentionally empty. Put the file in a registered
layout directory and select it by filename. A failed selection preserves the last
committed layout and raises the global `airline-layout` problem with that session as
its origin; a successful layout selection resolves that origin's claim.

The **window-list entry** itself is fixed as `#I:#W` (index:name) and styled by
the window colors below rather than configured as a segment.

## Plugin adapters

An **adapter** teaches a third-party plugin to draw in airline's palette. It's a
small snippet that sets the plugin's own color options from the active palette —
so tmux-cpu, tmux-battery, and friends match the bar and recolor whenever the
palette changes. Adapters ship for:

| Plugin                 | Adapter          | Slot it usually fills |
|------------------------|------------------|-----------------------|
| tmux-online-status     | `online`         | `left-mid`            |
| tmux-prefix-highlight  | `prefix-highlight` | `right-in`          |
| tmux-cpu               | `cpu`            | `right-mid`           |
| tmux-battery           | `battery`        | `right-out`           |

The `adaptive` layout detects which of these are installed (by directory name in
the plugin folder) and wires up only those — an uninstalled plugin leaves its
slot empty (the block collapses to just its background). airline only sets the
plugin's colors; the plugin draws its own widget.

You rarely call adapters directly — a layout invokes them — but you can:
`airline adapter use cpu`, `airline adapter show` (what's applied), `airline
adapter list` (what's on the path).

## Process runners

Interactive programs with lifecycle hooks should call airline's `status` and
`health` API directly. A runner is the lower-fidelity floor for non-interactive
lifecycles: `run` launches a command, while `watch` polls external state without
requiring a placeholder local job.

Airline ships `basic` as the implicit classifier, `tap` as a stream filter, and
`http` as a probe. Each is a first-class catalog with its own discovery commands:

```sh
airline classifier list
airline classifier show basic
airline filter show tap
airline probe show http
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

Frequently used compositions can be named. Airline ships `tap` as a run
composition and `http` as a watch composition:

```sh
airline runner list
airline runner show tap
airline runner run tap -- bats --formatter tap test/
airline runner watch http http://localhost/health
```

A runner catalog entry contains monitoring configuration, never the command. It is
expanded for that invocation and does not become active session state. With no
arguments, the shipped `http` runner checks
`http://localhost/health/live` and `http://localhost/health/ready`; supplied
endpoints replace those defaults.

While watching, status is `active` and probe reports drive health. Stopping the
watch clears both; there is no artificial command exit to classify.

`--pane [-h|-v]` and `--window` override the current-pane placement and are mutually
exclusive. Probe arguments continue to end-of-argv for `watch`.
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
stream condition is retained independently of classifier health. Probe health is
cleared when probing stops because Airline can no longer assert that observation is
current.

### Runner elements

Runner elements are trusted shell files in independently registered classifier,
filter, and probe catalogs; shipped examples live under `runners/`. `run` uses the
`basic` classifier unless an explicit `--classify` is supplied. A classifier looks
like:

```bash
AIRLINE_CLASSIFIER_SUMMARY='Interpret pytest termination'

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

A filter receives a tee'd copy of stdout by default. `--merge-stderr` applies
ordinary `2>&1` semantics before the tee:

```bash
AIRLINE_FILTER_SUMMARY='Interpret top-level TAP output'

airline_runner_filter() { # <pid> <report-function>
  local pid="$1" report="$2"
  while IFS= read -r line; do
    # Report `ok` or `warn|fail "user-facing diagnostic"`.
    # A later `ok` reports recovery.
  done
  # Always finish with `ok`, or `warn|fail "user-facing diagnostic"`.
}
```

The filter must report at least once; exiting without a report is an integration
failure. Airline retains the last report after EOF until the next run clears that
filter contributor. The classifier and filter have separate health contributors,
so a stream diagnostic is not erased by exit classification.

Airline ships `tap` as the filtering example. It warns when a
top-level TAP assertion fails, fails when the unsuccessful plan completes or the
stream bails out, reports `ok` after a clean stream, and leaves TODO/SKIP failures
alone:

```sh
airline runner run --filter tap -- bats --formatter tap test/
```

A long-lived process can instead define a probe when an API or other state source
contains useful current information absent from its logs:

```bash
AIRLINE_RUNNER_PROBE_INTERVAL=5
AIRLINE_PROBE_SUMMARY='Check service health endpoints'
AIRLINE_PROBE_USAGE='<endpoint> [<endpoint>...]'

airline_runner_probe() { # <lifecycle-pid> <report-function> [<arg>...]
  local pid="$1" report="$2"
  # Make one bounded query, write useful results to stdout, and call:
  # "$report" ok
  # "$report" warn|fail "user-facing diagnostic"
}
```

Probe stdout is uninterpreted user output. Airline writes it to the pane but never
parses it; formats such as `ok 204 <endpoint>` are conventions implementations may
adopt, not part of the protocol. Health observations travel only through the
reporter callback. During `run`, probe stdout bypasses the command-output tee, so a
selected filter sees only command output. During `watch`, probe stdout supplies the
visible polling transcript.

The shipped `http` probe checks one or more endpoints uniformly:

```sh
airline runner watch --probe http \
  http://localhost/health/live \
  http://localhost/health/ready
```

The equivalent shipped named composition is shorter:

```sh
airline runner watch http \
  http://localhost/health/live \
  http://localhost/health/ready
```

At least one URL is required. For each endpoint the probe writes its condition,
HTTP status, and URL to stdout. Each 2xx response reports `ok`; every other response
or connection failure reports `fail` with an endpoint diagnostic. Airline ignores
probe stdout, reduces callback reports to the worst condition, and retains an
opaque message reported at that severity. Each request has a two-second
connection timeout and a five-second total timeout. Missing `curl` or invalid
arguments use the problem API.

Airline runs one probe at a time, schedules the next after the interval, and stops
on process exit (`run`) or interruption (`watch`). It validates observations and
projects filter and probe health independently. The probe owns timeouts and domain
semantics; airline does not add persistence, restart policy, or general job
management. A probe that exits nonzero, calls no reporter, or reports an invalid
value creates a problem until a valid observation recovers it. Under `watch`, the
PID argument identifies the local watcher lifecycle, not the remote service.

### Named runner compositions

Runner definitions are trusted shell files in an independently registered catalog;
shipped definitions live in `runners/definitions/`. Two required functions build a
validated composition:

```bash
airline_runner_metadata() { # <declare-function>
  local declare="$1"
  "$declare" summary 'Monitor a TAP-producing test command'
  "$declare" usage ''
}

airline_runner_configure() { # <configure-function> [<runner-arg>...]
  local configure="$1"; shift
  "$configure" classify basic
  "$configure" filter tap
}
```

The metadata callback accepts `summary` and `usage`. The configuration callback
accepts `classify`, `filter`, and `probe` declarations, validates their
arity and cardinality, and preserves probe arguments as argv. It cannot specify `--`
or a command. Unexpected callback fields, duplicates, or stdout make the definition
invalid.

```bash
"$configure" classify <name>
"$configure" filter <name> [merge-stderr]
"$configure" probe <name> [<arg>...]
```

Arguments supplied after a named runner are passed to its configuration function.
A definition can therefore provide defaults while allowing replacements. `run` uses
the complete configuration; `watch` uses only the probe, failing when the runner has
none. Placement remains an option on the `run` or `watch` invocation and cannot be
stored in a runner. There is no runner mode or separate watcher definition.
Register and inspect compositions like every other catalog:

```sh
airline runner register ~/.config/airline/runners
airline runner list
airline runner show my-tests
```

A plugin that already owns richer scheduling or callbacks may instead call the
health API directly. That is an alternative to `watch`, not a distinction based on
whether the observed service is local or remote.

## Window list signals

### Targets and scope

Airline maps its state onto tmux's normal scopes:

- Options set with `set -g @airline-*` are server-wide input, copied by a later
  configuration operation into that operation's session.
- The committed palette, segments, layout, and adapters are private to the invoking
  session and are read through the CLI.
- Session-public options written while evaluating palette/layout files are cleared;
  they are not another user configuration scope.
- Status is owned by a pane and projected at its window; health belongs to a window.
  Their documented `-t` targets resolve the corresponding owner.
- Problems belong to the tmux server. A pane-hosted reporter may preserve its
  runtime origin with `problem set --pane <pane-target>`.

A window entry has three layers, owned by two parties. **airline** owns the
entry's *color* (the name itself); **plugins** speak through two *badges* that
flank the name. They never collide.

```
 ○ 1:vim        ● 2:build ▲        ◆ 3:agent
 │   └name      │   └name  └health   │   └name
 └status        └status              └status  (needs you)
```

The **status badge** sits *left* of the name; the **health badge** sits *right*.
Because they're on opposite sides, their colors may overlap without ambiguity.

### Entry color (airline-owned): tmux modes

The window name's color is airline's alone — no plugin API. It reflects, in
order, **tmux modes** over the **baseline** (focused / last / normal):

| State                              | Color     |
|------------------------------------|-----------|
| A pane in the window is **zoomed** | `zoom`    |
| The active pane is in **copy mode**| `copy`    |
| `monitor-activity` is **on**       | `monitor` |

Precedence is **zoom > copy > monitor**. With no mode, the normal focused, last,
activity, and bell styling applies.

### Badges (plugin-owned): the `airline` CLI

Plugins drive badges through the **`airline` command** — the supported API. It
owns the underlying tmux options and validates input, so plugins never depend on
option-name conventions.

> **Finding the CLI.** airline publishes its own path in the `@airline-cli`
> tmux option on load, so a cooperating plugin never has to guess the install
> location. This bootstrap handle is the one managed option consumers read
> directly; compatibility information remains behind the public CLI:
>
> ```shell
> airline="$(tmux show -gqv @airline-cli)"
> if [ -n "$airline" ]; then
>   version="$("$airline" version)"
>   [ -n "$version" ] && "$airline" status set active
> fi
> ```
>
> The empty check doubles as an "is airline installed?" probe.

### Contributor identity

Health and problem reporters supply two distinct identifiers: a stable contributor
name and a claim key owned by that contributor. Airline does not maintain a plugin
registry or try to prove ownership, but it stores both fields so two independent
contributors can safely use the same claim key. For example, `tmux-online`
`connectivity` and `tmux-cpu` `connectivity` are separate claims.

Airline-owned configuration reports use contributor `airline` with the stable claim
keys `airline-layout` and `airline-palette`; palette and layout names themselves do
not gain contributor qualification. Runner extensions report as concrete contributors
such as `airline-runner-classifier-basic` or `airline-runner-probe-http`, keeping
classifier, filter, and probe claims independent.

The contributor contract is:

- use a stable software identity as the contributor and mutate only its claims;
- keep severity and diagnostic text out of the key so identity remains stable;
- include an instance in the claim key when concurrent instances report independently;
- use `ok` when a retained health claim recovers; reserve `clear` for destructive
  removal and `ack` for user acknowledgement;
- use `problem set ... ok` when the current pane or session origin recovers, and
  `problem resolve` only when the contributor has verified that the underlying
  capability is restored for every origin represented by that problem;
- report an inability to provide the contributor's advertised capability as a
  problem, while successfully observed unhealthy domain state remains health.

Status is intentionally lighter. Each pane owns one workflow phase because the pane
itself contains the explanation. A contributor reduces any internal subprocesses or
tools into that pane-level state.
Health identity is contributor plus claim key within a window. Problem identity is
contributor plus claim key globally, while Airline separately records the pane or
session origins currently asserting it. Contributors and keys must be nonempty and
contain neither whitespace nor `:`; the colon is reserved for private storage
framing.

**Status** (left) — one workflow phase per pane. Airline reduces every pane in the
window to its highest-priority phase:

```tmux
airline status set active      # ○ processing (amber)
airline status set result      # ● output ready (green) — outranks active
airline status set attention   # ◆ waiting for input (amber)
airline status clear
airline status show            # pane ids + current phases + revisions
```

Levels reduce by user-action priority: `active < result < attention`. Ongoing work
is passive information, completed output is ready to inspect, and an input request
blocks progress. This is presentation priority rather than severity. A window with
no status entry shows nothing.

**Health** (right) — a single condition glyph reduced from any number of claims;
airline shows the **worst**. `ok` (or no claim) shows
**nothing** — a clean right side means healthy:

```tmux
airline health set example-agent context fail "connection refused"     # ▲ broken (red)
airline health set example-build tests warn "tests are still running with failures"
# badge now shows one glyph at the worst level (fail)
airline health ack example-agent context     # user has seen this fail state
airline health set example-agent context ok  # recovery clears it; drops to warn
airline health show                         # contributor + key + condition
airline health show --all                   # include acknowledged health
```

Health and problem share the levels `ok < warn < fail`. `ok` means reporter
recovery: for health it removes the claim; for problem it resolves one origin and
records `resolved` history when the final origin recovers. `clear` reaches the same
empty health state through explicit deletion rather than a reported observation.
`warn` means the component degraded gracefully and can keep working; `fail` means it
could not recover and is broken. `warn` uses the palette's amber `alert` role; `fail`
uses its red `stress` role. Glyphs are fixed (a distinct shape per visible state, so
badges stay legible without color). Every retained `warn` or `fail` condition has a
diagnostic message. Health's optional `-t <window-target>` precedes the keyed condition
tuple so the trailing message stays opaque. Messages are user-facing text supplied
by the reporter: Airline validates their framing but assigns them no meaning. Signal
commands place every option before their contributor, key, or value operands.

Status values are workflow phases with distinct transition mechanisms. `active`
remains while the producer is processing, and `attention` remains while the producer
is waiting for input. The producer advances either phase when its work changes.
`result` means processing has finished and the pane contains output ready to view.
Each effective status set or clear increments a counter owned by that pane. Setting
`result` ensures that Airline's focus hook is installed; contributors do not install
the hook or handle revision tokens. The hook uses a private revision-guarded callback,
so leaving a pane deletes only the exact result that was observed while leaving every
other pane, `active`, `attention`, and any newer result untouched. Merely being
visible in a window is not treated as proof of observation. Plain `status clear`
explicitly deletes the targeted pane's entry. `status show` includes the current
revision for general introspection. Producers normally advance active work and input
requests; an Airline-aware coding agent is the motivating interactive producer for
`attention`. Runner health separately communicates whether a completed result was
`ok`, `warn`, or `fail`.

Health and problem are never consumed by viewing a window. They expose explicit
`ack`, which retains the underlying condition but hides
its badge and omit it from normal `show`; `show --all` includes acknowledged state.
A message-only refresh at the same level remains acknowledged. Any `warn` / `fail`
level change resets acknowledgement and makes the new state visible. Reporter
recovery removes a health claim, so a later failure starts unacknowledged.

Because color and badges live on different layers, a window can show a mode
color, a health glyph, and a status glyph all at once without contention.

## Global problems

An airline-aware widget can fail gracefully and report why through the global
`problem` API. A problem means that Airline or one of its contributors cannot
provide an advertised capability; it is not window or pane attention. Active
problems are immediately visible in every initialized session. Airline reduces
their claims with the same `ok < warn < fail` severity ladder as health and shows
one aggregate glyph at the extreme right.

```shell
if ! command -v sensors >/dev/null 2>&1; then
  airline problem set tmux-cpu sensors warn "required program 'sensors' was not found"
  printf '?'
  exit 0
fi

# The contributor has verified its shared requirement, so retire every stale
# pane/session assertion and retain resolved history.
airline problem resolve tmux-cpu sensors
```

By default, a claim belongs to the current session context. A pane-hosted reporter
can preserve its origin explicitly with `problem set --pane "$TMUX_PANE" ...`.
Several panes and sessions may assert the same contributor/key pair independently;
`problem set ... ok` removes only the current origin's claim. Airline installs tmux
pane/session close hooks to retire claims when their origins disappear without
asserting recovery.

`problem show` lists only active problems. `problem ack <contributor> <key>`
acknowledges and hides the current level without discarding history or active claims.
A same-level diagnostic refresh remains acknowledged; a level change makes the
problem active again. Use `problem show --all [<contributor> [<key>]]` to inspect the
complete `active`, `acknowledged`, `closed`, and `resolved` lifecycle ledger and its
current origins.
`problem resolve <contributor> <key>` is an authoritative contributor recovery
operation: use it after verifying that the underlying capability is restored
globally. It removes every origin claim, including stale assertions that have not
run again, and retains a `resolved` ledger entry. If recovery is known only for one
pane or session, use `problem set ... ok` from that origin instead; the ledger
becomes `resolved` when the final claim recovers. `problem close` is normally
hook-driven, but is public so jobs may retire pane- or session-origin claims
explicitly without asserting recovery; its final claim produces `closed` history.
`problem clear <contributor> <key>` is destructive: it removes the ledger and every
active origin claim.

For the complete selection rules and lifecycle state diagrams, see
[Signal lifecycles](docs/lifecycle-signals.md).

### Transaction recovery

Airline serializes collection updates with owner-scoped tmux locks. A process killed
with `SIGKILL` cannot run cleanup, so its transaction marker can remain behind. The
diagnostics make that rare state discoverable and recoverable:

```shell
airline transaction show
# scope<TAB>owner<TAB>namespace<TAB>active|stale<TAB>pid<TAB>age-seconds

airline transaction clear global server problem
airline transaction clear window '@3' status
```

`transaction clear` only releases a stale marker; it refuses to clear one whose
recorded owner process is still alive. Recovery is separate from the problem API so
diagnosing a stuck problem transaction never depends on acquiring that same lock.

## The `airline` CLI

One entry point drives everything. Domain commands use a noun followed by a verb;
the read-only `version` command and help are root leaves. `-t` overrides the current
pane for status mutation, the current window for status/health inspection, or the
current session for targeted initialization. Target expressions are immediately
resolved to the corresponding canonical owner. Problems are server-global; an
optional pane target identifies a pane-hosted origin.

```
airline session init [-t <session-target>]  # initialize the current or selected session
airline session apply                # commit global edits and render
airline session show [state]         # print the configuration or raw session state
airline session suspend | resume | toggle
airline help [noun [verb]]    # all commands, one noun, or one leaf command

airline palette  show [name|<palette-element>] | list | use <palette> | register <dir>
airline segment  show [<segment>]              # read-only; write with set -g @airline-segment-<segment>
airline layout   show [name|path] | list | use <layout> | load <file> | register <dir>
airline adapter  show | list | use <adapter>... | load <file> | register <dir>
airline classifier show <classifier> | list | register <dir>
airline filter     show <filter> | list | register <dir>
airline probe      show <probe> | list | register <dir>
airline runner   show <runner> [<arg>...] | list | register <dir>
                 run [--pane [-h|-v]|--window] <runner> [<arg>...] -- <command>...
                 run [--pane [-h|-v]|--window] [--classify <classifier>] [--filter <filter> [--merge-stderr]] [--probe <probe> [<arg>...]] -- <command>...
                 watch [--pane [-h|-v]|--window] <runner> [<arg>...]
                 watch [--pane [-h|-v]|--window] --probe <probe> [<arg>...]
airline status   set [-t <pane-target>] <active|result|attention> | clear [-t <pane-target>] | show [-t <window-target>]
airline health   set [-t <window-target>] <contributor> <health-key> <ok|warn|fail> [<message>...] | ack|clear [-t <window-target>] <contributor> <health-key> | show [--all] [-t <window-target>] [<contributor> [<health-key>]]
airline problem  set [--pane <pane-target>] <contributor> <problem-key> <ok|warn|fail> [<message>...] | close [--pane <pane-target>|--session <session-target>] [<contributor> [<problem-key>]] | ack|clear|resolve <contributor> <problem-key> | show [--all] [<contributor> [<problem-key>]]
airline transaction show | clear <global|session|window> <target> <namespace>
```

Two conventions run through it:

- **`use` vs `register`.** `use <name>` loads a bare configuration name from a
  registered directory; `register <dir>` adds one (and lets it shadow shipped
  names). `load <path>` runs a one-off adapter or layout file. Classifier, filter,
  probe, and runner each have an independent registered catalog.

- **`show`.** Bare `show` is a human summary; `show <field>` prints one raw
  value, newline-terminated, safe for `$(…)`. `list` lists the catalog a
  `use` can pick from. Catalog-only runner nouns instead use `show <name>` for an
  implementation's summary, usage, and path. Editing a color or segment option is
  free; the bar re-renders on the next `session apply` (or `use`, which ends in one).

Help is inspected through the top-level command, for example `airline help
palette` or `airline help runner run`. Bash and Zsh completion follows the same
grammar and completes typed values such as palette, layout, probe, session, and
window names through the installed CLI.

## Development

For the architecture, internal boundaries, design rationale, and testing strategy,
see [DESIGN.md](DESIGN.md). Focused design documents begin with
[Signal lifecycles](docs/lifecycle-signals.md). Completed project work is summarized
in [CHANGELOG.md](CHANGELOG.md); prospective consolidation work lives in
[TODO.md](TODO.md).

The full suite still exercises real isolated tmux servers:

```shell
make test
```

For focused development, `make test-fast` runs only static and in-memory behavior
tests. `make test-layout`, `make test-session`, `make test-signal`,
`make test-transaction`, and `make test-runner` pair tests
with the corresponding `lib/` module; `make test-integration` runs every real-tmux
suite. Run `make lint` for ShellCheck and the architecture guards.

# tmux-airline — Design

This document defines the settled architecture, state model, and public command
grammar. Implementation details belong in the source and tests unless they protect
a non-obvious boundary described here.

Focused design documents own the detailed semantics of individual domains:

- [Signal lifecycles](docs/lifecycle-signals.md) defines the meaning, identity, and
  state transitions of status, health, and problem signals.

## Principles

1. **State is split by ownership.** Public `@airline-*` options are the user-facing
   configuration contract. Private `@airline--*` options are runtime state written
   only by airline. Native tmux options are derived output.
2. **There is one composition path.** `render`, invoked by `apply`, is the only code
   that composes the bar. Runtime signals may update live selectors and redraw, but
   they never construct an alternative bar.
3. **The middle is logic.** Badge reduction, segment assembly, render expressions,
   and palette application use domain terms and do not call the `tmux` binary.
4. **Dependencies point down.** `airline.sh` owns grammar and delegates once into
   `lib/`; internal modules call public functions in lower layers directly, and
   application tmux calls end in `lib/tmux.sh`. The graph is acyclic without
   prescribing every individual cross-module edge.
5. **Validate at the boundary; trust the interior.** CLI behavior handlers validate
   input once. Store and composition functions operate on validated values.
6. **Enforce architecture at build time.** Bash has no useful visibility boundary,
   so lightweight lint rules enforce layering without adding runtime machinery.
7. **Lifecycle operations are idempotent and redraw-gated.** Re-running `init` must
   not clobber established session choices, and rendering unchanged output must not
   refresh the client.
8. **Observe at the richest available boundary.** Interactive programs that expose
   lifecycle callbacks publish status and health through the signal API directly.
   Airline's runner is the lower-fidelity floor for non-interactive lifecycles: it
   owns command launch or probe-only watching and delegates domain interpretation
   to independently registered classifier, filter, and probe elements.

## Architecture

| File | Responsibility | Direct `tmux` calls? |
|------|----------------|:-------------------:|
| `airline.tmux` | TPM / `run-shell` entry point; invokes `airline.sh session init` | no |
| `airline` | Installable PATH shim; resolves the active CLI through `@airline-cli` | bootstrap lookup only |
| `airline.sh` | Public CLI: parses the grammar and delegates each command once | no |
| `lib/help.sh` | Renders marked CLI grammar sections for help and completions | no |
| `lib/command.sh` | Shared CLI error, context, and output helpers | no |
| `lib/session.sh` | Session bootstrap, configuration coordination, and state | no |
| `lib/transaction.sh` | Transaction-marker inspection and stale recovery | no |
| `lib/signal.sh` | Status, health, problems, projection, and observation cleanup | no |
| `lib/catalog.sh` | Owns registered search paths and bare-name resolution | no |
| `lib/layout.sh` | Palette, adapter, segment, and executable-layout behavior | no |
| `lib/runner.sh` | Runner contracts, mechanics, and orchestration | no |
| `lib/render.sh` | Owns domain vocabulary and composes the bar | no |
| `lib/collections.sh` | Stores and reduces variable-cardinality state | no |
| `lib/tmux.sh` | Mechanical operations and airline namespace policy | **yes; sole application caller** |
| `layouts/palettes/*` | Declarative public color configuration | sourced by `lib/tmux.sh` |
| `layouts/adapters/*` | Applies palette roles to third-party plugin options | no |
| `layouts/definitions/*` | Trusted Bash definitions declaring adapters and segments | no |
| `layouts/helpers/*` | Bash helpers for layout definitions; not public airline API | no |
| `runners/classifiers/*` | Interprets process termination | no |
| `runners/filters/*` | Interprets a copied command-output stream | no |
| `runners/probes/*` | Performs one bounded external observation | no |
| `runners/definitions/*` | Names a run or watch composition | no |

```mermaid
graph TD
    TPM([TPM / run-shell]):::ext --> ENTRY[airline.tmux]
    EXT([users and plugins]):::ext --> SHIM[airline]
    ENTRY --> CLI[airline.sh]
    SHIM --> CLI
    CLI --> CMD[lib/command.sh]
    CLI --> SESSION[lib/session.sh]
    CLI --> TX[lib/transaction.sh]
    CLI --> SIGNAL[lib/signal.sh]
    CLI --> LAYOUT[lib/layout.sh]
    CLI --> RUNNER[lib/runner.sh]
    CLI --> HELP[lib/help.sh]
    SESSION --> CMD
    TX --> CMD
    SIGNAL --> CMD
    LAYOUT --> CMD
    RUNNER --> CMD
    CAT --> CMD
    HELP --> CMD
    SESSION --> LAYOUT
    SESSION --> LOGIC[lib/render.sh]
    LAYOUT --> LOGIC
    LAYOUT --> SIGNAL
    RUNNER --> SIGNAL
    SESSION --> CAT[lib/catalog.sh]
    LAYOUT --> CAT
    RUNNER --> CAT
    CAT --> COLL
    COLL[lib/collections.sh]
    LAYOUT --> COLL
    RUNNER --> COLL
    LOGIC --> COLL
    SIGNAL --> LOGIC
    SIGNAL --> COLL
    SESSION --> MECH[lib/tmux.sh]
    TX --> MECH
    LAYOUT --> MECH
    RUNNER --> MECH
    LOGIC --> MECH
    SIGNAL --> MECH
    COLL --> MECH
    CMD --> MECH
    CAT -. register/resolve .-> FILES[palettes · adapters · layouts · runner catalogs]
    MECH ==> TMUX([tmux server]):::ext

    classDef ext fill:#eee,stroke:#999,color:#333,font-style:italic;
```

The graph describes ordinary in-process calls. A tmux hook or a newly created pane
starts a fresh Bash process and therefore enters through `airline.sh`, which owns
library loading, environment setup, argument validation, and dispatch. Most such
entry points use the public grammar. The result-observation hook instead uses one
explicitly private verb because invoking it correctly requires Airline's private
pane revision; it still crosses the normal CLI loading and validation boundary.
Once loaded, modules call one another directly: a
non-underscore function is a module service, while an underscore-prefixed function
is private to the file that defines it. Because every library is sourced into one
Bash function namespace, public service names must also be unique across modules;
the dependency lint rejects source-order overrides.

Build-time dependency enforcement uses the following coarse layers rather than an
allowlist of every permitted pair. Calls must point to a strictly lower layer;
`command` is a shared validation/context helper callable by every layer and itself
depends only on the mechanical context-resolution boundary.

```text
airline
  session / transaction / help
  layout / runner
  signal
  catalog / render
  collections
  tmux
```

The important boundaries are:

- Within the application layers, only `lib/tmux.sh` invokes the `tmux` binary or spells
  the `@airline-` and `@airline--` prefixes. The installable PATH shim is an external
  consumer: like a plugin, it makes one bootstrap lookup of `@airline-cli`. Higher
  layers address airline options by bare key through `pub_*` and `prv_*` accessors.
- Layouts are trusted Bash definitions, not loaded application layers. Their required
  `airline_layout_configure` function declares segments and adapters through a core
  callback. They never receive a tmux handle, target session, or private-state access.
- `lib/collections.sh` is an airline abstraction above tmux's flat option store. It is
  used only for status, health, problem, adapter membership, and search paths.
  Fixed segment slots are scalar options, not collections. Its operations take
  `global`, `session`, or `window` as their first argument and the native owner as
  their second; namespace, tuple contents, and reduction order are caller policy.
- `lib/catalog.sh` owns the common trust and lookup mechanism for every registered
  element kind. Layout and runner own element behavior but use catalog's public
  register, resolve, list, and path operations; they do not know the path collection
  namespace or representation.
- `lib/signal.sh` owns runtime status, health, and problem reporting: validation,
  collection mutation, badge projection, redraw gating, and transient consumption.
  All three signals follow the same mutation pipeline, with lifecycle policy kept
  in signal-specific callbacks. A problem is a server-global failure of airline or
  a contributor to provide an advertised capability; it is not window or pane
  attention. Layout and runner report managed problems through that public service.
- Palette and layout are independent axes: a palette chooses colors; a layout
  chooses adapters and segment strings. A palette change replays the active adapter
  declarations against the new colors without rerunning the layout program.

## State model

State falls into four kinds:

| Kind | Written by | Examples |
|------|------------|----------|
| **Public options** `@airline-*` | users globally; palette files temporarily per session | configuration input, palette evaluation output, `@airline-cli` |
| **Private options** `@airline--*` | airline at runtime | committed config, signals, badges, selections, paths |
| **Composed output** | `render` | `status-left/right`, window formats, styles, pane borders, clock color |
| **Constants** | source code only | glyphs, chevrons, name template, vocabularies, precedence tables |

The classification is mechanical:

- A value is an option when something outside `render` writes it. A fixed value
  used only while rendering is a Bash constant.
- Public versus private is a contract boundary. Users may set `@airline-*` and may
  read the published `@airline-cli` bootstrap handle; all other airline-managed
  state, including the version, is read through the CLI.
- Private option names, tuple shapes, and other encodings are implementation details
  with no compatibility guarantee. Code that reads or writes `@airline--*` directly
  bypasses the public CLI contract; Airline may replace or clear that state without
  providing a migration path.
- Native tmux output is derived. Users configure the public inputs, not
  `status-left`, `window-status-format`, or the other rendered snapshots.

### Scope and inheritance

A user's `set -g @airline-*` supplies durable input. A configuration operation copies
each explicitly present value over the invoking session's private snapshot. Missing
global options do not fall back or restore anything: the committed session value stays
unchanged. Palette files use session-public options only as an evaluation surface;
airline captures and removes those values before committing them privately. Layout
declarations are collected in Bash and never enter the public option namespace.

Named palette and layout operations replace their complete axis and record provenance.
A manual palette-role patch clears the palette name; a manual segment patch clears the
layout name. Clearing the global input later does not recover the former named value;
the user selects that palette or layout again when they want its complete definition.

Private state exists at its native owner:

- status entries, health claims, and their projected badges are window-scoped;
- the problem ledger, origin claims, and projected problem badge are server-global;
- palette/layout selections, guards, paths, suspension, committed configuration,
  and adapter declarations are session-scoped.

### Apply and live updates

The private session snapshot is the render source of truth. `apply` copies explicit
global inputs over it, replays active adapters when colors may have changed, and calls
`render`. It does not rerun a layout script.

```mermaid
graph LR
    CFG[global user input] -- config operation --> S[private session snapshot]
    INIT[init / named use] --> S
    EVT[runtime signals] --> D[private runtime state]
    D -- project + redraw --> LIVE[live badge selectors]
    S -- render --> OUT[composed tmux options]
    OUT --> BAR[tmux status bar]
    LIVE --> BAR
```

The two update modes are deliberately different:

- Configuration changes move values that must be baked into the output. A direct
  `set -g @airline-*` stages a change; `apply` commits and renders it. Named `use`
  operations first consume pending global input, then replace and record their own
  axis. Thus a pending color followed by `layout use` clears palette provenance while
  still recording the selected layout.
- Runtime `status`, `health`, and `problem` changes update their collections,
  project a scalar badge value, and redraw. The already-composed selector follows
  the scalar, so no apply is needed.

`init` publishes `@airline-cli`, installs missing default palette and layout
selections behind a session sentinel, and renders. Re-running it does not overwrite
an existing session selection. A global `after-new-session` hook initializes future
sessions using an explicit session target. Because tmux has global defaults but no
session defaults for window options, an `after-new-window` hook copies the creating
session's committed palette roles directly into the new window's pane-border and
clock options without starting another Airline process.

`VERSION` is the sole release-version source. The read-only `airline version`
command returns its value; `scripts/release` derives the annotated Git tag from it;
and the tag-triggered GitHub workflow refuses to publish unless the tag is exactly
`v<VERSION>`. The workflow creates the GitHub release from that verified tag, so the
runtime contract, repository tag, and release name cannot be supplied independently.

### Render boundary

The status bar contains three kinds of value:

1. **Baked constants.** Palette colors, chrome, chevrons, styles, and adapter colors
   change only on `apply`.
2. **Live selectors.** Tmux `#{?…}` expressions select among baked colors for status,
   health, problem, zoom, copy mode, and activity. The choice is reevaluated by tmux;
   the branch colors were baked by airline.
3. **Live readings.** Plugin values such as CPU usage and tmux values such as the
   clock remain `#{…}` references and update on the normal status interval.

The rule is: **colors are baked; selectors and readings are live.** `apply` renders
only what must be baked.

Rendered output is written at its native tmux owner. Status bars, window-list
formats, and their styles are session options. Pane-border styles and clock color
are window options, so render updates every window in the target session and the
new-window hook initializes future windows. No palette-derived output is written to
tmux's global session or global window defaults. A tmux window linked into multiple
sessions remains one native window and therefore has one set of window-owned pane
and clock options; this is tmux ownership rather than Airline state leakage.

## Configuration kinds

There are seven catalog kinds and one plain-option kind:

| Kind | Representation | Lifecycle |
|------|----------------|-----------|
| **palette** | complete targetless tmux config containing public color options | `use` captures one file, replaces colors, records it, then renders |
| **adapter** | Bash snippet mapping `PALETTE` roles to plugin options | `use` or `load` executes it and records a replayable declaration |
| **layout** | Bash function declaring adapters and segment slots through a callback | `use` or `load` validates once, replaces that axis, records it, then renders |
| **classifier** | trusted shell mapping process termination to a condition | selected by `runner run` |
| **filter** | trusted shell interpreting a copied command-output stream | selected by `runner run` |
| **probe** | trusted shell performing one bounded observation | selected by `runner run` or `watch` |
| **runner** | named run/watch composition over those primitives | expanded for one invocation |
| **segment** | public `@airline-segment-<slot>` option | set directly or by a layout; not loadable |

Every catalog has an ordered registered search path. `list` lists resolvable
bare names and `register <dir>` prepends a trusted location. Palette, adapter, and
layout additionally provide `use`; classifier, filter, probe, and runner provide
`show <name>` for static metadata and the resolved path.

For palette, adapter, and layout:

- `register <dir>` prepends a trusted search location;
- `list` lists resolvable bare names, deduplicated in search order;
- `use <name>` accepts a bare name and resolves it only within registered paths.

`load <path>` is the explicit operation for executable adapter and layout files.
Both record an absolute path where replay requires one. Adapter declarations are
replayed on palette changes; layout programs are rerun only by an explicit layout
operation.

Palette and segment configuration need no `load` verb. A custom palette is registered
and selected by name; it must define every palette role. One-off manual changes use
global `@airline-*` options followed by `apply`.

Adapters, layouts, runner primitives, and runner compositions are ordinary trusted
shell. Registration and explicit adapter/layout loading are the trust boundaries.
Configuration operations are serialized per session with the `config` transaction
namespace. A layout must define `airline_layout_configure <declare-function>` and
remain quiet on stdout. Its callback accepts `segment <slot> <value>`, `adapter use
<name...>`, and `adapter load <path>`. Unknown and duplicate declarations fail the
operation; omitted segment slots are empty. Adapters are validated and applied before
the new private segment, adapter, and provenance state is committed.

A segment may reference a palette foreground role live, but must not set a
background. Render owns each block background and its matching chevrons; allowing a
slot to replace the background would break that seam.

## CLI contract

`airline.sh` is the public parser and dispatcher. Each successful command arm makes
exactly one implementation call; context resolution, sequencing, state access, and
rendering stay behind that boundary. The `airline` executable is only the installable
discovery shim that resolves the active `airline.sh` through `@airline-cli`.

### Grammar

```text
airline session init [-t <session>]
airline session apply
airline session show [state]
airline session suspend | resume | toggle
airline version
airline help [<noun> [<verb>]]

airline status   set <active|result|attention> [-t <pane>]
                 clear [-t <pane>]
                 show [-t <pane|window>]
airline health   set [-t <window>] <contributor> <health-key> <ok|warn|fail> [<message>...]
                 ack [-t <window>] <contributor> <health-key>
                 clear [-t <window>] <contributor> <health-key>
                 show [--all] [-t <window>] [<contributor> [<health-key>]]
airline problem  set [--pane <pane-id>] <contributor> <problem-key> <ok|warn|fail> [<message>...]
                 close [--pane <pane-id>|--session <session-id>] [<contributor> [<problem-key>]]
                 ack <contributor> <problem-key>
                 clear <contributor> <problem-key>
                 resolve <contributor> <problem-key>
                 show [--all] [<contributor> [<problem-key>]]
airline transaction show
                    clear <global|session|window> <target> <namespace>

airline palette  show [name|<palette-element>] | list | use <palette> | register <dir>
airline segment  show [<segment>]
airline adapter  show | list | use <adapter>... | load <file> | register <dir>
airline layout   show [name|path] | list | use <layout> | load <file> | register <dir>
airline classifier show <classifier> | list | register <dir>
airline filter     show <filter> | list | register <dir>
airline probe      show <probe> | list | register <dir>
airline runner   show <runner> [<arg>...] | list | register <dir>
                 run [--here|--pane [-h|-v]|--window] [<runner>] [--classify <classifier>]
                     [--filter <filter> [--merge-stderr]] [--probe <probe> [<arg>...]] -- <command>...
                 watch [--here|--pane [-h|-v]|--window] [<runner>] [--probe <probe> [<arg>...]]
```

All listed commands are public. Tmux hooks use those operations when the event has a
public meaning. Result observation is the narrow exception: Airline's hook invokes
the unlisted `status _observed-result <pane> <revision>` entry point because its
revision is private implementation state rather than caller input. Spawned runner
panes and windows re-enter through public `runner run/watch --here` commands;
process-local spawn context arms pane retention before validation without adding
public command grammar.

The process exit contract is binary: zero means a valid request completed,
including an idempotent no-op; any nonzero status means validation or operation
failed. Individual nonzero values are implementation details, not a caller-facing
error taxonomy.

The parser arms are also the grammar source. Explicit `help:begin` / `help:end`
markers delimit each noun without depending on function or `case` formatting;
colocated `#|` annotations contain usage and descriptions. `lib/help.sh` renders
those annotations directly. Semantic placeholders such as `<palette>`, `<layout>`,
`<file>`, and `<window>` are part of that contract: they tell completion generation
which catalog or shell primitive supplies a value.

Bash and Zsh completions are compiled from the rendered help by
`scripts/generate-completions`; they do not add a runtime inspection API or parse
`airline.sh` independently. `make completions` updates the committed artifacts,
and `make check-completions` rejects drift. `make install` performs that check and
installs both artifacts with the PATH shim.

### Conventions

- `apply` is whole-system because there is one render over the complete source of
  truth. There are no per-noun apply commands.
- `set`, `ack`, and `clear` belong to dynamic signal nouns. Static palette elements
  and segment slots are written with `set -g @airline-*` and removed with `set -gu`.
- Stateful nouns use bare `show` for a labeled human summary and qualified fields
  for raw scripting reads. Catalog-only classifier, filter, probe, and runner use
  `show <name>` to describe one resolvable implementation.
- `palette show name` and `layout show name` expose their active selection. Layout
  also exposes its resolved path.
- `adapter show` lists the active adapter set, one name per line. `list` is a
  separate catalog of what could be selected.
- Runner elements compose only for one invocation. A leading bare runner name
  expands a catalogued composition; an option-leading invocation remains ad hoc.
  Named compositions contain monitoring configuration but never the command.
  `run` defaults to classifier `basic`; `watch` requires a probe. `--here` is the
  explicit placement default, while `--pane` and `--window` create tmux topology
  through the common runner core. Pane placement accepts tmux's native `-h` and
  `-v` orientation modifiers; omitting one preserves tmux's default split.
- Status mutation targets a pane, status inspection accepts a pane or window, and
  health targets a window. Health places `-t <window>` before its keyed tuple so
  every trailing message word is opaque. Problems are globally visible.
  Health and problem take contributor and claim as separate identity fields.
  `problem set` attributes a claim to the current session unless `--pane` supplies
  a pane origin; lifecycle hooks close claims for destroyed origins. Health and
  problem require a user-facing message for `warn` and `fail`; `ok` is message-free
  reporter recovery. For health it removes the condition; for problem it removes
  one origin claim and records `resolved` history when the final claim recovers.
- Session state is the active/suspended axis. Suspension derives a muted palette and
  traps the prefix; airline itself installs no key binding. `session show state`
  returns its raw scripting value.

Static options deliberately retain normal tmux behavior: changing a value at
runtime requires `set -g …` followed by `apply`, and an unknown option name is not
validated. This keeps configuration readable and composable with tmux instead of
adding a parallel configuration API.

## Process runner

The runner is airline's floor for non-interactive lifecycles. Interactive programs
such as coding agents expose richer lifecycle callbacks and should call the public
`status` and `health` API directly; wrapping them in a runner would discard useful
information only to reconstruct it. Airline can either launch a process with `run`
or own a probe-only observation lifecycle with `watch`. The latter makes a remote,
independently managed service observable without inventing a null local job.

The runner separates fixed mechanics from program-specific interpretation:

| Owner | Responsibility |
|-------|----------------|
| **airline core** | select placement, own the run/watch lifecycle, preserve command I/O, retain spawned panes/windows, maintain contributor identity, validate observations, project status/health, and return a run child's exit status |
| **runner elements** | independently classify termination, interpret a stream, or probe external state |
| **command** | when using `run`, perform the work and explain itself through its normal terminal output |

Classifier, filter, and probe are first-class catalogs. Each implementation carries
a one-line summary; probes also declare their argument usage. `show <name>` exposes
that metadata and its resolved path without running an observation.

A runner catalog entry is syntactic composition over those primitives:

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

Both functions call core-owned callbacks; stdout is not a protocol. Metadata accepts
exactly one `summary` and one `usage`. Configuration accepts at most one each of
`classify`, `filter`, and `probe`; the callback preserves probe argument boundaries
and validates every declaration. Arguments following a named runner are
passed to `airline_runner_configure`, allowing definitions to supply useful defaults
or accept replacements.

```bash
"$configure" classify <name>
"$configure" filter <name> [merge-stderr]
"$configure" probe <name> [<arg>...]
```

The result is one complete monitoring composition. `run` consumes classifier,
filter, and probe; `watch` projects the probe and fails when none was configured.
Placement belongs exclusively to the `run`/`watch` invocation and is never part of
a catalog entry. There is no runner mode declaration or separate watcher protocol. The
catalog stores monitoring policy only: commands, working directories, environment
setup, scheduling, retries, and restart policy do not belong in a runner definition.

```sh
airline runner run tap -- bats --formatter tap test/
airline runner watch http http://localhost/health
```

There is no active runner selection. A named definition configures one invocation
and then uses exactly the same validation and lifecycle path as inline composition.

Airline does not prepare or rewrite the command and does not describe its result.
An executable that cannot launch already writes the authoritative error and exits
nonzero; a program such as a test suite already produces a richer explanation than
airline could. In the current pane that output remains in the shell's terminal. A
new pane or window is retained after completion so its output and tmux's native dead
pane status remain available until the user dismisses it. Retention is common
launcher policy, not an implementation hook.

### Classification

Every run has one terminal classifier; `basic` is implicit unless another is named.
It receives objective termination
facts (exit status and terminating signal) once and returns exactly one validated
condition: `ok`, `warn`, or `fail`. The shipped `basic` classifier maps exit zero to
`ok` and every nonzero exit or signal to `fail`. A program-specific implementation
exists only where that program assigns richer meaning to termination, such as a
dedicated exit code for "no tests collected" that should be `warn` rather than
`fail`.

Airline owns lifecycle status. Runner elements remain tmux-independent and report
normalized observations that core projects onto health:

| Process state | Classifier result | Runner status | Classifier health |
|---------------|-------------------|---------------|-------------------|
| running | not yet observed | `active` | clear |
| exited | `ok` | `result` | clear |
| exited | `warn` | `result` | `warn` + diagnostic |
| exited | `fail` | `result` | `fail` + diagnostic |

The classifier is terminal and one-shot. It does not launch processes, mutate tmux,
or write airline signals. It supplies the user-facing diagnostic for a retained
`warn` or `fail` condition. Airline returns the child's original exit status rather
than replacing it with the classification.
The concrete trusted-shell contract is:

```bash
AIRLINE_CLASSIFIER_SUMMARY='Interpret this program termination'

airline_runner_classify() { # <exit-status> <signal>
  # Print `ok` or `<warn|fail><TAB><message>`.
}
```

### Live observation

A long-lived process may become unhealthy and later repair itself without exiting.
One run invocation may additionally select a filter, a probe, or both. Each reports
current state as `ok`, or as `warn`/`fail` with a diagnostic message, while the
process remains active. Reports are state, not transitions: repeated observations
are safe, and a later `ok` clears that observer's health claim after recovery.

Airline owns the observation lifecycle and validates and projects each value, but it
does not know what a Kubernetes readiness state, server log message, or recovery
event means. The implementation owns domain interpretation; core supplies only the
small mechanics that are common across implementations.

A filter reads a tee'd copy of stdout by default. `--merge-stderr` applies ordinary
`2>&1` semantics before the tee. The filter consumes through EOF and calls the
supplied reporter when its interpretation changes. It must report at least once,
and its final call must describe the completed stream:

```bash
AIRLINE_FILTER_SUMMARY='Interpret this command output'

airline_runner_filter() { # <pid> <report-function>
  local pid="$1" report="$2"
  while IFS= read -r line; do
    # Interpret line, then call either:
    # "$report" ok
    # "$report" warn|fail "diagnostic message"
  done
  # Finish with `ok`, or `warn|fail "diagnostic message"`.
}
```

Airline rejects a filter that exits without a report. The filter contributor is
cleared when the next run starts, updated by progressive reports, and retained after
EOF. It therefore preserves stream evidence that may be richer than, or independent
of, the classifier's interpretation of the process exit. Classifier and filter use
separate contributors; neither overwrites the other. Both remain subordinate to the
single runner-owned status lifecycle.

A probe is justified when a bounded API or state query provides current information
that the process does not write to its selected output streams. The implementation
defines one observation; airline invokes it sequentially at the declared interval,
never overlaps calls, and stops the loop when the child exits or a watcher is
interrupted:

```bash
AIRLINE_RUNNER_PROBE_INTERVAL=5
AIRLINE_PROBE_SUMMARY='Query current service health'
AIRLINE_PROBE_USAGE='<endpoint> [<endpoint>...]'

airline_runner_probe() { # <lifecycle-pid> <report-function> [<arg>...]
  local pid="$1" report="$2"
  # Perform one bounded query, write user-facing evidence to stdout, and call:
  # "$report" ok
  # "$report" warn|fail "diagnostic message"
}
```

The probe must bound its own I/O. Airline supplies no persistence, retries beyond
the next scheduled observation, restart policy, or general job management. A
nonzero probe exit, no reporter calls, or an invalid reported value is an integration
problem; a valid later result clears it. Airline reduces multiple reports from one
invocation to their worst condition and retains an opaque diagnostic reported at
that severity. Probe stdout is an uninterpreted human channel:
airline passes it to the pane and assigns no meaning to its format. During `run` it
bypasses the command-output tee, so a selected filter cannot observe it. During
`watch` it is the visible polling transcript. Filter and probe use independent
health claims. Probe health has a different lifetime from filter health: it
asserts only the most recent bounded observation while probing is active. Airline
clears that claim when the run or watch lifecycle stops because it can no
longer claim the observation is current.

`runner watch` owns a probe lifecycle without launching a command:

```sh
airline runner watch --probe http http://localhost/health
airline runner watch --window --probe http endpoint1 endpoint2
```

Its status remains `active` until interruption, then clears; there is no fabricated
terminal result to classify. The probe's first argument is the local airline watcher
PID, useful only as lifecycle identity—it is not the remote service PID. Probe
arguments continue to end-of-argv for `watch`; only `run` needs `--` to separate its
command. `--here` explicitly spells the default placement. A plugin
that already owns richer scheduling or callbacks may still drive the public health
API directly; that is an alternative integration shape, not a remote/local boundary.

Finite jobs normally need only classification, though a test protocol can use a
filter to expose failures before the suite exits and retain its terminal stream
diagnostic afterward. The shipped `tap` filter observes top-level TAP output: an
ordinary `not ok` warns while the suite can continue, completion with a failure or
`Bail out!` fails, and a clean completed stream reports `ok`. TODO/SKIP failures are
ignored.
Servers launched by `run` may use a filter, a probe, or both before classification
at eventual exit. Remote services may use a probe-only watch. The shipped `http`
probe accepts one or more endpoints, writes the condition, HTTP status, and endpoint
for each check, reports `ok` for each 2xx response and `fail` otherwise through its
callback, and leaves their worst-case reduction to airline. Its stdout format is a
shipped convention, not a core protocol.

A command failure, including an unavailable executable, is a job result and is not
an airline problem. Airline does not copy command diagnostics into problems.

## Collections and badge projection

Status holds one pane-owned entry and health holds contributor-owned claims per window.
Problem uses a server-global lifecycle ledger plus a server-global set of active
origin claims.
Each collection uses an explicit registry and a tuple per member:

```text
@airline--<namespace>       space-delimited member registry
@airline--<namespace>-<key> tab-delimited fixed-arity tuple
```

Collection rules:

- Every operation has one scope-first form, such as
  `coll_reduce <global|session|window> <owner> <namespace> <order>`. There are no
  scope-specific collection functions. The collection layer passes scope through
  mechanically and does not decide which domain belongs at which scope. Owner
  tuples have one canonical representation: `(global, server)`, `(session, id)`,
  or `(window, id)`.
- Membership is explicit; entries are never discovered by parsing option names.
- `set` writes the entire tuple and registers the key. `unregister` also removes the
  tuple.
- Public identity fields are opaque and cannot contain whitespace or `:`. Status is
  identified by pane and its window collection tuples hold
  `<level>\t<pane-revision>`. Its monotonic counter is a pane-scoped private scalar,
  so it survives status deletion and follows a pane moved between windows. Health tuples hold
  `<badge|none>\t<active|acknowledged>\t<level>\t<message>`. Problem ledger tuples
  hold
  `<badge|none>\t<active|acknowledged|closed|resolved>\t<last-level>\t<last-message>`;
  active claim tuples hold
  `<contributor>\t<key>\t<pane|session>\t<origin>\t<level>\t<message>`. Health and
  problem use a private composite collection member derived from contributor and key.
  Diagnostic messages may contain spaces but not tabs.
- Storage is never rendered directly. A domain-specific caller reduces the
  collection and projects the result to `badge-status`, `badge-health`, or
  `badge-problem`.
- Reduction receives its ranking as data, keeping `lib/collections.sh` free of status,
  health, and problem semantics.

Health and problem share the ladder `ok < warn < fail`. `ok` or absence is normal
and invisible; `warn` maps to `alert`; `fail` maps to `stress`. Every retained
condition includes a diagnostic message. Messages are opaque user-facing payload:
Airline validates framing, stores and shows the text, but assigns it no meaning.
Reporters and classifier/filter/probe implementations own the diagnostic content.

### Signal lifecycle boundary

Signal meaning, identity, and state transitions are defined in
[Signal lifecycles](docs/lifecycle-signals.md). This document retains only the
architectural consequences: status is keyed by pane within a window, health is keyed by
contributor and claim within a window, and problem is keyed by contributor and claim
globally while retaining pane or session origins.

All three signals use one orchestration path: resolve the native owner, enter its
transaction, apply domain lifecycle policy, reduce/project the collection, and
redraw only when presentation changed. The common path does not make their lifecycle
policies interchangeable.

Dynamic collection operations run in owner-scoped transactions: status and health
serialize by `(window, namespace)`, while problems serialize by the single
`(global, server, problem)` owner. The registry, member tuple, reduction, and
projected badge therefore form one logical mutation even when background
evaluations overlap.
Status revision changes are staged in the same window transaction as the pane's
collection tuple. Setting `result` installs Airline's observation hook; contributors
do not handle its tokens. The hook invokes the private `_observed-result` process
entry point with `(pane, revision)`, which deletes only an exact current result and
prevents delayed focus cleanup from clearing newer pane state.
`lib/tmux.sh` owns acquisition, an atomic owner-scoped marker, cleanup, stale-owner
detection, and recovery. Transaction callbacks run in a subshell so transaction-local
signal traps do not alter caller traps. `airline transaction show` exposes
outstanding markers, and `transaction clear` releases only a marker whose recorded
process is no longer alive. This diagnostic API is deliberately separate from problems, avoiding a
circular dependency when the problem transaction itself is stuck. Identical problem
sets and absent clears skip both storage writes and redraws. Widgets may report their
current capability on every evaluation so stale semantic observations converge.

Status and health are distinguished by position around the window name, so sharing
palette roles is safe.

## Mechanical boundary

`lib/tmux.sh` is the sole integration point with tmux. Its interface follows these
conventions:

- Functions use fixed positional arguments. The generic collection bridge takes
  scope and canonical owner first; `tmux.sh` validates that tuple and translates it
  to tmux flags in one place. In particular, `(global, server)` maps to `-g` without
  inventing an empty owner. Scalar domain accessors may express their fixed owner in
  names such as `prv_set_window`.
- Getters write to stdout, predicates use exit status, and mutators are silent.
- Session-, window-, and pane-scoped functions take explicit targets. Callers resolve an
  omitted target once and pass the resulting id downward.
- `opt_*` handles native option mechanics; `pub_*` and `prv_*` add airline namespace
  policy; standalone wrappers cover redraw, session-targeted palette sourcing,
  target resolution, hooks, and runner pane/window placement.
- `setif` uses ordinary success/failure status and writes changed-versus-unchanged to
  a caller-selected Bash variable. Orchestration accumulates that private result and
  redraws once only when rendered output changed; a successful no-op cannot mask or
  resemble a failed tmux mutation.

Owner-scoped transactions execute option work against a mutable in-memory
workspace. After acquiring the lock, `tmux.sh` bulk-loads the global option tables
and the transaction owner's session or window table. Additional native owners, such
as the panes holding status revisions or windows receiving one session's rendered
styles, are loaded lazily on first access. Existing scalar accessors read and update that desired snapshot with
read-your-writes behavior; presence is tracked separately so unset and explicitly
empty remain distinct. At the end, the mechanical layer compares desired state with
the baseline and submits the ordered final writes as one tmux command sequence.
Domain modules neither build batches nor pass option maps through their APIs.

Transaction means serialized, coherent option work rather than database rollback.
The callback has read-your-writes behavior, changed options are submitted in order,
redraw follows the writes, and the owner lock is released on return or a trapped
termination. Staged writes are still flushed when a callback returns nonzero: this
preserves failure diagnostics and cleanup around palette evaluation. In particular,
`source-file` is an external workspace boundary and trusted executable definitions
or adapters may have effects that cannot be reversed. Public operations therefore
validate declarations before domain commit and report a failed capability, but do
not promise to undo every effect of a trusted executable that fails while applying.

Commands whose effects are not ordinary option mutations are explicit workspace
boundaries. `source-file` flushes pending writes and reloads the snapshot before
evaluation continues. Redraw is deferred until changed writes have reached tmux.
Transaction lock acquisition and release remain immediate and outside the option
workspace. Actual process environment variables are not used as the state model:
option names and values are arbitrary data, empty and absent differ, and state must
not leak to child processes.

Public accessors support global defaults and effective session reads. Private
accessors support global, session, and window ownership, plus `prv_name` for
embedding a private scalar in a tmux format. Global private state is reserved for
data whose native owner really is the tmux server, currently the problem ledger,
origin claims, badge, and transaction marker.

## Enforcement and testing

`test/architecture.bats` enforces three build-time rules:

- **A — tmux ownership:** only `lib/tmux.sh` invokes the `tmux` binary inside the
  application. The external PATH shim, test shims, and inert tmux configuration are
  explicit exclusions.
- **B — namespace ownership:** only `lib/tmux.sh` constructs literal `@airline-` and
  `@airline--` names in shell code. Palette and segment configuration spell public
  names because those names are the external contract.
- **D — module boundaries:** a function whose name begins with `_` may be referenced
  only by the module that defines it. Calls to public functions must point to a
  strictly lower architectural layer (apart from shared `command` helpers). The lint
  derives ownership from function definitions, so palette and adapter helpers may
  retain useful primitive names without filename-prefix ceremony and does not need
  an exact edge allowlist.

CLI grammar shape, exactly-once delegation, argument preservation, help generation,
and completion drift are behavior tested by the CLI suites rather than labeled as
architecture rules.

The same boundary makes most tests cheap:

| Suite | Backend | Responsibility |
|-------|---------|----------------|
| `core/tmux.bats` | real tmux | pins the mechanical contract that the fake must match |
| `core/collections.bats` | in-memory fake | collection storage and reduction |
| `core/catalog.bats` | in-memory fake | path priority, resolution, listing, and registration |
| `core/render.bats` | in-memory fake | observable composition and projection behavior |
| `runner/behavior.bats` | in-memory fake | runner element contracts and mechanics |
| `runner/integration.bats` | real tmux subprocess | runner process and topology integration |
| `layout/integration.bats` | real tmux subprocess | executable layout and primitive integration |
| `signal/behavior.bats` | in-memory fake | status, health, problems, observation boundaries, and redraw gating |
| `signal/integration.bats` | real tmux subprocess | signal targeting, projection, and observation hooks |
| `session/behavior.bats` | in-memory fake | session initialization and active/suspended state |
| `session/integration.bats` | real tmux subprocess | session integration requiring tmux semantics |
| `transaction/behavior.bats` | function stubs | diagnostic validation and error translation |
| `transaction/integration.bats` | real tmux subprocess | public transaction inspection and recovery errors |
| `cli/grammar.bats` | sourced CLI with spies | grammar and exactly-once delegation behavior |
| `cli/completions.bats` | generated shell artifacts | help/compiler drift, typed completion, and shell syntax |
| `cli/wrapper.bats` | real tmux subprocess | installed launcher discovery and delegation |
| `architecture.bats` | static inspection | layering invariants |

`test/support/fake-tmux.sh` sources the real mechanical wrappers and replaces only their
leaf store operations and standalone tmux verbs. It models option scope, absence,
overwrite, removal, and preservation of spaces; it does not evaluate tmux formats.
`make test-fast` selects the static and fake-backed suites; `make test-integration`
selects the real-tmux suites. The domain targets `test-layout`, `test-session`,
`test-signal`, `test-transaction`, and `test-runner` pair fast behavior with
integration only where that domain needs it.

Fast suites keep validation, reduction, and boundary cases narrow. Real-tmux suites
prefer wider domain workflows: one isolated Airline initialization should prove a
related sequence of public behaviors, rather than paying the bootstrap cost once per
assertion. Runner process and topology cases remain isolated where process lifetime is
itself the behavior under test.

## Lessons from failed approaches

These are retained because they explain constraints that are otherwise tempting to
remove.

### Two composition paths diverged

The former `main()` and `_airline_rebuild` paths each assembled part of the bar. A
palette change exercised only one path, so it repainted the bar incompletely. The
replacement is one `render` function over the whole source of truth, reached through
`apply`. Runtime signals may redraw live selectors but never compose output.

### Rendering collection storage coupled display to tuple shape

Referencing a collection tuple directly from a tmux format made the display depend
on the storage tuple's arity. Adding metadata to a tuple could
therefore change the value seen by the renderer. Collections now reduce into a
separate scalar badge option, and render references only that stable projection.

### Bats `run` hid mutations made against the fake

The in-memory fake lives in the test process, while Bats `run` executes its command
in a subshell. A mutation inside `run` disappears before the following assertion,
although the equivalent operation against a real tmux server persists externally.
Tests that mutate and then inspect fake state must call the function directly and
capture its status with `|| rc=$?`.

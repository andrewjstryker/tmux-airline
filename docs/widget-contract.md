# Widget contract

Status: implemented. Public session-scoped palette options, widget-owned tmux format
strings, and ordered composition are the contract. CPU established the runtime slice;
battery, online, and prefix use it. See [widgets](widgets.md) for authoring, helper
names, budgets, platform support, and migration examples.

## Ownership

A widget produces a tmux format fragment. It chooses its text, glyphs, thresholds,
colors, conditions, and any commands required to obtain observations. Airline does
not interpret a widget's presentation as semantic spans or prescribe how it uses the
palette. Native formats and `#()` jobs may coexist in the same fragment.

A layout places and orders fragments. Render owns segment geometry: outer padding,
the baseline style, and separators between segment backgrounds. It establishes the
segment baseline before each fragment and restores it afterward, including before
padding and chevrons. Widgets can style their own content, including local highlights,
without leaking foreground, background, or attributes into neighboring widgets.
Content fragments must not change status-line alignment, list/range structure, or
other layout-level directives.

Widgets are trusted catalog entries, like layouts and runner elements. Format
validation catches contract errors; it is not a sandbox for hostile shell or tmux
expressions. No widget depends on a TPM startup rewriter or an exported replacement
for the `tmux` command.

## Public session palette

The existing role names become stable public session options:

```tmux
#{@airline-primary}
#{@airline-secondary}
#{@airline-alert}
#{@airline-inner-bg}
```

All palette roles are covered, including positional backgrounds and signal colors.
Values are tmux color specifications, not style directives. Airline publishes a
complete palette on each initialized session; widgets never reference private
`@airline--config-*` names. In a status format, tmux resolves the options in the
rendering session's context. A widget needs no CLI or subprocess to read colors.

For example, a widget may return:

```tmux
#[fg=#{@airline-active}]#{?client_prefix,PREFIX,}
```

These options describe the **effective display palette**. Palette selection and
suspend/resume update them and request a redraw. Suspension may retain a private
unsuspended restoration snapshot, but there is no second palette API for widgets.
Normal rendering and widget rendering use the same effective colors. Changing a
palette must not require regenerating widget formats or resampling hardware merely
to select a different color.

Palette commands validate and publish session values. Global palette values, if
retained as user defaults, are initialization input; they are not a second live widget
palette and cannot override a fully initialized session through inheritance. Palette
files need an isolated evaluation surface before publication, rather than temporarily
writing into the live public palette. Private selection/provenance and staging state
may remain private.

Migration must define manual option writes and `session apply` alongside this public
surface, especially while suspended: effective dimmed colors must never accidentally
become the saved unsuspended palette. Public read access does not imply that raw tmux
writes perform validation, update palette provenance, or request Airline lifecycle work.
Document that distinction with the CLI changes.

## Definition and return value

A widget uses the existing catalog header metadata and supplies a format function:

```bash
#!/usr/bin/env bash
#| summary: Highlight the active prefix
#| usage:

airline_widget_format() {
  (( $# == 0 )) || return 2
  printf '%s\n' '#[fg=#{@airline-active}]#{?client_prefix,PREFIX,}'
}
```

Airline resolves the definition, sources it in an isolated process, and invokes
`airline_widget_format [arguments...]`. Arguments retain their boundaries. The
function receives explicit canonical session and widget-instance identities through
host-provided context; it must not infer ownership from the current client or pane.
The context variables are `AIRLINE_WIDGET_SESSION` and `AIRLINE_WIDGET_INSTANCE`.
Optional observation workers also receive `AIRLINE_WIDGET_STATE_DIR`.

A successful call returns one tmux format string on stdout and status 0. One trailing
newline is permitted; an empty string is valid. There are no value/pending/unavailable
span callbacks, mandatory role tags, or separate native/sampled output modes.
Diagnostics go to stderr. A nonzero return rejects the candidate definition rather
than inserting its output in the bar. Multiline output and terminal control sequences
are invalid; native tmux syntax, Unicode, style directives, and `#()` are intentional
format content and must not be escaped as plain text by core.

Format construction parses options and constructs expressions, but does not sample
CPU, ping a host, wait for a device, start a persistent worker, or mutate tmux state.
Source-time code follows the same rule. Widgets escape literal data and quote any shell
commands they embed; Airline must provide reusable quoting/context helpers for jobs
it generates. Do not run the format through a shell `eval`.

A widget may expose a separate cheap availability check. Required unavailability
rejects a layout; optional unavailability omits only that widget. Unknown catalog
names, bad arguments, and malformed output remain errors even for optional placement.
`airline_widget_available [arguments...]` returns 0 for available and 3 for
unavailable, without stdout. Format validation runs first; other failures reject
even optional placements.

Widgets may declare `options` and `default-<option>` metadata to opt into persistent
policy. Precedence is placement arguments, nonempty global
`@airline-widget-<catalog-name>-<option>` values, then metadata defaults. Each declared
option takes one value. Session options are not policy input. Widgets without this
metadata retain their existing argument contract.

The host resolves one argument vector before format evaluation and saves it with
the instance. Format and availability checks validate that vector; observations
receive the same captured arguments. Global changes take effect on the next layout
load, not on palette changes or `session apply`. Invalid effective policy rejects the
candidate layout. Inspection reports current effective arguments without modifying
existing instances. See [widget policy](widgets.md#persistent-defaults-and-placement-overrides)
for supported options, validation, reload semantics, and authoring details.

## Multiple widgets per segment

A segment is an ordered list of fragments, each either literal tmux content or the
format returned by a widget. Repeated declarations append to that slot rather than
replace it or count as duplicate-slot errors. Layout grammar:

```bash
"$declare" segment left-out '#S'
"$declare" widget right-mid cpu --warn 70 --critical 90
"$declare" segment right-mid ' | '
"$declare" widget right-mid online
"$declare" segment right-out '%Y-%m-%d %H:%M '
"$declare" widget-optional right-out battery
```

Ordering follows declaration order within each slot; the existing slot order still
places segments on the bar. Widget argument lists end at each callback invocation,
so no new delimiter or placeholder language is needed. Repeating a widget is valid,
including different arguments in the same segment. Whitespace between fragments is
explicit layout content; core does not insert separators between widgets.

Render composes one segment from these returned strings. It adds outer padding and
chevrons once per segment, not once per widget. Optional omissions do not remove
neighboring content. A segment with no configured content is omitted. A live expression
that later evaluates to empty does not dynamically remove/reflow its whole segment;
that is separate from composing multiple widgets.

Each active instance is identified by server, session, slot, and fragment position,
with a configuration generation for replacement. Sampling state, jobs, and problem
claims must distinguish two widgets in the same segment. A late result from an old
instance cannot publish into its replacement. Palette changes do not replace widget
identity or measurement baselines.

## Runtime and tmux evaluation

Tmux evaluates returned formats through its normal rendering path. Native expressions
need no worker. External observations may use `#()` and Airline CLI/runtime services;
`widget run -t <session-target> <instance>` refreshes a registered instance
with explicit ownership. Do not change tmux syntax or recreate a global startup-interpolation
pass. Do not add CLI calls for palette lookup.

Use tmux's asynchronous command/output behavior deliberately. A widget interval, if
supported, must be enforced by its runtime/cache path; a metadata number alone cannot
create a per-job timer. Refresh behavior is constrained by status redraw cadence.
A CPU sampling path must bound work, avoid overlapping observations for one instance,
and maintain its counter baseline without holding a session configuration lock.
The optional hosted runtime caches a scalar reading; widgets choose their own
fallback glyphs and keep presentation in the format.

Palette references must be in a format that tmux actually evaluates. Do not assume
text returned by a `#()` job is recursively expanded as another format. A widget may
put live palette styles outside a data job or use native selectors over its runtime
readings. The CPU slice must verify its chosen mechanism with real tmux, including a
palette change with unchanged observations. Widgets own any presentation caching they
introduce; cached concrete colors cannot defeat the public palette's live behavior.

Widgets own normal warm-up, unavailable-data presentation, and reading thresholds.
High CPU utilization is a valid reading, not automatically an operational problem.
Use Airline's existing CLI/problem services for failed advertised capabilities; do
not turn stderr into bar content. Core owns failures of runtime mechanisms it hosts,
such as invocation and timeout enforcement. Widget-owned claims and host-owned claims
must remain distinct. Removal retires the relevant instance's jobs, state, and claims
without clearing a neighboring widget's problem. The optional runtime publishes `?` on failure and reports an instance-specific
`airline-widget` problem. Its successful next sample recovers that claim; retirement
closes it after outstanding bounded work ends.

## Catalog, inspection, and migration

Replace `adapter` with `widget`; do not keep an alias for incompatible behavior.
Reuse catalog discovery: `widget list`, `widget register <dir>`, and
`widget describe <name> [arguments...]`. Layout declarations activate widgets;
standalone activation without placement is unnecessary. Custom widgets are selected
from registered paths, including when the containing layout is loaded by path.

`list` reads metadata only. `describe` may evaluate format construction and cheap
availability checks, but never runs embedded jobs, samples data, creates caches, or
changes problems. It reports the returned format literally, preserving public palette
references and native tmux expressions. Layout inspection preserves every fragment's
order, source, and arguments instead of flattening them beyond recognition.

Retire adapter declarations with a clear migration diagnostic. Replace the old
private-palette/global-input model with the public session palette consistently across
rendering, palette evaluation, CLI help, and inspection. Update completions and shipped
layouts when the grammar changes. The adapter implementation and TPM capability helper are removed. No startup
compatibility machinery from the bug branch is needed.

## CPU acceptance gate

Implement CPU first, using a native counter reader initially on Linux. Report CPU
utilization from counter deltas rather than load average. Document idle, iowait, guest
counter treatment, resets, and zero elapsed time before implementing arithmetic.
The first observation establishes a baseline; the widget chooses an honest warm-up
display instead of inventing 0%.

Tests must prove:

1. Format return validation, argv preservation, required/optional availability, and
   inspection without executing jobs or collecting observations.
2. Correct counter arithmetic, threshold presentation, warm-up, resets, and failures
   with deterministic fixtures. No TPM plugin installation or color globals needed.
3. Public palette references resolve in real tmux styles, separately for two sessions;
   palette changes and suspend/resume update colors without another CPU observation.
4. CPU shares a segment with another widget and literal content in the specified order.
   Repeated instances keep separate arguments/state, and styles do not bleed between
   fragments or into segment padding and separators.
5. The chosen runtime path handles bounded execution, pacing, concurrent requests,
   stale results, failure reporting/recovery, layout replacement, and session cleanup.
6. TPM initialization before or after Airline has no effect on widget resolution;
   Airline leaves unrelated global status/plugin options unchanged.

The CPU gate preceded the other widgets. Empty-segment decoding and bounded tmux
write batches are mechanical rendering fixes included with this implementation.

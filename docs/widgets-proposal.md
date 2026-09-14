# Proposal: replace adapters with a widget catalog

Status: historical rationale for the implemented widget contract. The current API is documented in
[catalogs and discovery](catalogs.md) and [layout inspection](layouts.md).
The discussion below records the architectural motivation.

The [widget contract](widget-contract.md) records the current design: public
session-scoped palette options, widget-owned tmux format strings, and ordered
composition of multiple widgets within a segment. It replaces the earlier
semantic-output and one-widget-per-slot drafts. CPU established the runtime contract; battery, online, and prefix now use it.
See [widgets](widgets.md) for the implemented API and runtime.

## The mismatch

An adapter assumes a TPM status plugin is a widget that Airline can configure. It is
not. A TPM status plugin is a one-shot rewriter of the global status strings, and the
three consequences below are structural, not defects in any particular adapter.

**Interpolation is a startup event on a global string.** `cpu.tmux` reads the global
`status-right`, textually replaces `#{cpu_icon}` with `#(…/scripts/cpu_icon.sh)`,
writes the global back, and exits. It runs once, at TPM startup, against whatever the
global held at that moment. Airline composes *session-scoped* `status-left` and
`status-right` and recomposes them on every palette, layout, apply, suspend, and
resume operation. A placeholder Airline writes after startup is never interpolated;
a placeholder present at startup is interpolated into a global Airline does not use.
Both systems want to own the same string and only one of them can.

**Plugin configuration is read from global scope.** Plugin scripts resolve settings
with `tmux show-option -gqv @cpu_low_fg_color`, unconditionally global. Airline's
palette is session state and two sessions may hold different palettes, so nothing an
adapter writes into session scope is visible to the script it configures.

**The division of labour is inverted.** An adapter pushes palette colours out and
lets the plugin decide presentation. Airline is then blind to what the block
contains, what it costs to refresh, and whether it will honour the rule that render
owns each block background. The information Airline needs is split across two
declarations in the layout that must agree by hand: a segment string holding the
placeholder, and an adapter name. `adaptive` demonstrates the coupling — every
`installed` branch must remember to add both.

The `battery` adapter shows how far the inversion goes. Forty of its lines push
Airline's own glyph ramp and colour ladder into `@batt_icon_charge_tier*` and
`@batt_color_charge_primary_tier*` so that the plugin will pick among values Airline
chose. That presentation policy belongs in an Airline widget, which can reference the
session palette directly instead of sending settings through a third party.

## What the evidence on `bug/layout-rendering` shows

That branch makes the adapter approach work, and its cost is the measure of the
mismatch. It adds an `adapter-formats` collection of translations substituted into
composed status strings after composition; it reimplements the plugins'
interpolation step inside render; and it adds `scripts/plugin-command`, which exports
a Bash function into plugin child processes to redirect their untargeted
`show-option -gqv` reads to the owning session. That last piece is a process-level
shim around a third party's option reads, and its own documentation records that it
does not cover `command tmux` or a non-Bash child shell.

Each of those is a correct fix for the adapter design. Together they are the signal
to question the design rather than extend it. The remaining entry in that branch's
TODO — `_opt_decode` mishandling tmux's single-quoted empty values — is a genuine
mechanical-layer bug in the dependency-free layouts and is independent of this
proposal. It should be fixed on its own terms.

## Widget as a catalog kind

The governing analogy is one the runner catalog already established:

> probe is to runner as widget is to layout.

A probe supplies observations to a runner; a widget supplies a tmux format to a
layout. Both use trusted catalog discovery, but widgets do not inherit the probe's
reporting protocol or require an observation process. A native widget may consist
entirely of tmux conditions. A dynamic widget may include `#()` in the same format.

Widgets return a tmux format fragment. Airline establishes the segment's `fg` and
`bg` before evaluating the fragment and passes those values to its format function.
If a fragment changes either color, it must restore the exact supplied values before
it ends; Airline does not repair a broken fragment. Palette roles are public session
options named `@airline-palette-<role>`.

A layout places widgets directly and can append several fragments to a slot:

```bash
"$declare" widget right-mid cpu
"$declare" segment right-mid ' | '
"$declare" widget right-mid online
```

Each declaration contributes one ordered fragment. A segment receives outer padding
and separators once, regardless of the number of widgets inside it. Optional
availability omits only the unavailable widget. The contract defines instance identity
per fragment rather than assuming one widget per slot.

## Where TPM plugins end up

A widget stops adapting a plugin and becomes an Airline element with a flat catalog
shape: `<name>.sh` defines the format and an optional extensionless sibling `<name>`
emits runtime data. The runtime is a stateless, quick scalar command evaluated by
tmux's normal status refresh. Airline does not invoke plugin entry points or provide
a widget scheduler, cache, lock, timeout, or evaluation command. A plugin may remain
an external data source only when its command can meet that runtime contract.

The plugin scripts divide cleanly when they can meet that contract:

- `battery_percentage.sh` reads no tmux options at all. It is a pure data source.
- `cpu_percentage.sh` reads one option, `@cpu_percentage_format`, a printf format
  rather than a colour policy.
- `cpu_fg_color.sh`, `battery_color_charge.sh`, and their siblings exist only to read
  the `@…_color_*` globals an adapter writes. These are the scripts that force the
  scope shim, and a widget never calls them.
- `online_status_icon.sh` conflates the two: it pings and then reads `@online_icon`.
  Its data half is a two-line `ping`, so the honest widget samples directly and drops
  the dependency.
- `prefix_highlight` is already pure native tmux conditions, as the branch found. It
  becomes a widget with no `sample` at all.

The CPU slice will prefer a native counter reader and do its own thresholding
and presentation using public palette references. An optional third-party data source
is acceptable only if its interface is independent of global formatting settings.
That removes the option-scope problem at the root rather than shimming it: the scripts Airline invokes are the ones that report data,
not the ones that read colour globals. `scripts/plugin-command` and the
`adapter-formats` translation collection both become unnecessary, and Airline never
depends on a plugin entry point having run, or on having run before or after
Airline's own initialization.

TPM keeps installing and initializing plugins normally. Airline neither invokes their
entry points nor rewrites global status formats, which is already the branch's stated
boundary; the widget catalog is how that boundary stops costing a shim.

## Costs and open questions

This is a new catalog kind and new public grammar, which `TODO.md` admits only for a
demonstrated semantic difference or coverage gap. The gap is demonstrable and is the
`bug/layout-rendering` branch: adapters cannot render TPM widgets in session scope
without a process-level shim over a third party's option reads. That justification
belongs in `CHANGELOG.md` with the change.

The contract selects replacement of the adapter kind and format-only inspection
without observations. CPU must now prove the remaining runtime details:

- **Refresh.** Let tmux own redraw cadence through `status-interval`. Airline does
  not promise a widget interval or add a scheduler; runtime commands must finish
  quickly enough for normal status evaluation.
- **Palette.** Demonstrate live public option references in tmux styles, including
  session isolation and suspension. Do not assume recursive expansion of job output.
- **Failure.** Keep widget presentation and widget-owned operational claims separate
  from host invocation failures, using the existing problem lifecycle.
- **Composition.** Validate several widget formats in one segment, with ordered
  literals, independent instance state, and style restoration at fragment boundaries.

## Effect on the native-core proposal

See [the C++ core and Lua catalog proposal](native-core-proposal.md). Widgets change
its terms in Airline's favour and the change is worth recording there.

That proposal's adapter row reads "export a function receiving palette values and a
scoped option writer" — a side-effecting function whose whole purpose is mutating
host state, and the hardest row in the table to express as module data. A widget
instead returns a format string referencing public palette options and possibly
commands for external observations. Its definition can retain the same metadata
contract in a Lua implementation, and its
metadata can be read without running anything, which the proposal otherwise lists as
a guarantee the Lua migration would lose.

The proposal also names "shared function namespaces, callback names, string tuples,
argument preservation, and subshell behavior" as the Bash-specific friction that
motivates a rewrite. Sourced adapter snippets are the clearest instance of every one
of those. Replacing them with a declarative contract removes a share of the
motivation for the port rather than adding to it.

Performance depends on the widget's runtime path. Native expressions launch no
processes; external readings can incur command, cache, and CLI costs. Measure the CPU
slice rather than assuming it is unaffected by the core implementation language.
The existing initialization measurements and nameref work remain independently useful.

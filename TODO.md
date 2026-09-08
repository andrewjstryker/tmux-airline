# TODO

Airline is conceptually complete at 3.0. The public concepts, state model, and
command grammar are settled; what remains before release is a coverage and coherence
review of the surface, plus documentation and build-pipeline work.

The bar for changing the surface during this review is a demonstrated semantic
difference or a coverage gap. Symmetry, tidiness, and preference are not sufficient.
New capabilities, command families, extension systems, general-purpose frameworks,
and discretionary refactors remain out of scope.

Completed work belongs in `CHANGELOG.md`; durable behavior and architecture belong
in `README.md`, `DESIGN.md`, and focused documents under `docs/`. This file contains
only prospective work.

## Guardrails

- Change the settled grammar only for a semantic difference or a coverage gap, and
  record the justification in `CHANGELOG.md`.
- Prefer deletion, direct calls, and accurate names over new abstraction layers.
- Keep status, health, and problem lifecycle policy distinct while retaining their
  shared mutation/projection path.
- Require behavior tests for internal changes and real-tmux coverage for lifecycle,
  ownership, or process-boundary changes.
- Regenerate completions and run `make check-completions` with any change to the
  grammar or to rendered help.
- Move completed entries to `CHANGELOG.md`; do not accumulate checked-off history
  here.

## Runner element contracts

`docs/runner-elements.md` is the normative contract. The code does not yet meet it.
The stages below are ordered by dependency: each assumes the ones above it. Stages 1
and 2 change the grammar and require regenerated completions; stage 4 breaks every
element, so it lands after the seams it depends on exist.

### 1. Argument seam for every element kind

Give classifiers and filters the argument channel probes already have, in both the
invocation grammar and the `configure` callbacks, where `configure classify` today
rejects anything past the name. Closing this asymmetry is the policy seam; an element
is never obliged to use it.

### 2. `--merge-stderr` becomes a reserved token

Claim it anywhere in the option block instead of requiring it to immediately follow
`--filter <name>`, which variadic filter arguments make ambiguous. Reject it when no
filter was selected, as `--interval` already is without a probe.

### 3. Parse functions and their documentation

Add `airline_runner_<kind>_parse`, called during invocation validation, so a mistyped
element option is a CLI error rather than a runtime signal; elements without options
omit it. Document each option on its `case` arm between `options:begin`/`options:end`
markers and render them under `describe`. `lib/help.sh`'s arm pattern anchors on an
identifier (`[a-zA-Z_]…`) and one token per arm, so the element reader needs a regex
accepting `--opt)` and alternations.

### 4. Reporter contract

Rename the filter and probe reporter parameter from `report` to `health`, and add a
`<problem>` reporter beside it. Core already holds the contributor and key and already
writes problems from the filter's background subshell, so this extends
`_runner_filter_report`'s shape rather than adding a mechanism. Classifiers receive
neither reporter. Breaking for every element.

### 5. Retire the discarded status codes

Core clears a capability claim when a later observation succeeds, so an element reports
a problem only when it cannot function and never reports recovery. With stages 3 and 4
in place, retire `return 127` and every `return 2` that currently reports a usage error
into a status code `runner_probe_once` discards.

### 6. Dead code and key collisions

- Remove the write-only `load` problem key. `lib/runner.sh:745` and `:870` report it
  `ok`, and nothing sets it to `warn` or `fail`; an element that cannot load is
  rejected as a CLI error at validation, so the claim being cleared cannot exist.
- Give `_runner_probe_error` its own problem key so a generic failure notice cannot
  overwrite an element's specific diagnostic.
- Reword `lib/runner.sh`'s "stdout is never a protocol channel" comment, which is true
  of runner definitions and false of classifiers.
- Report `describe` modes as derived facts from the evaluated composition, rather than
  leaving watch capability to be discovered at invocation.

### 7. Rewrite the shipped http probe

Parse its own options, stop hardcoding the 2xx policy and the curl timeouts, and report
a missing curl through `<problem>`. This lands last as the demonstration that the
contract holds; it is the file whose defects produced this document.

## Catalog element metadata

- Element files that carry both a `#| summary:` line and a near-identical title
  comment should lose the duplication.
- `catalog_metadata` rejects a repeated header key. That rule can stand as written:
  option documentation moved to the parse function's arms, so no header key repeats.

## Grammar coherence

### Separate `show` from `describe`

`show` names two operations today. In the layout domain it reports committed session
state; in the runner domain it reads a catalog artifact from disk. Split them so
`show` reports live tmux state and `describe` reads the catalog, with no noun carrying
both meanings under one verb:

| Noun | `register` | `list` | `describe <name>` | `use` / `load` | `show` |
|------|:---:|:---:|:---:|:---:|:---:|
| palette | yes | yes | **add** | `use` only | active state |
| adapter | yes | yes | **add** | yes | active state |
| layout | yes | yes | **add** | yes | active state |
| classifier | yes | yes | **rename** | — | **remove** |
| filter | yes | yes | **rename** | — | **remove** |
| probe | yes | yes | **rename** | — | **remove** |
| runner | yes | yes | **rename** | — | **remove** |
| segment | — | — | — | — | active state |

Two consequences the principle implies and the code does not yet reflect:

- The four runner-domain nouns lose `show` outright. An element is selected per
  invocation and never installed, so once the catalog read becomes `describe` there is
  no applied state left for `show` to report there.
- The layout domain gains `describe`, closing a real gap: `use` is currently the only
  way to learn what a palette or layout contains, and it commits the change to find
  out. `segment` has no catalog and takes neither `describe` nor `list`.

`describe` always takes a required entry name, where `show` takes optional narrowing
(`palette show [name|<element>]`). `runner describe <runner> [<arg>...]` keeps trailing
arguments because resolving defaults needs them; that varies the operand, not the rule.

Renaming reaches beyond the dispatcher: `scripts/generate-completions` maps
`'classifier show') semantic=classifier` and its siblings, and both completion
artifacts regenerate.

### Add `palette load`

`adapter` and `layout` accept `load <file>` for a one-off unregistered path; `palette`
does not, so a palette must be registered before it can be applied. Add it.

Sourcing the file yourself is not a substitute, which is what settles this. A palette
is standard tmux config in syntax only: `_palette_select_unlocked` stages the file into
an isolated session surface, checks every role in `AIRLINE_PALETTE_ELEMENTS` is present
and non-empty, captures the values, clears the stage so the palette's options never
leak into user config, then commits them and records provenance. Its caller adds
adapter repaint, `render`, the transaction, and problem reporting on an incomplete
palette. `tmux source-file` gets the raw `set-option` effects and none of that, and
`session apply` cannot recover it because the private snapshot was never written.

Implementation is small, following `layout_load`, where `use` and `load` share one
unlocked implementation and differ only in resolution. `_palette_select_unlocked`
resolves the name itself today, so split resolution from evaluation; provenance records
a path for the load form, as `layout show [name|path]` already does.

Build this together with `palette describe`. Describing an unapplied palette means
evaluating it in the staging surface and reporting its roles without committing —
`_palette_select_unlocked` minus the commit. `use`, `load`, and `describe` should end
up sharing one evaluation core rather than growing three.

Precedent worth recording, because the next borderline case will cite it: this closes
an asymmetry that had a working workaround (`register` then `use`), unlike `describe`
and the element argument seam, where the capability was otherwise unreachable. The bar
applied here is that a capability present in two of three siblings is a defect in the
third, even when a detour exists.

- Affirmed, no change: `problem close` keeps its wildcard. With both identity
  operands omitted it closes every claim held by the named origin, which is the only
  mutation whose blast radius grows as the command gets shorter. That is the point of
  the verb rather than an oversight — `close` is the sweep, and the bare form is what
  the `pane-exited`, `pane-died`, and `session-closed` hooks need to run when an
  origin disappears without reporting recovery. Once `set` is pane-only, `close` is
  also the only verb handling both origin kinds, which makes the sweep reading
  explicit. Document the blast radius where the lifecycle is described rather than
  narrowing the grammar.
### One spelling for a pane target

`problem` spells its pane target `--pane` while every other signal command spells it
`-t`. The cause is not the flag name: `signal_problem_set` opens with
`local kind=session`, so `problem set` defaults to a *session* origin and `--pane`
switches the origin's kind rather than selecting a different pane. Two commands that
look alike at the call site therefore do different things, and nothing in the
invocation reveals it.

Change the default rather than the spelling:

```text
problem set   [-t <pane-target>]
problem close [-t <pane-target> | --session <session-target>]
```

`set` becomes pane-only, defaulting to the current pane, matching `status` and
`health`. Nothing is lost: session origins have exactly one producer, and it is not
the CLI. `signal_problem_report` hardcodes the session kind and is called only from
`lib/layout.sh` for palette and layout evaluation failures, which are session-scoped
because a broken palette belongs to the session's configuration rather than to
whichever pane ran `session apply`.

`close` keeps a session form because it has a live consumer: the `session-closed[90]`
hook invokes `problem close --session '#{hook_session}'` through the public CLI to
sweep those core-created claims. The asymmetry between `set` and `close` is therefore
stated rather than accidental — a session origin cannot be created through the CLI,
but Airline must be able to close one when the session ends. Keep the session form
public rather than private: unlike the result-observation callback it needs no private
state, and manually sweeping a stale session's claims is legitimate recovery, in the
same family as `transaction clear`.

This is a semantic change to `problem set`, not a rename, and it is free only until
release. Affected surface: the `#| …` annotations in `airline.sh`; option parsing in
`signal_problem_set` and `signal_problem_close`; the `pane-exited`, `pane-died`, and
`session-closed` hook command strings in `signal_problem_install_hooks`, which spell
`--pane` today; the `--pane`/`--session` arms and word-position arithmetic in both
completion scripts; the `problem set --pane %3` assertions in
`test/cli/completions.bats`; the signal tests; and the target-option rule in
`docs/cli.md`.

- `transaction clear <global|session|window> <target> <namespace>` takes its scope
  as a bare positional where the rest of the grammar uses options. Low-traffic
  diagnostics; leave the grammar alone and make the ordering explicit in help.

## Documentation

- Split the README by audience. Keep installation, palettes, segments and layouts,
  and suspend/resume; move `Process runners` to `docs/runners.md` and the signal
  how-to to `docs/signals.md`, leaving `docs/lifecycle-signals.md` as the reference.
  State the `use`/`load`/`register`/`list`/`show` verb algebra once, up front, so the
  command surface reads as five ideas rather than fifty paths.
- Mark where each audience can stop reading. Daily use ends at palettes and layouts;
  signals are for plugin authors; runners and acknowledgement are advanced. Demote
  the runner and problem bullets in the feature list, which currently recruit for the
  smallest audience above the fold.
- Reduce the signal state diagrams. Draw `clear` and `resolve` as prose captions
  rather than as an edge from every state; problem drops from nineteen edges to
  roughly nine, status from thirteen to nine. Health is already legible and is the
  control case.
- Add a sequence diagram for the problem claim layer. The self-loops in the problem
  chart are multi-origin facts forced into a single-object state machine, which
  cannot show two origins where one recovers and the problem stays active. Annotate
  each message with the resulting claim set.
- Delete the dependency graph in `DESIGN.md`. The file/responsibility table and the
  layer stack already state the architecture, the layer stack is what the
  architecture lint enforces, and the graph draws all thirty cross-module edges that
  the surrounding prose says the design does not prescribe. Keep the render dataflow
  diagram.
- Describe the runner surface as three tiers: `run -- <command>` with the default
  classifier, a named composition, and the explicit element specification that both
  lower to. Present ad hoc specification as the normal form rather than an escape.

## Deferred

- Grow the runner catalog once the surface settles. `watch` requires `--probe` and
  one probe ships, so the verb has a single out-of-the-box use; additional probes
  and definitions are what make the composed-runner path the default in practice
  rather than only in principle.

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

## Build pipeline

`scripts/generate-completions` recovers the grammar by parsing rendered help with an
awk state machine keyed to indentation widths, so a formatting change to `help.sh` is
a breaking change to the completion compiler. Emit the tab-delimited records that
`_help_records` already produces as a machine-readable form, and have the human
renderer and the completion compiler consume that instead. The `#| …` annotations
remain the single source of truth.

## Catalog element metadata

Element metadata is declared in `#| key: value` header comments and read by
`catalog_metadata` without executing the file. Inspection must not run an element:
adapters and palettes are side-effecting snippets, so sourcing one to read its
summary applies it. All shipped elements declare their metadata; the loaders have
not yet been migrated onto it.

- Retire the four competing metadata mechanisms. `AIRLINE_CLASSIFIER_SUMMARY`,
  `AIRLINE_FILTER_SUMMARY`, `AIRLINE_PROBE_SUMMARY`, `AIRLINE_PROBE_USAGE`,
  `AIRLINE_RUNNER_PROBE_INTERVAL`, and the `airline_runner_metadata` callback all
  express summary and usage; `catalog_metadata` now supplies both for every kind.
  Removing the callback also removes its duplicate-key validation machinery.
- Keep functions for behavior only: `airline_runner_classify`,
  `airline_runner_filter`, `airline_runner_probe`, `airline_runner_configure`, and
  `airline_layout_configure`. Element validity still requires the behavior function,
  so declared metadata and working behavior stay separately verified.
- Read the probe interval through catalog rather than a sourced global.
- Absent and empty are distinct: `catalog_metadata` returns non-zero for an absent
  key and empty output for a declared empty one, replacing the `+x` test that probe
  used for a usage string that may be empty.
- `list` continues to emit bare names. Both completion scripts feed its output
  straight into candidate lists, so adding summaries there is a breaking change to
  them; summaries belong to `describe`.
- Element files that carry both a `#| summary:` line and a near-identical title
  comment should lose the duplication.

## Grammar coherence

- `show` names two operations. In the layout domain it reports committed session
  state; in the runner domain it describes a catalog artifact resolved from disk.
  Rename the catalog reads to `describe` so `show` means "report active state"
  with no exceptions across the whole grammar.
- There is no read-only inspection of an unapplied catalog entry in the layout
  domain: `use` is the only way to learn what a palette or layout contains. Add
  `palette describe`, `layout describe`, and `adapter describe`. `segment` has no
  catalog and takes no `describe`.
- Affirm or narrow the wildcard on `problem close`. With both identity operands
  omitted it closes every claim held by the current origin, which is the only
  mutation whose blast radius grows as the command gets shorter. It exists for
  origin-exit sweeps; decide whether the bare form should require an explicit
  origin.
- Document, do not change: `health` spells its pane target `-t` while `problem`
  spells it `--pane`, because problem must also admit `--session`. Contributors
  writing to both channels meet both spellings, so state the rule where plugin
  authors will read it.
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

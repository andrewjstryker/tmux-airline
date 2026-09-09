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

## Grammar coherence

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

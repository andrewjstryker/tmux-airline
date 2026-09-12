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

## Widgets

Adapters do not fit the way TPM status plugins work: a plugin interpolates the global
status strings once at startup and reads its configuration from global scope, while
Airline composes session-scoped status strings and recomposes them on every palette
and layout change. The `bug/layout-rendering` branch makes adapters work and prices
the mismatch — a post-composition translation collection and a process-level shim
over plugin option reads.

- Replace the adapter catalog kind with a widget catalog following the existing
  catalog contracts, per the [widget catalog proposal](docs/widgets-proposal.md).
  Follow the [widget contract](docs/widget-contract.md): public session palette
  options, widget-owned tmux formats, and ordered composition of multiple widgets
  per segment. Prove runtime, availability, and failure handling through CPU.
  Record the grammar justification in `CHANGELOG.md` when the change ships.

- Implement and validate only the CPU vertical slice against its acceptance gate. Migrate battery, online status, and prefix state only
  after CPU proves the contract through real tmux rendering.

- Independently of the widget work, fix `_opt_decode` handling of tmux's
  single-quoted empty values (`''`), which renders an unwanted block after reload in
  the dependency-free `default` and `minimal` layouts.

## Grammar coherence

- `transaction clear <global|session|window> <target> <namespace>` takes its scope
  as a bare positional where the rest of the grammar uses options. Low-traffic
  diagnostics; leave the grammar alone and make the ordering explicit in help.

## Latency

Measured and attributed in the [latency profile](docs/latency-profile.md). These are
internal mechanics: no public grammar, option name, or storage format changes.

- Add nameref-destination read variants (`coll_get_into`, `coll_members_into`,
  `opt_get_into`) and convert the loop-resident call sites in `signal.sh`,
  `render.sh`, and `layout.sh`. Command substitution forks to return a value that a
  transaction already holds in memory: ~0.87 ms per read against ~0.01 ms for the
  nameref the write path already uses. This is the one change that takes the ~13 ms
  marginal cost per stored collection member down to a fraction of a millisecond.

- Preload the session scope before `catalog_paths` resolves the seven
  `@airline--path-*` options, so they come from the workspace instead of seven
  separate tmux round trips.

- Narrow or reuse the option snapshot. Snapshot parsing is about half of every Bash
  command executed during an init, and most parsed options are ones Airline never
  reads.

- Only if the ledger scan still measures after the above: index problem claims by
  `contributor:key` rather than filtering every member. Decided against a `jq`-style
  document store: it would beat the code as written, but loses to the nameref change
  above until well over a hundred members, and costs a runtime dependency.

## Documentation

- Delete the dependency graph in `DESIGN.md`. The file/responsibility table and the
  layer stack already state the architecture, the layer stack is what the
  architecture lint enforces, and the graph draws all thirty cross-module edges that
  the surrounding prose says the design does not prescribe. Keep the render dataflow
  diagram.

## Deferred

- Reassess the [C++ core and Lua catalog proposal](docs/native-core-proposal.md)
  after the implementation settles, using [performance measurements](docs/performance.md)
  and actual maintenance demands. No migration is scheduled.

- Grow the runner catalog once the surface settles. `watch` requires `--probe` and
  one probe ships, so the verb has a single out-of-the-box use; additional probes
  and definitions are what make the composed-runner path the default in practice
  rather than only in principle.

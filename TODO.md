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

## Configuration persistence

- Design a save/load installation story for selected layouts, palettes, and catalog
  paths. Apply saved configuration during Airline session initialization rather
  than relying on shell startup files. Discuss this separately from rendering.

## Runner contract

The runner model is being settled against the native implementation so both versions
behave identically; the contract is written up in
`../tmux-airline-native/docs/runner.md`. Bash already conforms in one respect: `watch`
ignores a declared classifier or filter and fails without a probe. The rest are
changes.

- Rename the `basic` classifier to `exit-status`. `basic` names nothing; the new name
  states what the element observes. Public catalog name, so regenerate completions.

- Ship a `none` classifier so a null runner is reachable. Today `run` always injects
  `basic`, so "Airline manages the lifecycle and nothing else" cannot be expressed.
  A real catalog entry that obeys the contract and returns no condition beats a CLI
  sentinel: the default rule stays "`run` uses `exit-status` unless it names a
  classifier" with no exception, `classifier describe none` explains itself, a
  composition declares it with no new syntax, and the core keeps exactly one selected
  classifier instead of growing an absent state. This requires the classifier
  contract to permit declining a verdict, which is distinct from reporting `ok` and
  mirrors probes, where reporting nothing is already valid.

  The default applies uniformly: a composition that omits `classify` chooses
  `exit-status` exactly as a bare invocation does. A declared filter must *not*
  suppress it, because a filter cannot distinguish an empty stream from a clean silent
  pass, so the two observations are complementary and land under separate
  contributors.

  Semantic difference: status without a verdict is a distinct and useful state.

- Stop classifying deliberate termination as failure. `basic` maps any signal to
  `fail`, so interrupting a long-running command leaves a persistent health claim for
  a stop the user asked for — the recurring cost of defaulting to a classifier at all.
  `exit-status` should decline a verdict on `SIGINT` and `SIGTERM` and reserve `fail`
  for abnormal termination.

- Replace the FIFO-and-`tee` stream split with a spill file. `run` promises to hold
  the pane's stdout, and `tee` lets a slow filter block the command and stall the
  user's terminal; dropping bytes instead would let a filter miss a `not ok` and
  report green. Writing to a file decouples them: no stall, no loss, bounded by disk,
  with the filter's reports lagging under load.

  Sketch: `cmd > >(tee -a "$spill")` with stderr inherited, and the filter reading
  `$spill` independently. The filter's stream ends when the command has terminated
  *and* the reader has reached the final offset — a reader that stops at the first
  EOF drops the last lines, so this needs its own regression.

- Correct the stderr handling that the current split implies. Without `--merge-stderr`
  stdout passes through `tee` while stderr goes straight to the pane, so the two can
  interleave differently than they would natively; with it, stderr is redirected onto
  the pane's stdout, changing what the pane shows rather than only what the filter
  sees. Pump each stream to its own pane descriptor and make merging a property of
  the spill copy alone, as the documentation already describes it. Interleaving
  within the spill is then at read granularity, which should be stated.

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

## Deferred

- Reassess the [C++ core and Lua catalog proposal](docs/native-core-proposal.md)
  after the implementation settles, using [performance measurements](docs/performance.md)
  and actual maintenance demands. No migration is scheduled.

- Grow the runner catalog once the surface settles. `watch` requires `--probe` and
  one probe ships, so the verb has a single out-of-the-box use; additional probes
  and definitions are what make the composed-runner path the default in practice
  rather than only in principle.

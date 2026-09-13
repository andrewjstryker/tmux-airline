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

## Widget policy

- Define a shared options convention for widget policy. The current contract covers
  format construction, arguments, availability, sampling intervals, and timeouts,
  but it does not yet provide a consistent home or naming scheme for user policy
  such as thresholds, hosts, device selection, fallback behavior, or refresh rules.
  Decide how policy is declared, scoped, validated, exposed by `describe`, and
  passed to both format and sample functions before adding more configurable widgets.

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

## Deferred

- Reassess a secondary problem-claim index by its marginal performance benefit
  relative to its code clarity and maintenance cost. A decrease in clarity can be
  worthwhile when offset by a substantial performance gain; larger clarity costs
  require larger gains.
  A persistent index duplicates membership and adds consistency obligations to
  reporting, recovery, closure, resolution, and clearing. Destination reads
  reduced the measured marginal set/clear-pair
  cost from 13.3 ms to 1.7 ms per stored claim; the current single-digit
  collections have not demonstrated enough remaining lookup cost to justify that
  additional state. See the follow-up in the
  [latency profile](docs/latency-profile.md).

- Reassess the [C++ core and Lua catalog proposal](docs/native-core-proposal.md)
  after the implementation settles, using [performance measurements](docs/performance.md)
  and actual maintenance demands. No migration is scheduled.

- Grow the runner catalog once the surface settles. `watch` requires `--probe` and
  one probe ships, so the verb has a single out-of-the-box use; additional probes
  and definitions are what make the composed-runner path the default in practice
  rather than only in principle.

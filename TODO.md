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

## Runner contract follow-up

The Bash contract is settled around three distinctions:

- `run` owns the foreground streams. It may supervise a command, or a probe-only
  lifecycle with no placeholder command. `watch` starts a probe in the background,
  disconnects its standard streams, returns an opaque process ID, and releases the
  pane for other work.
- `runner` selects and starts an invocation. `process list`, `process show`, and
  `process stop` inspect and control live invocations. An invocation belongs to its
  pane and ends when that pane closes. Element health claims remain separate from
  Airline's lifecycle and supervision problems.
- `conventional` is the default classifier; `none` is an explicit no-verdict
  classifier. A Bash wait status alone cannot distinguish an actual SIGINT or
  SIGTERM from an explicit exit of 130 or 143, so the classifier needs a termination
  marker supplied by the process wrapper before promising that distinction.

Output copying uses ordinary Unix pipes/FIFOs and `tee`. Airline provides no disk
spill or custom buffer, and cannot infer how a filter works. OS buffering and
backpressure therefore apply. Airline reports a core observer problem only when it
observes failure or cannot complete cleanup; a slow filter is not itself a portable
diagnosis. The core problem resolves after the command, filter, and related Airline
processes have been reaped. Filter-owned health and problem claims have their own
recovery policy.

The process record now stores the supervisor, worker, command, filter, probe, and
stream PIDs as they are created, removes them after reap, and reconciles records whose
supervisor or owning pane has disappeared. Listing is a liveness snapshot; stopping
an already-finished invocation succeeds. Once the supervisor is gone, reconciliation
retires its bookkeeping without signaling recorded child PIDs that may be reused.
Stop requests go to the live supervisor through the invocation record.
The process wrapper records INT/TERM
delivery before Bash collapses it into a wait status. This is sufficient for
Airline-initiated and terminal-delivered cancellation; a child that independently
exits 130 or 143 remains indistinguishable from a signal at the Bash boundary.

Remaining implementation work:

- Reconcile and report an owned child that cannot be reaped, resolving the core
  observer problem only after the owned process set is gone. Airline signals the
  PIDs it supplied and recorded; it does not walk the process table or claim
  ownership of descendants created privately by an element.
- Add real-tmux coverage for direct PID signal failures and the explicit-exit
  130/143 limitation in the public classifier contract.

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

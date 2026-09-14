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

## Code review follow-up

- **Keep unit coverage centered on behavior.** Most fast suites already assert
  outcomes over real modules and a mechanical fake. When revisiting runner parser
  tests, prefer accepted/rejected invocations, preserved element arguments, and
  observable results over private parser globals. Retain focused parser tests
  where they protect argument boundaries; avoid a blanket test rewrite. Add
  coverage for observable gaps rather than duplicating implementation steps in
  assertions.

Configuration persistence remains deferred. Tmux options and configuration files
already provide the platform-native source of truth; adding an Airline save/load
store would introduce filesystem state without a demonstrated need.

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

- Add real-tmux coverage for direct PID signal failures and the explicit-exit
  130/143 limitation in the public classifier contract.

Airline's process obligation ends when each PID it launched has been waited for
or Bash reports that it is no longer an owned child. Airline does not inspect the process table or
chase descendants created privately by a command, filter, or probe. A process
that remains alive is handled by the operating system and the user's system
tools; Airline reports only failures in the processes and cleanup it owns.

## Grammar coherence

- `transaction clear <global|session|window> <target> <namespace>` takes its scope
  as a bare positional where the rest of the grammar uses options. Low-traffic
  diagnostics; leave the grammar alone and make the ordering explicit in help.

## Deferred

- Do not add a secondary problem-claim index unless measurements show a material
  benefit that justifies duplicating state and consistency obligations. A decrease
  in clarity requires a larger performance gain.
  A persistent index duplicates membership and adds consistency obligations to
  reporting, recovery, closure, resolution, and clearing. Destination reads
  reduced the measured marginal set/clear-pair
  cost from 13.3 ms to 1.7 ms per stored claim; the current single-digit
  collections have not demonstrated enough remaining lookup cost to justify that
  additional state. See the follow-up in the
  [latency profile](docs/latency-profile.md).

- Keep the [C++ core and Lua catalog proposal](docs/native-core-proposal.md)
  deferred. Revisit only if measured maintenance or performance problems outweigh
  the cost of leaving Bash and tmux as the implementation platform.

- Grow the runner catalog only when a concrete use case requires another probe or
  composition; catalog breadth alone is not a project objective.

# Changelog

This file records notable completed work. It summarizes outcomes rather than the
implementation worklists used to reach them.

## Unreleased — 3.0.0

- Made process stop idempotent for finished or absent valid invocation IDs. Stop
  requests are consumed by the supervisor; stale records are retired without
  signaling their recorded child PIDs. Added repeated-stop and stale-PID safety
  regressions with real tmux.

### Runner and process contract

- Added probe-only foreground `runner run`; `runner watch` now backgrounds the
  observation with terminal streams disconnected and returns an invocation ID.
- Added `process list`, `show`, and `stop`. This grammar addition closes the
  inspection/cancellation gap created by releasing the pane for background work.
  Supervisors cancel owned work when the owning pane closes; overlapping
  invocations retain independent lifecycle membership.
- Renamed the shipped `basic` classifier to `conventional` and added `none`.
  Successful silence is now a valid no-verdict result, distinct from `ok`;
  conventional SIGINT/SIGTERM outcomes decline a verdict. Filters never suppress
  the default classifier.
- Kept stream copying on Unix FIFOs and pipes with OS backpressure; no disk spill.
  Merged observation preserves visible stdout/stderr destinations, and early filter
  completion drains remaining output while reporting a separate execution problem.
- Documented the Bash host, process ownership, reporting, scheduling, cancellation,
  and stream contracts; updated CLI help and generated completions.
- Process records now retain every Airline-created supervisor, worker, command,
  filter, probe, and stream PID and reconcile dead supervisors or vanished panes.
  The command wrapper records terminal-delivered INT/TERM before Bash reduces the
  outcome to a wait status; explicit child exits 130/143 remain necessarily
  ambiguous at the Bash boundary.
- Cleanup signals only the recorded PIDs. A vanished owning pane produces a
  server-global runner problem for later inspection; an explicit `process stop`
  reports signal failures directly to its caller without adding a problem claim.

### Performance

- Added destination-based option and collection reads and converted signal scans,
  collection internals, palette reads, and rendering loops to avoid subshells when
  accessing transaction state. Lazy scope loads now survive those reads.
- Moved shipped catalog registration into the existing initialization transaction,
  serving its seven membership reads from the session snapshot.
- Decode snapshot values and populate diff bookkeeping only when accessed, retaining
  exact-scope native options, explicit emptiness, and read-your-writes behavior.
- Added real-tmux regressions for lazy reads, native no-op writes, and unread
  mutations. These also exposed and fixed escaped quotes in snapshot decoding and
  a nonzero success return from option argument escaping.

### Widgets and public palette

- Replaced adapter commands and TPM placeholders with a widget catalog. Widgets
  return native tmux formats; layouts append ordered widget/literal fragments in a
  segment. This grammar change fixes the mismatch between startup rewriting of
  global plugin formats and Airline's session-owned rendering.
- Published effective palette roles as public session options. Palette evaluation
  uses private staging; global colors seed initialization, while session edits are
  captured by apply. Palette changes and suspension preserve widget identities.
- Added Linux CPU counter utilization, battery capacity, ICMP online status, and
  native prefix/key-table widgets. The optional observation runtime enforces pacing,
  timeouts, instance locks, guarded publication, and failure/retirement lifecycle.
- Fixed tmux snapshot decoding of empty single-quoted values and bounded option
  write batches so empty segments and larger composed formats render correctly.
- Updated inspection, CLI help, completions, authoring documentation, and tests for
  the widget contract; removed adapter scripts and TPM capability detection.

### Development tooling

- Added an isolated performance harness for CLI overhead, fresh/repeated session
  initialization, apply, health reporting, and basic/TAP runners. Recorded the
  C++ core/Lua catalog proposal as a deferred option pending measurements and
  maintenance experience.

- Added `scripts/profile-latency`, which attributes CLI latency to mechanical
  primitives, subprocess counts, executed Bash commands, and collection size against
  a disposable server. Recorded the resulting latency profile and an assessment of
  the keyed-collection storage design, concluding that command substitution on the
  read path, not the absence of an external JSON dependency, is the avoidable cost.

### Public interface and organization

- Focused the README on installation, configuration, and daily use, with help
  examples and links to dedicated runner, signal-reporting, and development guides.
  Documented shared configuration verbs and the three runner usage tiers.

- Clarified origin claims versus shared problem records in the signal lifecycle
  reference. Added a multi-origin recovery/closure sequence and simplified status
  and problem state diagrams, documenting global clear/resolve effects in prose.

- Made `problem set` pane-only with the current pane as its default and `-t` for
  explicit targets. `problem close` follows the same default and retains `--session`
  for core-origin cleanup. Removed the old problem `--pane` spelling; updated
  reporters, lifecycle hooks, completions, and the documented origin contract.
  Classifier execution diagnostics now use the runner pane too, so pane closure
  retires them consistently with filter and probe execution diagnostics.

- Added HTTP probe `--expect`, `--timeout`, and `--connect-timeout` policy options,
  retaining 2xx success and the existing five-second total/two-second connection
  budgets by default. Policy is validated before execution, applies across all
  endpoints, and is documented through `probe describe http`. Named HTTP compositions
  forward options and explicit endpoints; no arguments retain the localhost defaults.
- Supplied filters and probes with health and problem functions accepting author-owned
  contributor/key identities. Both call the same signal mutation functions as the CLI
  in the existing shell, with the invocation's pane bound as context. Validation
  errors return to the element; there is no additional CLI dispatch or signal policy.
- Removed runner-owned observation collection, mandatory reporting, and automatic
  clearing of element claims. Core execution diagnostics have separate identities;
  contributor recovery remains explicit. Migrated TAP to `airline-tap` / `assertions`
  and HTTP to `airline-http` with per-endpoint keys and explicit curl failure/recovery.
  HTTP argument errors now fail validation rather than becoming discarded exit codes.

- Added classifier and filter arguments to explicit runner specifications and named
  composition callbacks, closing the policy-input gap that previously required
  copying elements to customize them. Arguments survive normalization and spawned
  pane/window reentry; `runner describe` exposes all selected element arguments.
- Made `--merge-stderr` a reserved core token throughout the option block and
  rejected it without a filter or when repeated. Probe arguments no longer force
  the probe to be last. Configure filter declarations now use `--merge-stderr`;
  bare `merge-stderr` is an opaque filter argument, removing the ambiguity introduced
  by variadic filter arguments. See `docs/runner-elements.md` for the contract.

- Consolidated session initialization, apply, state, suspend, resume, and toggle
  operations under `airline session`.
- Replaced private process-entry commands with targeted public operations where the
  caller owns the operation. Result observation remains an Airline-private callback
  because its pane revision is internal state.
- Grouped status, health, and problem as signals while retaining their distinct
  scopes and lifecycle policies.
- Moved transaction inspection and stale-lock recovery under `airline transaction`.
- Split the former lifecycle module into focused session, signal, catalog,
  transaction, and command-boundary owners. Architecture checks now enforce actual
  dependency direction and private ownership rather than naming ceremony.
- Renamed runner state around its contributor, health-claim, and problem-claim
  roles; made each status verb enforce its own option semantics; replaced the
  scope-specific collection matrix with one scope-first API and canonical
  `(scope, owner)` tuples; and removed private option helpers with no production
  owner.
- Defined one CLI argument convention: options precede required operands, target
  options accept tmux expressions and canonicalize immediately, and private
  process entry does not change positional-argument rules. Removed the redundant
  runner `--here` spelling, separated named and ad hoc runner grammar, and rejected
  conflicting placement selections. Fixed-arity commands reject trailing operands
  instead of silently discarding them.

### Catalogs and discovery

- Extended `layout describe` with evaluated segment slots and ordered adapter
  declarations, sharing validation with layout application. Inspection does not
  execute adapters, commit configuration, or change problem claims.
- Added `palette load <file>` with absolute-path provenance and evaluated roles in
  `palette describe`. Selection, file loading, and inspection share one staged
  evaluator; inspection does not commit configuration or mutate problem claims.
- Added derived `modes` to `runner describe`: every valid composition supports
  `run`, and compositions declaring a probe also support `watch`. Modes reflect
  configuration evaluated with the supplied arguments, without a metadata field.
- Added optional classify, filter, and probe parse callbacks during invocation
  validation. Parser-rejected arguments now surface the element's diagnostic as a
  CLI error before launching work, changing topology, or reporting signals.
  Validation preserves original argv and cannot leak shell state into execution.
- Added static option documentation under `describe`, read from annotated dashed
  `case` arms and alternations between `options:begin` / `options:end` markers.
  Catalog owns extraction and rendering; summary and usage remain header metadata.

- Made `describe <name>` available across all seven catalogs, with common name
  resolution, metadata validation, and field rendering owned by catalog. Palette,
  adapter, and layout descriptions inspect headers without applying entries;
  runner owns probe intervals and evaluated composition details. All kinds use
  the same `#|` header strategy, documented in `docs/catalogs.md`; removed redundant
  summary/title comments from shipped entries.

- Renamed runner-domain `show` to `describe` for classifiers, filters, probes, and
  named runners, removing the old verbs. Catalog inspection and committed tmux
  state are semantically different operations; `show` now retains the state
  meaning. Named-runner descriptions preserve argument-dependent defaults, while
  element descriptions read metadata without execution. See `docs/cli.md`.
- Fixed Zsh catalog completion losing its executable search path to a local
  `path` variable, allowing dynamic names to be resolved through the CLI.

- Replaced the four competing element-metadata mechanisms with one convention.
  Every catalog element declares `#| summary:` in its header, plus `#| usage:` and
  an optional `#| interval:` where its kind calls for them. Retired
  `AIRLINE_CLASSIFIER_SUMMARY`, `AIRLINE_FILTER_SUMMARY`, `AIRLINE_PROBE_SUMMARY`,
  `AIRLINE_PROBE_USAGE`, `AIRLINE_RUNNER_PROBE_INTERVAL`, and the
  `airline_runner_metadata` callback with its duplicate-key validation machinery.
- Catalog reads declared metadata without executing the file, so inspection no
  longer runs a catalog element. Adapters and palettes are side-effecting snippets
  that cannot be sourced for inspection without applying them; they now carry
  metadata for the first time. Inspection reports what an element declares, while
  `run` and `watch` verify that it behaves.
- Made the probe observation interval overridable. It was declarable by a probe
  author and reachable by no one else: neither a named composition nor an
  invocation could change it, so pacing a probe differently meant copying its file.
  A composition now sets it with `configure interval` and an invocation with
  `--interval <seconds>`, with the element's declaration as the fallback. This
  follows the existing `merge-stderr` pattern, which already exposed an
  element-behavior modifier at both levels; probe interval was the only
  configurable dimension in the runner subsystem reachable from neither.
- Compiled the shell completions from the annotated grammar rather than from
  rendered help. Help formatting and completion metadata no longer share a parser,
  so wrapping, headings, and wording are free to change without regenerating
  completions.

### Rendering and configuration

- Made committed palettes and layouts session-owned through rendering. Window status
  formats remain session-scoped, while pane borders and clock color are written at
  their native window owner.
- Preserved the last valid committed configuration when trusted layout, palette, or
  adapter evaluation fails and exposed the failure through the problem service.
- Removed unused collection, option, rendering, hook, key-binding, and runner helper
  surfaces; later restored only the narrow global collection operations required by
  the server-global problem ledger.

### Transactions and performance

- Defined transactions as owner/namespace serialization with read-your-writes,
  ordered batching, deferred redraw, lock cleanup, and stale-owner recovery. They do
  not promise rollback of arbitrary trusted extension side effects.
- Added a transaction-local option workspace and batched tmux option reads and writes.
  In the recorded benchmark, cold initialization dropped from 475 tmux clients and
  2.36–2.72 seconds to 38 clients and 1.10–1.14 seconds; idempotent initialization
  dropped to 25 clients and 0.69–0.74 seconds.
- Separated mutation failure from changed/unchanged reporting so public commands
  return ordinary success for valid no-ops while still gating redraws.

### Signals and diagnostics

- Extracted signal semantics into a focused lifecycle document with state diagrams
  for status, health, and problem, including the distinction between per-origin
  recovery and authoritative problem resolution.
- Enforced exact command grammar, reliable process exit status, opaque
  diagnostics, and consistent validation at the public command boundary.
- Added explicit health and problem acknowledgement, which hides the current
  semantic level without claiming recovery. Status instead deletes observed results
  because it retains no acknowledged history.
- Made status lifecycle intrinsic to its workflow values: producers advance
  `active` processing and `attention` waiting for input, while viewing advances only
  a completed `result`. Runner health independently records the result's outcome.
- Made pane identity the single status owner, defined window reduction as
  `active < result < attention` user-action priority, and added pane-local revisions
  with exact observed-result clearing so delayed focus cleanup cannot delete another
  pane or newer work. Airline owns the observation hook and its private callback;
  contributors only set the semantic result, while `status show` exposes revisions
  for introspection.
- Added a server-global problem lifecycle ledger with independent pane/session
  claims and explicit `active`, `acknowledged`, `closed`, and `resolved` states.
  Resolution retains recovered history; destructive `clear` deletes the lifecycle.
- Made contributor and claim key separate identity fields for health and problem.
  Problem origin remains independent, allowing multiple runtime origins to assert
  one contributor capability without conflating different contributors.
- Made health pane-owned and reduced its claims across the containing window.
  Runner claims no longer encode pane IDs in semantic keys; pane movement and
  destruction reproject the affected window badges.
- Kept status key-only and left layout and palette APIs free of contributor
  qualification. Airline-owned configuration diagnostics report as contributor
  `airline` with stable `airline-layout` and `airline-palette` claim keys.
- Assigned runner classifier, filter, and probe diagnostics to concrete extension
  contributor identities while keeping runner status lightweight.

### Verification

- Added focused behavior and real-tmux integration coverage for ownership,
  transactions, signal lifecycle, contributor collisions, hooks, runner re-entry,
  failure propagation, and generated completions.
- Preserved native exit status for retained runner panes when tmux observes PTY EOF
  before reaping the pane process, including immediate command completion under
  repeated real-tmux load.
- Reduced the architecture lint from 200 to 185 lines while expanding its negative
  boundary fixtures. The 3.0.0 development tree contains 204 Bats cases.

## 2.0.0

- Reworked tmux-airline around the `airline` CLI, session-scoped configuration,
  composable layouts and adapters, runtime signals, runner catalogs, and an
  installable launcher.
- This release was intentionally incompatible with 1.x configuration and repository
  paths. See `RELEASE_NOTES.md` for the migration summary.

# Changelog

This file records notable completed work. It summarizes outcomes rather than the
implementation worklists used to reach them.

## Unreleased — 3.0.0

### Public interface and organization

- Consolidated session initialization, apply, state, suspend, resume, and toggle
  operations under `airline session`.
- Replaced private process-entry commands with targeted public operations for session
  hooks, transient status cleanup, and spawned runner re-entry.
- Grouped status, health, and problem as signals while retaining their distinct
  scopes and lifecycle policies.
- Moved transaction inspection and stale-lock recovery under `airline transaction`.
- Split the former lifecycle module into focused session, signal, catalog,
  transaction, and command-boundary owners. Architecture checks now enforce actual
  dependency direction and private ownership rather than naming ceremony.

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

- Enforced exact status and health grammar, reliable process exit status, opaque
  diagnostics, and consistent validation at the public command boundary.
- Folded transient status consumption into ordinary keyless `status clear`, used by
  the focus hook.
- Added a server-global problem lifecycle ledger with independent pane/session
  claims and explicit `active`, `closed`, and `cleared` states. Resolution deletes
  the ledger entry.
- Made contributor and claim key separate identity fields for health and problem.
  Problem origin remains independent, allowing multiple runtime origins to assert
  one contributor capability without conflating different contributors.
- Kept status key-only and left layout and palette APIs free of contributor
  qualification. Airline-owned configuration diagnostics report as contributor
  `airline` with stable `airline-layout` and `airline-palette` claim keys.
- Assigned runner classifier, filter, and probe diagnostics to concrete extension
  contributor identities while keeping runner status lightweight.

### Verification

- Added focused behavior and real-tmux integration coverage for ownership,
  transactions, signal lifecycle, contributor collisions, hooks, runner re-entry,
  failure propagation, and generated completions.
- Reduced the architecture lint from 200 to 185 lines while expanding its negative
  boundary fixtures. The 3.0.0 development tree contains 196 Bats cases.

## 2.0.0

- Reworked tmux-airline around the `airline` CLI, session-scoped configuration,
  composable layouts and adapters, runtime signals, runner catalogs, and an
  installable launcher.
- This release was intentionally incompatible with 1.x configuration and repository
  paths. See `RELEASE_NOTES.md` for the migration summary.

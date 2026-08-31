# TODO

## Architecture follow-up (2026-08-28)

This work follows the architectural review of the configuration, rendering, option
workspace, and internal module surfaces. The first four items were completed in
order; the architecture lint was strengthened only after their resulting module/API
shape settled. User-visible behavior is preserved except where an item explicitly
corrects an ownership or failure-reporting defect.

### 1. Render output at its native owner

- [x] Keep the committed palette and layout session-owned all the way through
      rendering. Write `window-status-*` formats and styles to the target session,
      not the global session defaults.
- [x] Write `pane-border-style`, `pane-active-border-style`, and
      `clock-mode-colour` at window scope for every window belonging to the target
      session. Ensure a newly created window receives the owning session's rendered
      values without borrowing the palette most recently rendered by another
      session.
- [x] Do not let independent session configuration transactions race over shared
      palette-derived global output.
- [x] Add a real-tmux, two-session regression test using distinct palettes. Verify
      both existing and newly created windows retain their session's status formats,
      pane styles, and clock color after either session is rendered again.

Completion requires every palette-derived native option to have the same effective
owner as its committed source, including tmux inheritance for future windows.

### 2. Decide failed-workspace semantics proportionately

- [x] Treat rollback as a design choice, not as an ACID requirement. The audit found
      that ordinary option staging could be discarded cheaply, but palette evaluation
      deliberately flushes the workspace, executes a trusted tmux source file, and
      reloads it. General rollback would need a second original-state model plus
      compensating tmux writes and still could not reverse arbitrary side effects from
      trusted executable definitions or adapters.
- [x] Do not add partial rollback that would protect only callbacks without workspace
      boundaries while making the overall `transaction` name appear stronger. Keep
      the current commit-on-callback-return behavior needed for failure diagnostics
      and palette-stage cleanup.
- [x] Define the transaction guarantee narrowly: owner/namespace serialization,
      read-your-writes, ordered option batching, redraw deferral, lock cleanup, and
      stale-owner recovery. It does not promise rollback when a callback fails.
- [x] Keep public operations structured to validate before mutation and commit domain
      state only after trusted definitions have passed their declaration contracts.
      Accept the residual partial-write risk of a trusted executable that fails while
      applying effects; the command reports failure and the managed problem records
      the degraded capability.
- [x] Pin the chosen behavior at the mechanical boundary so a future one-line
      discard change cannot silently break palette cleanup or failure diagnostics.

Decision: rollback is not proportionate to the remaining exposure. Revisit only if
Airline stops evaluating trusted tmux/Bash extensions inside the protected operation
or a concrete user-visible partial-write failure justifies that added machinery.

### 3. Separate mutation failure from change detection

- [x] Give option mutation an ordinary success/failure result and communicate
      changed-versus-unchanged through private data rather than overloading exit
      status 1.
- [x] Propagate render failures through session apply, palette/layout operations,
      suspend/resume, and signal projection while preserving redraw gating for
      successful no-ops.
- [x] Add failure-injection coverage for direct rendering and workspace-flush paths.
      A valid unchanged operation remains successful; a failed tmux write does not.

### 4. Remove unjustified internal surface

- [x] Audit unused collection and option helpers by intended ownership, not only by
      reference count. Before deleting one, decide whether its absence exposes a
      missed use of the common abstraction or whether it represents speculative
      symmetry.
- [x] Remove global private-collection operations while no domain owns global state.
      Reintroduce only the narrow accessors required if the state model later gains
      a genuine server-global owner. Review unused window collection wrappers,
      `coll_optname`, `opt_getor_*`, and namespace accessors under the same standard.
- [x] Remove tests that preserve deleted hypothetical APIs; retain or add tests for
      the smaller supported internal surface and its ownership rules.

The audit removed the then-unused global collection surface, unused window register/prepend
wrappers, the public collection option-name constructor, `opt_getor_*`, unused
global/config unset wrappers, the unused global `setif`, the non-targeted source-file
wrapper, unused hook-unset and key-binding primitives, a dead palette-expression
builder, and a runner-definition validity wrapper used only by its test. The later
global problem-ledger design reintroduced the minimal private-global option and
collection operations because they now have a concrete owner and caller.

### 5. Strengthen symbol-boundary lint after items 1-4

- [x] Reject duplicate public function definitions across sourced library modules.
      Bash uses one process-global function namespace, so a source-order override is
      an architectural collision just as a duplicate private symbol is.
- [x] Re-evaluate the layer map and checked source set after the preceding API and
      ownership changes, then update the design document and lint fixtures together.

## Public CLI correctness

The Agent integration review exposed two command-boundary defects. These are
Airline CLI correctness issues rather than missing Agent capabilities: the existing
status, health, and problem operations are the right public surface, but callers
must be able to trust their exit status and declared grammar.

### Mutation exit status

- [x] Preserve operational failures from target resolution, transaction acquisition,
      callback execution, workspace flush, and transaction release through the
      public status, health, and problem commands. A diagnostic on stderr must not be
      followed by exit status zero when the requested mutation did not complete.
- [x] Keep the public exit contract binary: zero means a valid request completed,
      whether Airline changed stored state or treated it as an idempotent no-op;
      nonzero means validation or operation failed. Whether stored state or its
      visible projection changed is Airline's private concern, not caller protocol.
- [x] Track projection changes privately for redraw gating. In particular, changing
      only a retained diagnostic message changes state but need not redraw an
      unchanged aggregate badge.
- [x] Do not run `command_die` inside command substitutions whose nonzero status can
      be overwritten by subsequent commands. Resolve and validate window/session
      targets in a control-flow shape that terminates the public command reliably.
- [x] Apply the same failure propagation to idempotent sets and absent clears. Their
      expected no-change result must remain successful without masking a real tmux
      or transaction failure.
- [x] Add failure-injection tests proving that invalid/unresolvable targets, failed
      transaction acquisition, failed mutation flush, and failed problem reporting
      return nonzero. Include process-level CLI tests, not only sourced-function
      tests, so the observable exit contract is covered end to end.

### Strict signal grammar

- [x] Enforce the documented arity for status and health `set`, `clear`, and `show`.
      Reject extra positional arguments instead of ignoring them or allowing a later
      argument to replace the contributor key.
- [x] Reject duplicate `-t` and duplicate `--transient` status options. Continue
      accepting status options in every position allowed by its documented grammar.
      Keep health's optional window target before its keyed condition tuple so the
      trailing message is unambiguous and opaque.
- [x] Validate status and health contributor keys against the collection invariant:
      keys must be nonempty and contain no whitespace. Apply the same key validation
      consistently to problem set, clear, and qualified show operations.
- [x] Extend window-scoped health contributors with an opaque diagnostic message.
      Require one for retained `warn` and `fail` conditions, reject tabs, and accept
      none when `ok` clears the contributor. Keep health persistent: viewing a window
      does not prove that its diagnostic was understood, so health is not transient.
      Keep status message-free because its values have direct pane-display semantics.
- [x] Make qualified health show return the retained `level<TAB>message` tuple and
      include messages in the collection listing without changing badge reduction,
      which continues to use only the severity field.
- [x] Treat health and problem messages as opaque user-facing payload. Airline may
      validate framing, retain, and display the text, but assigns it no meaning;
      classifiers, filters, probes, and other reporters own the diagnostic content.
- [x] Route health and problem through one scoped condition implementation for key
      and message validation, tuple storage, idempotence, recovery, show formatting,
      reduction, failure propagation, and redraw gating. Their only mechanical
      differences are owner scope, namespace, and projected badge.
- [x] Keep free-form problem messages opaque. Preserve the current ability to join a
      multi-argument message while rejecting tabs, and make the documented grammar
      accurately describe that behavior.
- [x] Add table-driven grammar tests covering valid option orderings and rejection of
      extra operands, duplicate options, whitespace-bearing keys, missing targets,
      and malformed problem tuples. Verify rejected commands perform no mutation.

Completion requires the process-level CLI to return zero only when a valid command
completed successfully, including an idempotent no-op, and to reject every argv not
described by the public grammar before entering a transaction.

### Runner signal ownership

- [x] Keep lifecycle status runner-owned: `active` while work is running, then a
      transient classifier-derived `result` or `attention`. Classifier, filter, and
      probe implementations remain tmux-independent and report normalized conditions.
- [x] Retain a filter's final health report after EOF so stream evidence is not erased
      by exit classification. Require at least one report, keep classifier and filter
      contributors independent, and clear stale filter health when the next run starts.
- [x] Make the shipped TAP filter report `ok` for a clean completed stream and retain
      its terminal failure diagnostic for an unsuccessful stream.
- [x] Keep probe health bounded by its observation lifecycle. Clear it when polling
      stops because Airline can no longer claim the last observation is current.

## Completed work: initialization performance (2026-08-26)

The architecture work exposed a user-facing performance question that deserves its
own investigation. Starting an isolated tmux server measured roughly 15–25 ms, while
one full Airline initialization measured roughly 1.5–2.5 seconds in controlled
alternating runs. The integration suite amplified that cost by repeatedly performing
a complete bootstrap; widening its workflows reduced the full-suite runtime from
more than eight minutes to about five minutes and thirteen seconds. That improves
test feedback, but it does not explain or improve Airline initialization itself.

The leading hypothesis is cumulative synchronous tmux client round trips. Session
resolution, catalog registration, configuration collection, rendering, transaction
markers, and problem recovery each perform option reads and writes through
`lib/tmux.sh`. Individual calls are inexpensive, but initialization performs enough
of them serially to become visible.

The synchronous-client hypothesis was confirmed. On tmux 3.4, a controlled cold
initialization launched 475 tmux clients (287 `show-options`, 181 `set-option`) and
took 2.36–2.72 seconds. A true idempotent re-initialization still launched 241
clients (173 reads, 63 writes) and took about 1.37 seconds.

The option layer now creates a transaction-local Bash workspace after acquiring the
owner lock. It bulk-loads global and owner-scoped option tables, provides
read-your-writes through the existing scalar accessors, tracks presence separately
from value, and flushes the ordered final diff as one tmux command sequence.
`source-file` flushes and reloads the workspace; redraw is deferred until after the
write flush. Collection registration also avoids its former duplicate registry read.

After the change, the same cold path launched 38 tmux clients and took 1.10–1.14
seconds. Steady idempotent initialization launched 25 clients, performed no redraw,
and took 0.69–0.74 seconds. The remaining clients are principally target resolution,
seven bootstrap catalog reads outside the configuration transaction, three
transaction acquire/release pairs, their scope snapshots, CLI publication, and hook
installation. This is small enough that broadening state ownership merely to remove
those calls is not justified.

Completed investigation:

1. [x] Establish repeatable cold-init and idempotent-reinit benchmarks. Record wall
       time, tmux client invocation count, and command count rather than relying on
       full-suite duration as a proxy.
2. [x] Trace the `AIRLINE_TMUX` process boundary and attribute client invocations to
       resolution, catalog bootstrap, configuration, rendering, transactions, and
       problem reporting.
3. [x] Identify redundant work separately from necessary work. In particular, check
       repeated option reads, read-before-write pairs, unchanged rendering writes,
       and invariant catalog registration during idempotent initialization.
4. [x] Implement batch execution at the mechanical boundary:
       - retrieve related options with one bulk query where tmux semantics permit;
       - compute the desired snapshot in memory;
       - submit ordered changed writes as one tmux command sequence or sourced file;
       - leave the seven independently owned catalog registries outside the
         transaction rather than broadening its state ownership for a small gain.
5. [x] Re-measure after each batching change and retain it only when it materially
       reduces both tmux invocations and initialization time without obscuring the
       mechanical API.
6. [x] Consider parallel execution only after batching. Parallelize only demonstrably
       independent, read-only work; do not parallelize ordered layout/adapter writes,
       shared collection mutations, rendering writes, or transaction-protected state.
       tmux is a single shared server, so concurrent clients may add contention rather
       than reduce latency.
7. [x] Preserve behavior with fast boundary tests and a few wide real-tmux workflows.
       Do not add product capability or weaken transaction, ordering, idempotence, or
       session-isolation guarantees as a performance shortcut.

Completion requires an explained profile, a before/after benchmark, and a clear
account of which round trips were removed or batched. A fixed latency target should
come from the baseline and profile rather than being invented in advance.

## Completed work: CLI and library architecture

This worklist records the CLI and library architecture review of 2026-08-26.
Compatibility with the current command grammar or internal entry points is **not**
a goal. Prefer the clearest final design over aliases, deprecation periods, or
migration scaffolding.

This is an interface and organizational clarity effort, not a capability effort.
The finished system should provide the same user-visible behavior through a clearer
public grammar and a truer module structure. Prefer deleting dispatch ceremony,
wrappers, duplicated paths, and architecture machinery over introducing a framework.
An effective reduction in production and test code is an expected outcome.

## Agreed principles

- An architecture lint must enforce a complete, meaningful architecture principle.
  Naming ceremony by itself does not justify a lint.
- A private process entry point must clear a high bar. It is justified only when:
  1. the required operation cannot be expressed coherently through the public CLI;
     or
  2. a strong policy, safety, security, or compatibility reason prevents exposing
     the operation through the public CLI.
- Implementation convenience, avoiding a flag, preserving an internal call shape,
  or skipping a parsing step does not justify a private entry point.
- Public CLI concepts and library ownership should reinforce one another. A major
  domain concept may own several primitives, as layout owns palettes, segments, and
  adapters and runner owns classifiers, filters, and probes.
- Dependencies must point downward in the code as well as in the design document.
  Modules must not call another module's private functions.
- Validate process and CLI input at the boundary. An airline-generated invocation is
  still an invocation, not trusted in-memory control flow.
- Do not add product capabilities as part of this work. A newly public operation is
  an existing behavior made honestly expressible, not a new behavior.
- Judge the rework partly by what it removes: private command vocabulary, redundant
  wrappers, duplicated execution paths, broad modules, and non-substantive lint code.

## Findings

### Architecture lint

- [x] Retain invariant A's principle: `lib/tmux.sh` is the sole application module
      that invokes the tmux binary.
- [x] Review invariant A's implementation for complete coverage. Its tmux-verb
      allowlist can miss a newly introduced subcommand, so the check may not fully
      express the stated rule.
- [x] Retain invariant B's principle: `lib/tmux.sh` is the sole owner of literal
      `@airline-` and `@airline--` option-name construction.
- [x] Review invariant B's exclusions and matching rules so the documented scope and
      checked source set agree.
- [x] Remove invariant C in its current form. Requiring `noun -> cmd_<noun>` and one
      of the currently approved handler prefixes enforces the present naming scheme,
      not dependency direction or module ownership.
- [x] Keep grammar behavior, exactly-once dispatch, argument preservation, help
      generation, and completion drift checks in the CLI test suites rather than
      presenting them as module architecture enforcement.
- [x] Introduce a replacement module-boundary lint after the target module graph
      and naming rules exist. It should enforce at least:
      - private ownership is derived from the defining file, avoiding prefix ceremony;
      - no file calls another module's private functions;
      - cross-module public calls follow an explicit allowed dependency graph;
      - `airline.sh` follows only its allowed public module edges; detailed grammar
        and dispatch behavior remains in the CLI behavior suites.

### Internal CLI entry points

The current root dispatcher contains four underscore-prefixed routes. None clears
the agreed bar for a private entry point.

- [x] Replace `_init-session` with targeted public session initialization.
      `session init` currently resolves only the current session, while the
      asynchronous `after-new-session` hook needs an explicit, stable target. Add an
      explicit target to the public operation, for example:

      ```text
      airline session init [-t <session>]
      ```

      Have the hook call that public command with `#{session_id}`.

- [x] Replace `_unfocus` with the normal public status-clear operation. A keyed clear
      removes one contributor; a keyless clear consumes every transient status
      contributor for the target window in one transaction while preserving sticky
      status and redraw gating:

      ```text
      airline status clear -t <window>
      ```

      Have the `pane-focus-out` hook translate the tmux event into that operation.

- [x] Replace `_run` and `_watch` with re-entry through public runner commands using
      the already-normalized specification:

      ```text
      airline runner run --here ...
      airline runner watch --here ...
      ```

- [x] Preserve the spawned-pane retention race guarantee without adding another
      command vocabulary. Pass airline-owned spawn provenance as execution context
      (for example, an environment marker) and let the public runner handler retain
      the new pane before validation/execution.
- [x] Remove all four underscore-prefixed arms, their delegation wrappers, grammar
      spies, and direct integration-test usage after the public paths cover their
      behavior.
- [x] Update `DESIGN.md`, whose CLI grammar currently documents `_unfocus` but omits
      the other three internal routes even though all four are reachable through the
      same executable.

### CLI concepts

- [x] Combine `state` with `session`. Active/suspended state is session-owned
      behavior and does not justify an independent root concept. Target grammar:

      ```text
      airline session init
      airline session apply
      airline session show [state]
      airline session suspend
      airline session resume
      airline session toggle
      ```

- [x] Do not retain `airline state ...` compatibility aliases.
- [x] Preserve the useful aggregate structure already present in the layout family:
      layout with palette, segment, and adapter primitives.
- [x] Preserve the analogous runner family: runner with classifier, filter, and probe
      primitives.
- [x] Give status, health, and problem an explicit shared concept and help grouping.
      The CLI and help now use `signal`; carry that decision through the module name,
      functions, tests, and design document during the lifecycle split. `attention`
      remains a status value and would be ambiguous as the owner name.
- [x] Reconsider `lock` as a root domain noun. It is transaction recovery/diagnostic
      behavior rather than lifecycle behavior; place it under a clear diagnostics or
      transaction concept if it remains public. The public noun is now `transaction`.

### Library ownership

`lib/lifecycle.sh` began as a coordinator, shared-services module, and domain module
at once. It has now been replaced: catalog, signal, session, and transaction behavior
have explicit owners, and generic CLI utilities live in a deliberately small command
boundary. Session coordinates configuration only through public layout services.

- [x] Replace `lib/lifecycle.sh` with narrower owners. The resulting owners are:
      - `lib/session.sh`: initialization, apply/show orchestration, and
        active/suspended session behavior;
      - `lib/signal.sh` or `lib/attention.sh`: status, health, problem, projection
        orchestration, and transient consumption;
      - `lib/catalog.sh`: registration, search paths, and resolution shared by layout
        and runner;
      - optionally `lib/transaction.sh`: transaction inspection and recovery above
        raw tmux mechanics.
- [x] Extract `lib/catalog.sh`; layout and runner now consume its public registration,
      path, resolution, and listing services instead of lifecycle-private helpers.
- [x] Extract `lib/signal.sh`; it owns status, health, problems, projection
      orchestration, redraw gating, and transient consumption. The CLI, layout, and
      runner use its public services directly.
- [x] Keep `lib/layout.sh` responsible for layout, palette, segment, and adapter
      behavior.
- [x] Keep `lib/runner.sh` responsible for runner orchestration and classifier,
      filter, and probe contracts.
- [x] Keep `lib/render.sh`, `lib/collections.sh`, and `lib/tmux.sh` as lower layers.
- [x] Move generic command context and error handling to a deliberately small shared
      boundary rather than allowing a new miscellaneous module to form.
- [x] Give every private function one defining owner and enforce that ownership
      directly. Primitive names such as `_palette_*` remain meaningful within layout;
      they do not need a redundant `_layout_*` prefix.
- [x] Replace cross-module private calls with small public service boundaries. In
      particular:
      - session may coordinate public layout/configuration operations (complete);
      - layout and runner consume public catalog services;
      - layout and runner report through public signal/problem services (complete);
      - signal, catalog, render, and collections reach tmux only through
        `lib/tmux.sh`.
- [x] Remove load-order assertions that stand in for real module boundaries.
- [x] Redraw the architecture graph from actual calls after the extraction and verify
      that it is acyclic.

## Suggested execution order

1. [x] Settle the public CLI grammar for targeted initialization, transient
       consumption, session state, and transaction diagnostics.
2. [x] Convert tmux hooks and spawned runners to the resulting public commands; then
       remove the four private root routes.
3. [x] Extract signal/attention and catalog responsibilities from lifecycle.
4. [x] Establish private ownership and eliminate cross-module private calls.
5. [x] Update the source/load structure and the documented dependency graph.
6. [x] Remove invariant C and add the replacement dependency/visibility lint.
7. [x] Regenerate completions and update grammar, behavior, integration, architecture,
       README, and design tests/documentation.
8. [x] Run final verification: `make lint`, `make test-fast`, and the full
       `make test` suite.

## Test strategy

- [x] Use focused fast tests during the refactor: CLI grammar/help/completions,
      architecture lint, and the directly affected in-memory behavior suites.
- [x] Run `make test-fast` at coherent milestones rather than paying the integration
      cost after each mechanical change.
- [x] Avoid routine integration-test runs while module names, dispatch, and ownership
      are moving. This work does not change `lib/tmux.sh` or intentionally add tmux
      behavior.
- [x] Run targeted integration tests at key process-boundary moments, especially
      after replacing tmux hook routes and spawned runner re-entry. Those changes
      alter subprocess wiring even though the tmux mechanics remain unchanged.
- [x] Run the complete integration and test suites once the architecture and public
      grammar have settled, before considering the work complete.

## Scope and simplification checks

- [x] Do not add new end-user behavior while reorganizing these boundaries.
- [x] Treat targeted initialization, transient consumption, and spawned-runner
      re-entry as existing behavior receiving public expression, not new capability.
- [x] Avoid compatibility aliases and adapter layers for the grammar being removed.
- [x] Avoid replacing `cmd_*` and lifecycle ceremony with registries, metaprogramming,
      or a generic module framework unless they produce a demonstrably smaller and
      clearer system.
- [x] Compare production shell LOC, test LOC, function count, and architecture-lint
      LOC before and after. These are supporting signals rather than hard targets,
      but unexpected growth requires a concrete justification.
- [x] Prefer fewer concepts and paths over a one-file-per-noun structure. File
      boundaries should represent cohesive owners, not mirror every CLI word.

### Outcome metrics

Compared with the branch base (`32f80c6`), counting `airline.sh` plus `lib/*.sh` as
production and project-owned Bats/support sources as tests:

| Measure | Before | After | Change |
|---------|-------:|------:|-------:|
| Production shell lines | 3270 | 3257 | -13 |
| Production functions | 317 | 312 | -5 |
| Architecture-lint lines | 200 | 176 | -24 |
| Test/support lines | 3124 | 3245 | +121 |
| Bats test cases | 190 | 171 | -19 |

The support-line increase is deliberate boundary coverage: catalog, signal, session,
and transaction behavior now have focused fast suites, and the architecture lint has
negative fixtures proving that violations are detected. Integration coverage was
widened from 107 narrow cases to 72 domain workflows so repeated real-tmux bootstrap
does not dominate feedback. It does not represent added product capability.
Production code, production function count, lint size, and total Bats case count all
decreased.

## Completion criteria

- [x] The public CLI can express every operation needed by tmux hooks and spawned
      runner processes.
- [x] `airline.sh` contains no private command vocabulary.
- [x] Session state is part of the session command family.
- [x] Status, health, and problem have a clear shared owner distinct from session
      lifecycle.
- [x] Catalog behavior is not owned by session lifecycle.
- [x] No module calls another module's private functions.
- [x] The documented dependency graph matches the implementation and is acyclic.
- [x] Every architecture lint states and enforces a substantive boundary.
- [x] Help and generated completions describe only the intended public grammar.
- [x] No new product capability was introduced by the architecture rework.
- [x] Any net increase in effective code size has a documented architectural reason;
      otherwise the rework reduces effective production/test complexity.
- [x] All lint and test suites pass.

## Global problem lifecycle ledger

The problem API is server-global: users never need a session id to inspect a
problem, and an active problem is immediately visible in every Airline status bar.
Origins are retained only to distinguish independent claims and automate lifecycle
transitions.

- [x] Route status, health, and problem through the same internal mutation shape:
      native-owner transaction, lifecycle callback, common reduction/projection,
      and redraw gating.
- [x] Keep status and health window-scoped; make the problem ledger, claims, badge,
      and transaction server-global.
- [x] Support `problem set [--pane <pane-id>] <key> <ok|warn|fail> [message]`.
      Omitted `--pane` records the current session as origin; a pane id preserves a
      pane-hosted contributor's identity.
- [x] Support `problem close [--pane <pane-id>|--session <session-id>] [key]` and
      install tmux pane/session lifecycle hooks that close the matching claims.
- [x] Model ledger states explicitly: `active` while contributors claim the problem,
      `closed` when the last contributor disappears, and `cleared` when the user has
      acknowledged it. Resolution deletes the ledger entry.
- [x] Give `clear` consistent user semantics across signals: normal `show` no longer
      displays the item. Status and health implement that by removal; problem keeps
      a cleared history entry.
- [x] Make `problem show` list active entries only and `problem show --all` include
      active, closed, and cleared entries with lifecycle and origin detail.
- [x] Ensure `problem set` reopens `closed` but never un-clears `cleared`. Reporter
      `ok` removes only that origin's claim and deletes the ledger when the final
      claim demonstrates recovery. `problem resolve <key>` explicitly deletes all
      claims and history.
- [x] Keep duplicate origin/key mutations, absent close/clear/resolve operations,
      projection, and redraw behavior idempotent.
- [x] Regenerate completions, synchronize user/design documentation, and pass the
      complete lint, behavior, and real-tmux integration suites.

## Contributor identity contract

- [x] Keep contributor identity convention-based rather than adding a global
      registration or collision-detection system Airline cannot make authoritative.
- [x] Define retained health and problem keys as contributor-qualified opaque keys,
      conventionally `<contributor>/<claim>[/<instance>]`.
- [x] Keep status lightweight: its key is an ownership token within one window and
      does not gain a separate contributor or origin model.
- [x] Retain problem origins independently of the qualified problem key so multiple
      runtime instances of one contributor capability aggregate without conflating
      different contributors.
- [x] Apply qualification at the external reporting boundary, not mechanically to
      Airline-owned layout and palette lifecycle keys; retain the stable reserved
      `airline-layout` and `airline-palette` identifiers.
- [x] Require contributors to mutate only their own keys, keep state out of identity,
      report recovery explicitly, and use problem for failures of advertised
      capability rather than observed domain health.
- [x] Distinguish Airline runner element kinds where an internal collision is
      possible, validate qualified external keys through real tmux storage,
      synchronize documentation, and pass the full suite.

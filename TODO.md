# TODO

## Follow-up: initialization performance

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

Initial investigation path:

1. [ ] Establish repeatable cold-init and idempotent-reinit benchmarks. Record wall
       time, tmux client invocation count, and command count rather than relying on
       full-suite duration as a proxy.
2. [ ] Instrument the `AIRLINE_TMUX` seam to attribute calls and cumulative time to
       session resolution, catalog registration, layout/palette collection, adapter
       application, rendering, transactions, and problem reporting.
3. [ ] Identify redundant work separately from necessary work. In particular, check
       repeated option reads, read-before-write pairs, unchanged rendering writes,
       and invariant catalog registration during idempotent initialization.
4. [ ] Prototype batch execution at the mechanical boundary:
       - retrieve related options with one bulk query where tmux semantics permit;
       - compute the desired snapshot in memory;
       - submit ordered changed writes as one tmux command sequence or sourced file;
       - batch builtin catalog registration after one bulk read, if that preserves
         collection ownership and priority semantics.
5. [ ] Re-measure after each batching change and retain it only when it materially
       reduces both tmux invocations and initialization time without obscuring the
       mechanical API.
6. [ ] Consider parallel execution only after batching. Parallelize only demonstrably
       independent, read-only work; do not parallelize ordered layout/adapter writes,
       shared collection mutations, rendering writes, or transaction-protected state.
       tmux is a single shared server, so concurrent clients may add contention rather
       than reduce latency.
7. [ ] Preserve behavior with fast boundary tests and a few wide real-tmux workflows.
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

- [x] Replace `_unfocus` with a public semantic operation that consumes all transient
      status and health contributors for a target window. The operation must retain
      the current transaction and redraw-gating behavior. Choose final grammar based
      on the signal/attention model rather than exposing the tmux hook name; for
      example:

      ```text
      airline signal clear-transient -t <window>
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

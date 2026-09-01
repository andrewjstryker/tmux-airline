# TODO

Airline is conceptually complete and its public interface is provisionally complete.
Future work should expose the existing model coherently and make the implementation
smaller, clearer, and more dependable. New capabilities, command families, extension
systems, and general-purpose frameworks are out of scope unless a demonstrated user
need changes that conclusion.

Completed work belongs in `CHANGELOG.md`; durable behavior and architecture belong
in `README.md` and `DESIGN.md`. This file contains only prospective work.

## Current priorities

### Internal clarity

- [ ] Rename runner contributor state so names describe its shared health/problem
      role. In particular, contributor identity should not be named as though it
      belongs exclusively to problem reporting.
- [ ] Audit repeated CLI parsing and signal lifecycle bookkeeping for small, local
      reductions. Accept a change only when it removes meaningful code or ambiguity;
      do not introduce a parser framework or generic lifecycle framework.
- [ ] Review private helpers and data passed across module boundaries after the
      signal work. Remove obsolete symmetry and wrappers, but preserve helpers that
      encode an actual ownership or transaction invariant.

## Guardrails

- Preserve the current public concepts and command grammar unless real usage exposes
  a missing or incoherent operation.
- Prefer deletion, direct calls, and accurate names over new abstraction layers.
- Keep status, health, and problem lifecycle policy distinct while retaining their
  shared mutation/projection path.
- Require behavior tests for internal changes and real-tmux coverage for lifecycle,
  ownership, or process-boundary changes.
- Move completed entries to `CHANGELOG.md`; do not accumulate checked-off history
  here.

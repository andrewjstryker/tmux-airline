# TODO

Airline is conceptually complete and its public interface is provisionally complete.
Future work should expose the existing model coherently and make the implementation
smaller, clearer, and more dependable. New capabilities, command families, extension
systems, and general-purpose frameworks are out of scope unless a demonstrated user
need changes that conclusion.

Completed work belongs in `CHANGELOG.md`; durable behavior and architecture belong
in `README.md` and `DESIGN.md`. This file contains only prospective work.

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

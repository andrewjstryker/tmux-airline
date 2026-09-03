# TODO

Airline is conceptually complete, and its public interface and implementation are
frozen for the 3.0 release. Until release, changes are limited to demonstrated
defects, inaccurate documentation, and release or packaging corrections. New
capabilities, command families, extension systems, general-purpose frameworks, and
discretionary refactors are out of scope.

Completed work belongs in `CHANGELOG.md`; durable behavior and architecture belong
in `README.md`, `DESIGN.md`, and focused documents under `docs/`. This file contains
only prospective work.

## Guardrails

- Preserve the frozen 3.0 public concepts and command grammar.
- Prefer deletion, direct calls, and accurate names over new abstraction layers.
- Keep status, health, and problem lifecycle policy distinct while retaining their
  shared mutation/projection path.
- Require behavior tests for internal changes and real-tmux coverage for lifecycle,
  ownership, or process-boundary changes.
- Move completed entries to `CHANGELOG.md`; do not accumulate checked-off history
  here.

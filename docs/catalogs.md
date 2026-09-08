# Catalogs and discovery

Airline has seven catalog kinds: palette, adapter, layout, classifier, filter, probe,
and runner. Each has a session-owned, ordered search path. `register <dir>` prepends
an existing directory; shipped directories provide the fallback. Bare names resolve
to the first matching file, and `list` returns each available name once without
executing files. Segment is active configuration, not a catalog kind.

Every catalog supports `describe <name>`. Catalog owns name resolution, common
metadata validation, and rendering of name, summary, declared usage, and resolved
path. Palette, adapter, and layout retain `show` for their active state. Classifiers,
filters, probes, and runners are selected per invocation and have no installed state
for `show` to inspect.

## One metadata format

All seven kinds declare discovery metadata in marked header comments:

```bash
#| summary: Check one or more HTTP endpoints
#| usage: <endpoint> [<endpoint>...]
#| interval: 5
```

- `summary` is required and must contain non-whitespace text.
- `usage` describes arguments accepted by the entry. An empty value explicitly means
  no arguments; an absent field is omitted from the description. The runner domain
  currently requires this field for probes and named compositions.
- `interval` is a probe-specific default, in seconds. Runner validates it and renders
  the effective default (five seconds when unspecified).

Keys are lowercase words with optional hyphens. Each key may occur only once, and
malformed markers or repeated keys invalidate the header. Values occupy one line.
Scanning stops at the first nonblank, noncomment line. A shebang is a comment.
Metadata is never discovered through shell variables, callbacks, or file execution.
Keep explanatory comments when they add information; do not repeat the summary as a
title comment. Unknown well-formed fields are retained by the metadata reader but do
not automatically become description rows or executable policy.

The same rules apply to palette files written in tmux syntax and to shell elements.
Registration does not source or validate every entry: validation happens when a
specific description is requested. Invocation may require additional domain contracts.

## Description and evaluation

Palette, adapter, layout, classifier, and filter descriptions currently read only
metadata. Probe descriptions add the validated interval. These operations never
execute the inspected file or apply configuration. Metadata describes the entry;
it does not prove that the entry can execute successfully.

Named-runner descriptions additionally evaluate the trusted composition's configure
function to report selected elements and resolved defaults. `runner describe <name>
[<arg>...]` forwards arguments intact, just as a named invocation does. It launches
no command or observation. The runner domain owns that evaluation and adds its
results to the common catalog description through direct calls.

Derived fields belong to the owning domain, not in duplicated header declarations.
Evaluating palette roles or layout contents without committing them remains separate
work; it must reuse the domain's evaluation path. Catalog has no evaluator registry
and does not depend on layout or runner.

See [CLI conventions](cli.md) for argument and target rules, and
[runner element contracts](runner-elements.md) for the runner contract and the
option-documentation convention.

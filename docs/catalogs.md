# Catalogs and discovery

Airline has seven catalog kinds: palette, widget, layout, classifier, filter, probe,
and runner. Each has a session-owned, ordered search path. `register <dir>` prepends
an existing directory; shipped directories provide the fallback. Bare names resolve
to the first matching entry, and `list` returns each available name once without
executing files. Segment is active configuration, not a catalog kind.

Catalog entries use role-specific extensions. Shell definitions use `.sh`; tmux
configuration files use `.conf`. The logical name omits the extension:

```text
widgets/battery.sh       # format definition named battery
widgets/battery          # optional runtime executable named battery
layouts/adaptive.sh      # layout named adaptive
palettes/default.conf    # palette named default
```

The extensionless widget executable is a runtime companion, not a catalog definition.
Widget resolution finds `<name>.sh` and, when the format contains a `#()` command,
the definition may invoke the sibling `<name>` executable directly. Catalog discovery
does not execute either file merely to list or describe it.

Every catalog supports `describe <name>`. Catalog owns name resolution, common
metadata validation, and rendering of name, summary, declared usage, and resolved
path. Palette and layout retain `show` for their active state. Classifiers,
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
- `interval` is a runner probe field, in seconds. It is not a widget field; tmux owns
  status refresh cadence for widgets.

Keys are lowercase words with optional hyphens. Each key may occur only once, and
malformed markers or repeated keys invalidate the header. Values occupy one line.
Scanning stops at the first nonblank, noncomment line. A shebang is a comment.
Metadata is never discovered through shell variables, callbacks, or file execution.
Keep explanatory comments when they add information; do not repeat the summary as a
title comment. Unknown well-formed fields are retained by the metadata reader but do
not automatically become description rows or executable policy.

The same rules apply to palette `.conf` files written in tmux syntax and to shell
`.sh` elements.
Registration does not source or validate every entry: validation happens when a
specific description is requested. Invocation may require additional domain contracts.

## Option documentation

File-wide summary and usage stay in the header. Individual options are annotated on
their implementation's `case` arms in one optional marked region:

```bash
# options:begin
case "$1" in
  --timeout|-t) ... ;; #| <seconds> — request budget
  --quiet) ... ;; #| — suppress normal output
esac
# options:end
```

Catalog reads these annotations without executing the file and renders them under
`options:` in `describe`. It accepts dashed option names and literal alternations,
with optional spaces and an opening parenthesis. Markers may be indented; function
names and brace layout do not affect extraction. Unannotated arms and annotations
outside the region are ignored. This is a documentation reader, not a shell parser
or a generated option parser. Use literal unquoted option spellings in documented
arms. Duplicate, unclosed, or unmatched regions make the description fail; files
without a region have no option section.

## Description and evaluation

Classifier and filter descriptions currently read only
metadata. Probe descriptions add the validated interval. These operations never
execute the inspected file or apply configuration. Metadata describes the entry;
it does not prove that the entry can execute successfully.

Named-runner descriptions additionally evaluate the trusted composition's configure
function to report supported modes, selected elements, and resolved defaults.
Every valid composition supports `run`; one declaring a probe also supports `watch`.
`runner describe <name> [<arg>...]` forwards arguments intact, just as a named
invocation does. It launches
no command or observation. The runner domain owns that evaluation and adds its
results to the common catalog description through direct calls.

Palette descriptions evaluate all required roles through the same session staging
path as `palette use` and `palette load`, without committing the candidate palette.
See [palette selection and inspection](palettes.md) for staging and trust boundaries.

Layout descriptions evaluate segment and widget declarations through the same
declaration evaluator as `layout use` and `layout load`. They do not sample widgets or commit configuration. See [layout inspection and application](layouts.md).

Derived fields belong to the owning domain, not in duplicated header declarations.
Widget descriptions construct formats and check cheap availability without running
runtime executables. See [widgets](widgets.md) for the format and runtime contract.

Catalog has no evaluator registry
and does not depend on layout or runner.

See [CLI conventions](cli.md) for argument and target rules, and
[runner element contracts](runner-elements.md) for the runner contract and the
option-documentation convention.

# CLI conventions

Airline commands use a noun and verb followed by options and positional arguments:

```text
airline <noun> <verb> [<options>...] [<arguments>...]
```

A small, fixed set of parameters required by an operation is positional. This rule
does not depend on whether the command is public or private. Options identify
optional departures from a default when their presence or meaning cannot be
reliably inferred from position alone. The value required by an option belongs to
that optional choice; it is not a required operand of the base operation.

When tmux provides an obvious current context, that context is the default and a
target option selects another one. Naming the override avoids confusing an optional
target with the command's required semantic operands.

Target options accept tmux target expressions for their declared type. A
`<pane-target>`, `<window-target>`, or `<session-target>` is resolved immediately to
the corresponding canonical pane, window, or session identity before Airline uses
or stores it. The expression itself is not persistent identity. Lifecycle callbacks
may supply an already-canonical `%N` pane or `$N` session identity after that object
has disappeared; no other unresolved expression is accepted.

Options appear before positional arguments in the canonical grammar:

```text
airline status set [-t <pane-target>] <active|result|attention>
airline health set [-t <pane-target>] <contributor> <key> <level> [<message>...]
```

Options may be reordered within that leading option block when they are independent.
After the first positional operand, a parser does not resume consuming Airline
options; commands with fixed operands reject a recognized option placed there.
Variadic opaque arguments, such as diagnostic messages and named-runner arguments,
instead retain their contents.

With no `-t`, status, health, and problem mutations use the current pane, while window-level
inspection uses the current window. Behavioral modifiers
such as `--all` and `--merge-stderr` are also options. A trailing positional may be
optional when it naturally narrows or selects command output, as in `segment show
[<segment>]`. `--` is a delimiter before an opaque command, not a behavioral option.

Runner placement follows the same default rule: omitting placement means the current
pane, while the mutually exclusive `--pane` and `--window` options request new tmux
topology. Named runner and ad hoc element specifications are separate grammar forms;
a leading bare name selects a runner, while an option-leading specification selects
its classifier, filter, or probe directly.

For example, Airline's private result-observation entry point takes both its pane
and revision positionally because both are required and their order is unambiguous.
Its absence from public help and completions is an API-ownership decision, not an
argument-layout convention.

## Exit statuses and errors

Exit statuses describe whether a command completed successfully. They are separate
from signal conditions (`ok`, `warn`, `fail`) and problem lifecycle states
(`active`, `acknowledged`, `closed`, `resolved`). Successfully reporting a `fail`
condition returns `0`; it does not make the reporting command fail.

| Status | Meaning |
|--------|---------|
| `0` | Success, including an operation that requires no state change. |
| `1` | General execution or infrastructure failure, such as an unavailable launcher or a failed transaction acquisition or write. |
| `2` | Airline rejected the operation: invalid arguments, an invalid element contract, an unresolved target, or another command-level error. Read stderr for the specific reason. |
| `70` | Palette evaluation or configuration is incomplete or could not be evaluated. |
| `80` | Layout evaluation or application failed. |
| `129`, `130`, `143` | Signal termination handled by Airline: HUP, INT, or TERM, respectively (`128 + signal number`). |

Status `2` is not exclusively a syntax error: command-level failures such as an
unreadable version file or refused transaction recovery also use it. Lower-level
operations can propagate other nonzero statuses; Airline does not normalize every
failure into this table. Scripts should treat any nonzero status as failure unless
the command's particular contract gives it another meaning. Diagnostics are for
people; do not parse their wording as a stable machine interface.

There are two runner-specific distinctions:

- `runner run` in the current pane returns the child command's exit status after
  execution. A child can itself return `2`, so that number alone cannot distinguish
  an Airline error from a child failure. Classifier, filter, and probe reports do
  not replace the child's exit status.
- With `--pane` or `--window`, the launching command does not wait for the spawned
  workload's eventual result. Its exit status cannot report that workload's outcome.

Hosted health and problem reporting functions follow the same mutation contract as
the CLI: `0` means success (including no change), `2` reports validation or target
resolution failure, and runtime failures can propagate a nonzero status. They
return to the calling element instead of exiting its shell. In shell code,
`"$problem" contributor key ok || return` propagates the reporting call's failure;
the bare `return` preserves that call's nonzero status. Tests establish correct
behavior, but callers still need to handle runtime failures such as a target pane
disappearing. See [runner element contracts](runner-elements.md).

## Catalog inspection and active state

Every catalog kind accepts `describe <name>`: palette, widget, layout, classifier,
filter, probe, and runner. The name is required and must be a bare catalog name.
`runner describe <name> [<arg>...]` accepts composition arguments;
`widget describe <name> [<arg>...]` accepts format arguments. Segment has no catalog and accepts neither `describe` nor `list`.

`show` reports live tmux state, with optional narrowing such as `palette show name`.
Runner-domain catalogs have no installed state and do not accept `show`.

`layout describe` evaluates segment and widget declarations without applying them;
`layout show` still reports the active selection. See [layouts](layouts.md).

`palette describe` also evaluates the file's roles without selecting it. `palette
load <file>` applies an unregistered palette, following the same validation and
repaint path as `palette use <name>`. See [palettes](palettes.md).

See [Catalogs and discovery](catalogs.md) for shared metadata, resolution, and the
boundary between description and domain evaluation.

## Problem origins and targets

`problem set [-t <pane-target>] <contributor> <key> <level> [<message>...]`
always reports for a pane, defaulting to the current pane. The old `--pane` spelling
is rejected. This changes the former session default as well as the option name.

`problem close [-t <pane-target> | --session <session-target>] [<contributor> [<key>]]`
defaults to the current pane too. The target options are mutually exclusive and must
precede the identity operands. Omitting both identity operands closes every claim
held by the selected origin; it does not sweep other origins. Hooks use this form
when a pane or session disappears, accepting its departed canonical `%N` or `$N` ID.
`set` requires a live pane.

Session origins are reserved for core configuration reports. Public `close --session`
remains available for lifecycle hooks and manual cleanup of those claims. See
[signal lifecycles](lifecycle-signals.md) for recovery and retained history.

## Active process management

`runner list` discovers definitions. `process list` lists active invocations on the
connected server; `process show <process-id>` inspects one and `process stop
<process-id>` cancels its owned work and waits for cleanup. Watch prints this opaque
ID after startup and releases the pane with standard streams disconnected. Run
holds the foreground for a command or repeated probe. A placed command run returns
a pane ID; a placed watch returns a process ID and leaves a usable shell in its pane.

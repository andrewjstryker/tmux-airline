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
airline health set [-t <window-target>] <contributor> <key> <level> [<message>...]
```

Options may be reordered within that leading option block when they are independent.
After the first positional operand, a parser does not resume consuming Airline
options; commands with fixed operands reject a recognized option placed there.
Variadic opaque arguments, such as diagnostic messages and named-runner arguments,
instead retain their contents.

With no `-t`, these commands use the current pane or window. Behavioral modifiers
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

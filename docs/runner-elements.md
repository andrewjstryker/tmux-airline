# Runner element contracts

A classifier, filter, or probe is trusted shell that Airline loads from a registered
catalog and calls at a defined moment. This document defines what Airline hands each
kind, what each kind hands back, and which parts of an invocation belong to Airline
rather than to the element.

The governing rule is that **Airline validates the contract, not the policy.** Core
checks that a condition report is well formed and that a required function exists. It
has no opinion on whether a 2xx response means healthy, whether exit status 5 deserves
a warning, or how a log line should be read. Those are the element's domain, which is
why every kind can receive arguments: policy belongs to the element, so the element
needs a channel through which a user can supply it.

## The three kinds

| Kind | Airline supplies | Element returns | Invoked |
|------|------------------|-----------------|---------|
| Classifier | exit status, signal, argv | one condition on stdout | once, when the child exits |
| Filter | child pid, `<health>`, `<problem>`, the command's output on stdin, argv | conditions through `<health>` | once; reads until EOF |
| Probe | lifecycle pid, `<health>`, `<problem>`, argv | conditions through `<health>` | repeatedly, paced by core |

Output shape follows input shape. One exit event yields exactly one condition, so a
classifier returns it on stdout and core parses it. A stream or a repeated poll yields
many conditions over time, so filters and probes receive a reporter callback. This is
a consequence of what each kind observes, not an inconsistency between them.

## Run and watch

`run` and `watch` are not separate catalogs or separate element kinds. They differ in
which inputs exist, and the available kinds follow:

- `run` launches a child command, so an exit status and an output stream exist. All
  three kinds are meaningful.
- `watch` launches nothing, so neither exists. Only a probe is meaningful, and
  `--classify` and `--filter` are rejected.

A named composition is therefore usable with `watch` exactly when it declares a probe.
Core derives this from the composition rather than from a declaration: a composition
that declares no probe fails `watch` with a diagnostic naming the missing capability.
`describe` evaluates a composition and can report the modes it supports; `list` names
and summarizes elements without evaluating anything.

## Metadata

Every element uses the [shared catalog metadata format](catalogs.md), which core
reads without executing the file:

```bash
#| summary: Check one or more HTTP endpoints
#| usage: [--timeout <seconds>] [--expect <pattern>] <endpoint> [<endpoint>...]
```

`summary` is required, and `usage` gives the synopsis of an element that accepts
arguments. Both describe the file as a whole, so both live in the header. Inspection
must never execute a catalog element, so metadata is read from the header rather than
from shell assignments.

Individual options are documented where they are implemented, on the arms of the parse
function's `case`, between explicit markers:

```bash
_http_probe_parse () {
  # options:begin
  case "$1" in
    --timeout) … ;; #| <seconds> — per-request budget
    --expect)  … ;; #| <pattern> — status treated as healthy; default 2[0-9][0-9]
  esac
  # options:end
}
```

This is the convention `airline.sh` uses for its own grammar, for the same reason:
documentation that sits beside the code implementing it cannot drift from it. Deleting
an arm deletes its documentation, and renaming a flag moves its text along with it.
Core reads these annotations without executing the file and renders them under
`describe`; it does not build a parser from them, because the arm it is reading is
already the parser. Markers delimit the region so extraction never depends on function
names, brace placement, or indentation.

## Two levels of argument parsing

An invocation carries two kinds of option. Airline owns everything that describes
*what core supplies*; the element owns everything that describes *what it does with
what it received*.

Core claims a fixed set of reserved tokens, and passes every other argument through to
the element opaquely:

```text
--pane  --window  --classify  --filter  --probe  --interval  --merge-stderr  --
```

`--interval` is Airline's because pacing is core's loop, not the probe's work.
`--merge-stderr` is Airline's because it selects which stream core hands to the filter.
Neither is an element policy knob, and an element must not define an option with a
reserved name.

Everything after an element's name and before the next reserved token is that
element's argv:

```text
airline runner watch --interval 30 --probe http --timeout 3 https://example/health
                     └── core ──┘             └──────── probe argv ────────┘
```

A knob whose element was not selected is rejected: `--interval` without `--probe`,
`--merge-stderr` without `--filter`.

An element is never required to accept arguments. A classifier that hardcodes its
mapping is a valid classifier; the seam exists so that policy has somewhere to live
other than a forked copy of the file.

## Required functions

Each kind exposes one function named for its action:

```bash
airline_runner_classify <exit-status> <signal> [<arg>...]
airline_runner_filter   <child-pid> <health> <problem> [<arg>...]
airline_runner_probe    <lifecycle-pid> <health> <problem> [<arg>...]
```

A classifier receives no reporters. It is a pure function of its arguments, and a pure
function has no external capability to lose: it must be implementable in Bash without
external dependencies. Its two failure modes belong to core rather than to itself — an
element that cannot load is rejected as a usage error before the run starts, and one
that emits an invalid condition is reported by core as a problem against it. Work that
needs an external tool is observation, not classification: a filter decides at end of
stream, a probe polls while the process lives, and both carry `<problem>`.

Core supplies every reporter. An element receives no ambient configuration: there are
no environment variables in this contract, and everything an element needs arrives as
an argument or on stdin.

An element that accepts arguments also exposes a parse function, which core calls when
it validates the invocation:

```bash
airline_runner_<kind>_parse <arg>...
```

A non-zero return means the invocation was wrong, and core reports the element's
message as an ordinary CLI error before anything starts. This is what keeps a
mistyped option from becoming a runtime signal: bad input is a usage error, not a
statement about health or about a missing capability. An element with no options
omits the function.

Element-private helpers share a namespace with core once sourced, so they carry the
element's own name as a prefix: `_http_probe_report`, not `_report`.

## Reporting

Three outcomes, three channels. Choosing between them is a question about what
happened, not about severity.

**Usage error** — an unknown option, a missing value, no target. Reported by the parse
function and surfaced as a CLI error at invocation.

**Capability failure** — the element cannot do what it advertises, because a required
executable is absent or a prerequisite is missing. Reported through `<problem>`, which
raises the global claim that a contributor cannot provide a capability:

```bash
"$problem" fail "curl is not installed"
```

The claim's identity — contributor and key — is core's, derived from the element's kind
and name. An element never supplies, chooses, or inspects it, so core passes a reporter
that already holds it rather than exporting the identity for the element to quote back.
The reporter is an ordinary function call even where the element runs in a forked
process: a filter executes inside a background subshell, and its reporter writes
signals from there today.

Because core owns the identity, core also clears the claim when a later observation
succeeds. An element therefore reports a problem only when it cannot function, and
never reports recovery.

**Observation** — what the element actually saw. Reported through `<health>` for
filters and probes, and on stdout for classifiers. Core reduces every condition
reported during one observation to the worst, and projects a single claim. An element
supplies evidence; the runner owns the claim.

The two reporters differ in what they assert, not in how they are delivered. `<health>`
says what the element saw; `<problem>` says the element could not look. A run that
reports `fail` health is working correctly; a run that raises a problem is not.

## Trust and boundaries

Elements are trusted shell: registering a directory is the decision to allow it. They
receive no tmux handle, no session target, and no access to private state, and they
make no tmux calls of their own. Stdout is user-facing output whose format Airline does
not interpret, except for a classifier's single condition line, where stdout is the
return channel.

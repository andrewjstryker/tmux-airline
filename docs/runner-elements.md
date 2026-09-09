# Runner element contracts

A classifier, filter, or probe is trusted shell that Airline loads from a registered
catalog and calls at a defined moment. This document defines what Airline hands each
kind, what each kind hands back, and which parts of an invocation belong to Airline
rather than to the element.

Catalog registration does not make an element part of Airline core. The reporting
functions below are in-process entry points to the same mutations exposed by the CLI.

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
| Filter | child pid, health and problem functions, stdin, argv | publishes its own signals through the supplied functions | once; reads until EOF |
| Probe | lifecycle pid, health and problem functions, argv | publishes its own signals through the supplied functions | repeatedly, paced by core |

A classifier returns a condition for the completed command on stdout. Filters and
probes are contributors: they select their identities and keys, publish observations,
and report recovery through the supplied health and problem functions. Airline performs the
lifecycle mutations and reduction over their claims.

## Ownership

Catalog entries are authored extensions, including the entries shipped with Airline.
Their authors own contributor names, key meanings, and recovery policy. Core does not
assign an element's claim identity from its catalog name, clear its claims because an
invocation succeeded, or require it to report on every call.

Runner core owns scheduling, child process handling, status transitions, its command
outcome projection from the classifier's return, and diagnostics about failures of
those mechanisms. Those are core's claims. They must not share identities with
contributor-managed claims. Signal core owns validated lifecycle mutations, reduction,
and origin cleanup through the public lifecycle rules.

There are two calling paths to the same signal mutations. External processes use
the CLI; hosted elements use supplied functions to avoid starting another Airline
command-dispatch graph for each report. Both paths call `signal_health_set` or
`signal_problem_set`, which own validation and the shared lifecycle/projection path.
No second lifecycle implementation or runner-specific observation reducer exists.

Supplying a function does not transfer claim ownership to core. The private
result-observation callback has a different purpose: it carries a revision token
owned by Airline. Health/problem reporting needs no private identity token. Parse
and configure callbacks validate arguments and declare compositions, respectively.

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
`runner describe <name> [<arg>...]` evaluates the composition with those arguments
and reports `modes`: `run` for every valid composition, or `run watch` when it
declares a probe. Arguments can change the selected elements and therefore the
reported modes. This is a derived fact, not a metadata field or a guarantee that
the selected elements will execute successfully. `list` names and summarizes
elements without evaluating anything.

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
airline_runner_probe_parse () {
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

## Arguments and named compositions

All three element kinds receive the arguments after their name, up to the next
reserved token. Core options may follow probe arguments as well as classifier or
filter arguments. For example:

```bash
airline runner run --merge-stderr --probe http https://example/health --interval 30 \
  --classify custom --policy strict --filter custom --format compact -- make test
```

Here the classifier receives `--policy strict`, the filter receives `--format
compact`, and the probe receives the endpoint. Core passes element options opaquely
to the optional parse callback for validation. Empty arguments, whitespace, and shell
metacharacters retain their original argv boundaries.
Everything after `--` belongs to the child command, including reserved spellings.

A reserved token ends an element's argument block. Arguments cannot resume after a
standalone core option: put all filter arguments before `--merge-stderr`, or put
`--merge-stderr` before `--filter`. Repeated element selections and repeated
`--merge-stderr` are errors. `watch` still rejects classifiers and filters.

Named compositions receive the same argument channels through their configure callback:

```bash
"$configure" classify <name> [<arg>...]
"$configure" filter <name> [<arg>...] [--merge-stderr]
"$configure" probe <name> [<arg>...]
"$configure" interval <seconds>
```

Within a filter declaration, `--merge-stderr` is a core modifier and may appear
anywhere after the name; it is removed from the filter's arguments. The old bare
`merge-stderr` spelling is now an ordinary argument. Other reserved runner tokens
are rejected in element argument declarations, preventing a composition from
changing placement or selecting another element through its argv. Use the dedicated
configure fields to select elements and set the interval.

Named compositions project to the same explicit specification used for ad hoc
invocations. Normalization preserves element arguments when reentering the CLI in a
new pane or window. `runner describe` shows classifier, filter, and probe arguments
with shell quoting so empty arguments and spaces are visible. A watch invocation
projects only the probe and its interval from a named composition.

## Required functions

Each kind exposes one function named for its action:

```bash
airline_runner_classify <exit-status> <signal> [<arg>...]
airline_runner_filter   <child-pid> <health> <problem> [<arg>...]
airline_runner_probe    <lifecycle-pid> <health> <problem> [<arg>...]
```

A classifier returns one condition on stdout. Core validates that result and may
project it as its own command outcome; this function result does not give core
ownership of the classifier author's other signal claims. An element that cannot
load is rejected before execution, and an invalid classifier result is a core
contract diagnostic.

Filters and probes receive two function names, called as follows:

```bash
"$health"  <contributor> <key> <ok|warn|fail> [<message>...]
"$problem" <contributor> <key> <ok|warn|fail> [<message>...]
```

The functions bind the invocation's pane context. Health is stored on that pane;
problems carry that pane as their origin in the global ledger. This is equivalent to
`health set -t <pane>` and `problem set --pane <pane>` in the current CLI grammar.
The element chooses both contributor and key. Use public CLI target options for
reporting deliberately directed outside the invocation's pane.

Messages follow CLI semantics: trailing words are joined with spaces, `ok` takes no
message, and `warn`/`fail` require one. Both reporting functions return zero on success
and nonzero on validation or mutation failure. An invalid tuple returns status 2
with a diagnostic rather than exiting the hosting shell. Elements must handle or
propagate failures, for example with `"$health" author key fail message || return`.
There is no private identity supplied through environment variables.

A reporter executes in its caller's existing shell process. For a filter or background
probe loop, this is already a subshell; reporting neither starts a CLI subprocess
nor sends a message to the parent runner process. Normal signal transactions still
provide concurrency control. The provided names are part of the element calling
contract; their implementation names are private and must not be hardcoded.

An element that accepts arguments also exposes a parse function, which core calls when
it validates the invocation:

```bash
airline_runner_classify_parse [<arg>...]
airline_runner_filter_parse [<arg>...]
airline_runner_probe_parse [<arg>...]
```

A non-zero return means the invocation was wrong, and core reports the element's
message as an ordinary CLI error before anything starts. This is what keeps a
mistyped option from becoming a runtime signal: bad input is a usage error, not a
statement about health or about a missing capability. An element with no options
omits the function. Parsers receive only element arguments, without process IDs or
reporters. Validation runs before launching a command, creating a pane/window, or
publishing lifecycle signals, for both explicit and named invocations. A named watch
validates only the probe selected by its projected composition.

Write a useful diagnostic to stderr and return non-zero on invalid input. Airline
includes the diagnostic in a CLI error with exit status 2. Output from successful
validation is discarded. Parsing runs in an isolated validation subshell: shell
variables, functions, and argument changes do not configure the later observation.
Execution receives the original argv. An element may share a private parsing helper
between its validation callback and its action to avoid duplicating option policy.
Keep validation free of external side effects; subshell isolation does not undo file
writes or external commands. Loading an element clears its action and parse function
first, so an omitted parser cannot inherit a previously loaded element's parser.

Element-private helpers share a namespace with core once sourced, so they carry the
element's own name as a prefix: `_http_probe_report`, not `_report`.

## Reporting

**Usage error** — an unknown option, a missing value, or no target. The optional parse
function rejects it during invocation validation, before execution.

**Observation** — what a filter or probe actually saw. The contributor chooses health
keys and calls the supplied health function. For example, a probe checking two endpoints can
maintain two independent claims:

```bash
"$health" example-http live fail "live endpoint returned HTTP 503"
"$health" example-http ready ok
```

The healthy endpoint cannot erase the failing endpoint's claim. Airline reduces the
remaining claims; the reporter publishes each mutation directly. The author decides
whether endpoints need distinct keys or a deliberately aggregated report. Stable key selection and retiring keys for removed endpoints
belong to that author.

**Capability failure** — the contributor cannot observe because a required executable
or prerequisite is missing. It chooses a problem key and reports failure and recovery
through the supplied problem function:

```bash
"$problem" example-http curl fail "curl is not installed"
# When the contributor verifies that capability is available again:
"$problem" example-http curl ok
```

The supplied problem function binds a pane origin, while the contributor owns its
key. Core must not infer recovery from a successful process exit or from a health report: neither
proves that a separate capability claim has recovered. Public origin cleanup still
applies when a pane or session disappears, and remains distinct from contributor
recovery. See [signal lifecycles](lifecycle-signals.md).

A filter or probe may publish no changes when there is no new evidence. A missing
report is not itself a contract failure. Unexpected execution failures can produce a
separate core diagnostic; they do not authorize core to overwrite or recover the
element's claims. Capability failures are reported through the supplied problem
function, rather than magic exit codes whose meaning core must guess.

## Trust and boundaries

Elements are trusted shell: registering a directory is the decision to allow it.
Their supplied reporting functions call public signal mutations in the current
process. Elements do not access private state or write signal storage directly. Stdout is user-facing output, except for a classifier's single condition
line, where stdout is the return channel.

## Shipped contributor policies

The TAP filter owns `airline-tap` / `assertions`. It reports progressive failures and
a final stream result; core does not clear that result at the next invocation.

The HTTP probe owns `airline-http`. Its `curl` problem key describes availability of
curl and is explicitly recovered when curl becomes available. Health keys are
`endpoint-` followed by the hexadecimal bytes of each URL, giving stable distinct
keys without forbidden whitespace or colons. Successful checks recover only their
endpoint key. Last observations remain when polling stops; removed endpoints require
explicit cleanup through the public health API. Timeout and status-policy options
remain the separate HTTP probe work item.

Unexpected filter/probe execution failures use the core contributor `airline-runner`
with `filter-<name>` or `probe-<name>` keys (non-identifier characters replaced by
hyphens). Successful later execution recovers only that core diagnostic. Classifier
results retain core's command-outcome identity. Element authors should choose their
own contributor names, rather than core's `airline-runner` namespace.

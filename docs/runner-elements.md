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

## Invocation and process contract

`runner` selects and validates work, then starts an invocation. `process` manages
that live invocation. `runner list` lists catalog definitions; `process list` lists
active invocations on the connected tmux server. A process ID is an opaque Airline
identity, not an OS PID. `process show <process-id>` shows its owning pane, mode,
supervisor and owned PIDs, state, and shell-quoted normalized specification. Never evaluate the
displayed specification as part of inspection.

| Mode | Subject | Standard streams | Completion |
|------|---------|------------------|------------|
| `run` | A command, or a probe with no command | Holds the caller's input and displays output | Command exits, or invocation is cancelled |
| `watch` | A probe | Background; stdin, stdout, stderr use `/dev/null` | Explicit stop or owner pane closes |

A probe-only `run` repeatedly observes until cancelled; it does not manufacture a
placeholder command. A command-bearing `run` may also select a filter and a probe.
A filter requires a command stream. A probe-only invocation has no command
termination to classify. The selected classifier is inactive in that case.

`watch` returns its process ID after validation, registration, and lifecycle startup.
The pane remains available for ordinary shell work. `run` stays in the foreground
and returns the command's original shell status, or a cancellation status for a
probe-only invocation. Both are listed and can be stopped through `process`.

`process stop <process-id>` requests cancellation of that invocation and waits for
cleanup. Airline signals the recorded PIDs directly and reports a failure when an
owned PID cannot be signaled or reaped. It does not walk the process table or claim
ownership of descendants created privately by an element. These are live records,
not history. A user-requested stop reports failures directly on the command output;
it does not create an additional problem claim.

The list is a snapshot. Stopping a syntactically valid ID whose invocation has
already finished succeeds with an `already finished` message, including repeated
stops. No completed-process history is retained, so an absent valid ID is treated
the same way. Malformed IDs remain usage errors.

Stop requests are stored under the invocation ID for the supervisor to consume.
The CLI does not signal a numeric PID from an old list result. When the supervisor
is gone, listing, showing, or stopping retires stale bookkeeping without signaling
recorded child PIDs; those numbers may have been reused. Child membership is
maintained by the supervisor as children are reaped. A missing child alone is not
an unexpected-failure verdict. Portable Bash liveness checks are snapshots, not
durable process-identity handles.

Every invocation belongs to a pane and ends when that pane is removed. Supervisors
check ownership while work is running, including during a blocked probe call. With
multiple invocations on a pane, ending one leaves status active while others remain.
The last command completion produces `result`; ending the last watch or cancelling
work clears status. These lifecycle changes do not recover element-owned claims.
If cleanup discovers that the owning pane is already gone, Airline cannot attach the
diagnostic to that pane and instead raises a server-global `airline-runner` problem
for the process. That problem remains visible for later inspection.
Uncatchable supervisor termination cannot guarantee cleanup; process records are
not a persistent job service or a restart mechanism.

Placement belongs to the invocation. A placed `run` retains its output pane on exit
and returns that pane ID to its launcher. A placed `watch` creates a normal usable
shell pane and returns the watch's process ID; `process show` identifies the pane.

## What the Bash host provides

Airline supplies original element argv, lifecycle/process IDs, stream descriptors,
and the reporting functions documented below. In the current pane, execution inherits
the invoking environment and working directory. A placed command run is launched
by tmux in the source pane's current directory and uses tmux's pane environment;
Airline passes its own executable location and tmux connection configuration across
that boundary. A placed watch inherits its launcher's environment and working
directory, and binds its reporting to the newly created pane.

Elements are trusted Bash and use ordinary Unix tools directly. Airline does not
supply a subprocess API, network client, disk spool, custom buffer, or universal
request timeout. A probe must bound its own external requests (for example, using
curl's timeout options). Airline owns cancellation of the invocation and its owned
children. Command and probe diagnostics retain their normal stdout/stderr meaning;
watch discards these streams, so operational observations must use the reporters.

Probe observations are sequential and do not overlap. The first starts immediately;
the interval is a delay after an observation finishes, not a fixed start-to-start
rate. Precedence is explicit invocation interval, composition interval, probe
metadata, then five seconds. Filters have invocation-local shell state. Probe calls
share the observation loop's shell state; validation state is never carried into
execution. Neither kind may assume state survives a new invocation.

## Stream copying

A filter reads copied command stdout until EOF. `--merge-stderr` includes stderr in
that copy while preserving the command's separate visible stdout and stderr
destinations. Separate stream pumps cannot promise the child's exact cross-stream
ordering. Probe output never enters the command's filter.

Copying uses Unix FIFOs, pipes, and `tee`. OS buffering and backpressure apply: a
slow filter can slow the command. Airline does not drop bytes to keep up and does
not spool output to disk. Temporary directories contain control files and FIFOs,
not stored command output. Pipe copying may affect a program's buffering and TTY
detection; it is not a transparent pseudo-terminal.

EOF means all selected writers have closed and buffered bytes have been consumed,
including a final unterminated line. Descendants that inherit output descriptors
keep the stream open. Normal completion drains the stream before publishing its
terminal filter result. Cancellation may interrupt observation and does not promise
a final verdict. An early-returning or failed filter leaves a drain reader behind
so it cannot truncate terminal output; unread input or nonzero action status causes
a separate runner problem. Filter failure does not change classifier policy or the
command's exit status.

## The three kinds

| Kind | Airline supplies | Element returns | Invoked |
|------|------------------|-----------------|---------|
| Classifier | exit status, signal, argv | one condition on stdout, or no verdict | once, when the child exits |
| Filter | child pid, health and problem functions, stdin, argv | publishes its own signals through the supplied functions | once; reads until EOF |
| Probe | lifecycle pid, health and problem functions, argv | publishes its own signals through the supplied functions | repeatedly, paced by core |

A classifier returns a condition for the completed command on stdout, or returns
successfully with no output to decline a verdict. Filters and
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

- A command-bearing `run` supplies an exit status and an output stream. All three
  kinds are meaningful. A probe-only `run` supplies repeated observations only.
- `watch` has no subject command or observed stream. Only a probe is meaningful, and
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
#| usage: [--expect <regex>] [--timeout <seconds>] [--connect-timeout <seconds>] <endpoint> [<endpoint>...]
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
    --expect)  … ;; #| <regex> — full status-code match; default 2[0-9][0-9]
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

A classifier returns one condition on stdout, or no verdict. Core validates that result and may
project it as its own command outcome; this function result does not give core
ownership of the classifier author's other signal claims. An element that cannot
load is rejected before execution, and an invalid classifier result is a core
contract diagnostic.

`conventional` is the default whenever a `run` omits `--classify`, including named
compositions and runs with a filter. `none` is an ordinary classifier that always
declines a verdict; it does not disable lifecycle management or other observers.
`conventional` maps zero to `ok`, other exits to `fail`, and SIGINT/SIGTERM to no
verdict. Other signals mean `fail`. Bash exposes a shell wait status, so statuses
above 128 carry the conventional `status - 128` signal interpretation; an explicit
exit 130/143 cannot be distinguished from those signal outcomes by this interface.
No verdict is not a successful health observation. At command startup Airline
retires its previous classifier outcome; silence at completion adds no new claim.

Filters and probes receive two function names, called as follows:

```bash
"$health"  <contributor> <key> <ok|warn|fail> [<message>...]
"$problem" <contributor> <key> <ok|warn|fail> [<message>...]
```

The functions bind the invocation's pane context. Health is stored on that pane;
problems carry that pane as their origin in the global ledger. This is equivalent to
`health set -t <pane>` and `problem set -t <pane>` in the current CLI grammar.
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
explicit cleanup through the public health API.

HTTP policy options precede the endpoints and apply to every endpoint in that poll:

| Option | Meaning | Default |
|--------|---------|---------|
| `--expect <regex>` | Bash extended regular expression matching the entire HTTP status code | `2[0-9][0-9]` |
| `--timeout <seconds>` | Curl total request budget, per endpoint | `5` |
| `--connect-timeout <seconds>` | Curl connection budget, within the total budget | `2` |

Timeouts accept positive integers or decimals such as `0.5`. Zero, negative values,
missing values, empty endpoints, and empty or malformed regular expressions fail
invocation validation before work starts. Repeated options use the last value.
Only successful curl requests with a status code from 100 through 599 can be healthy;
transport failures and invalid codes fail regardless of the expression. Expressions
are matched against the whole code: `204|503` accepts either code, whereas `20` does
not accept `200`. Quote expressions to prevent the invoking shell from interpreting them.

```bash
airline runner watch http --expect '204|503' --timeout 3 --connect-timeout 1 \
  https://example/health/live https://example/health/ready
```

The named HTTP composition forwards options and endpoints intact to the probe.
With no arguments it supplies the two localhost health endpoints. When arguments
are supplied, at least one explicit endpoint is required, including when setting
policy options. `probe describe http` lists the options alongside their defaults.

Unexpected filter/probe execution failures use the core contributor `airline-runner`
with `filter-<name>` or `probe-<name>` keys (non-identifier characters replaced by
hyphens). Successful later execution recovers only that core diagnostic. Classifier
results retain core's command-outcome identity. Element authors should choose their
own contributor names, rather than core's `airline-runner` namespace.

# Deferred proposal: C++ core and Lua catalogs

Status: an option to reassess after the current implementation settles. This is
not an accepted migration plan, a release requirement, or a change to the current
catalog contracts.

## Motivation and decision

The Bash implementation has clear architectural boundaries, but expressing them
requires discipline around shared function namespaces, callback names, string
tuples, argument preservation, and subshell behavior. A native implementation could
express these boundaries through ordinary types, records, containers, private
members, and direct return values. A `TmuxClient` could encapsulate the existing
mechanical layer and its transaction workspace.

Initialization has been reported to take more than one second on the maintainer's
machine. That observation motivates measurement; it does not establish where the
time goes or predict the speedup from changing languages. The current mechanical
layer already snapshots options and batches writes. A port can remove Bash work
and command substitutions while retaining costs from tmux subprocesses, server
work, and synchronization.

The largest downside is compatibility with existing catalog entries and
Airline-specific configuration expressed in Bash or tmux configuration files.
Existing shell callbacks and executable palette files would not automatically
become Lua entries. Native tmux configuration and format expressions can remain
native. Public CLI grammar and option names could be preserved, but the migration
boundary and any compatibility period would need an explicit decision.

Other costs include a compiler/build system, binary distribution across supported
platforms, embedding Lua, a maintained host API, and revalidating lifecycle behavior.
The clarity and maintenance gains matter most if core changes remain frequent. If
the implementation stabilizes, those gains alone may not justify a rewrite.

For now, document the option, collect repeatable performance measurements, and
continue using Bash. Reassess after actual maintenance demands and latency show
whether a migration would pay for itself. No migration date or performance promise
is set.

## Proposed boundary

Move application code outside the catalog to C++. Keep every catalog entry in Lua,
including shipped entries. Tiny installation or TPM launch shims may still be
necessary. C++ owns CLI validation, catalog discovery, tmux interaction, state,
rendering, transactions, process lifecycles, scheduling, and contract validation.
Lua owns extension declarations and interpretation policy.

Every catalog module exports a Lua table containing its metadata and the data or
functions required by its kind. Metadata, including option descriptions, is
structured data in that table. Core validates the exported table against the
common metadata schema and the kind's contract. Exact field names remain a design
detail; the module-table contract is part of this proposal.

| Catalog kind | Possible Lua contract |
|---|---|
| Palette | Export color-role data for validation and application |
| Adapter | Export a function receiving palette values and a scoped option writer |
| Layout | Export a function declaring segments and adapters, with helpers for adaptive selection |
| Classifier | Export a function receiving termination information and returning a condition |
| Filter | Export stream-consumer behavior that reports observations and retains per-invocation state |
| Probe | Export a function performing one bounded observation using host services and reporting its findings |
| Runner | Export a function returning selected elements, their argument lists, and an optional interval |

Catalog-specific helpers, such as TPM installation detection, remain Lua policy;
generic filesystem primitives can come from the host. Tmux format expressions
remain strings interpreted by tmux. A Lua source language does not require
reimplementing tmux's expression language.

Reading metadata requires loading the module and evaluating its top-level Lua code.
Name/path discovery can remain a filesystem operation, but listing summaries and
describing metadata use the exported tables. Modules should declare data and define
functions at load time; observation, configuration application, and process launch
belong in the functions core invokes for those purposes. This authoring contract
does not preserve the current guarantee of inspecting metadata without executing
entry code. Catalog modules remain trusted extensions.

## Runner support

Bash supplies convenient process execution, output capture, redirection, and exit
status handling. Lua entries would need equivalent generic host services. An
illustrative API, not a committed interface, is:

```lua
local result = ctx.exec({
    "curl", "--silent", "--output", "/dev/null",
    "--write-out", "%{http_code}", "--", endpoint,
}, { stdout = "capture", stderr = "inherit", timeout = 5 })
```

C++ would preserve argv boundaries, manage streams, return structured termination
information, and handle timeouts, cancellation, and cleanup. Lua chooses the
executable and arguments, interprets the result, and owns contributor names, keys,
diagnostics, and recovery. HTTP and TAP policy must not move into C++.

Classifiers and named compositions need no subprocess facilities. A TAP filter
could receive line and EOF callbacks with per-invocation state; general filters
also need byte/chunk access. The host must define buffering, backpressure, observer
failure, and concurrency so a slow filter or probe has deliberate lifecycle
behavior. Lua coroutines alone do not make blocking process operations concurrent.

The HTTP probe can continue invoking curl. Pipeline-heavy extensions would test
whether a generic pipeline API or explicit shell execution is needed. Avoid making
authors rebuild shell quoting and process supervision in every entry.

The standard Lua execution facilities are narrower than this proposed interface:
`os.execute` invokes a shell, while `io.popen` supplies a simple process stream.
Embedding allows the host to provide additional functions. See the
[Lua reference manual](https://www.lua.org/manual/5.4/manual.html).

## Contracts to preserve or explicitly reconsider

- Replace comment-parsed metadata and option annotations with each module's
  exported table. Metadata inspection evaluates module code, as described above;
  it does not invoke the module's observation or application functions merely to
  obtain metadata.
- Validation precedes process launch, topology changes, and lifecycle publication.
  Module state must not accidentally leak between validation and execution.
- Catalog entries remain trusted extensions; changing language does not make
  arbitrary extension code safe or reversible.
- Contributor observations and recovery remain separate from core diagnostics.
- Arguments, absent versus empty values, original command exit status, signals,
  copied output, and retained panes keep their defined behavior.
- HTTP's `--expect` currently accepts Bash extended regular expressions. Lua
  patterns are different; preserving that syntax requires a regex facility.
- Palette/layout staging and adapter replay must be considered explicitly;
  arbitrary effects of executable tmux palettes cannot simply become table data.

## Evidence for reconsideration

Use [performance measurements](performance.md) to track initialization and ordinary
operations on a stable machine and fixture. Separate fresh initialization from
idempotent initialization and CLI overhead. If latency remains material, profile
before attributing it to Bash or selecting a remedy.

Also assess how often core changes, whether Bash-specific problems recur, how much
compatibility users need, and whether the build/distribution cost is acceptable.
Catalog growth alone need not justify rewriting a stable core.

If the evidence supports a prototype, use two bounded vertical slices: initialization
through a Lua palette/layout/adapter, and command monitoring with Lua TAP filtering
and HTTP probing. Compare latency, contract behavior, and catalog authoring effort.
Decide on a broader migration only after those results are available.

# Signal lifecycles

Airline signals let a contributor expose retained state in the tmux window list.
They are not interchangeable notification styles. Each channel answers a different
question:

- **Status:** what is happening in this window that the user may want to inspect?
- **Health:** what observed condition is currently unhealthy in this window?
- **Problem:** what advertised capability can Airline or a contributor currently
  not provide?

The interfaces are deliberately coherent. Contributors set named state, normal
state is invisible, repeated reports are safe, and the most important current value
is projected into one badge. `clear` deletes retained state, `ack` hides retained
health or problem state without claiming recovery, and `show` inspects it. The exact
result still follows the meaning of each channel: status advances according to its
workflow phase, health may retain an acknowledged condition, and problem retains a
lifecycle ledger.

Problem is expected to be the least frequently used signal and has the richest
lifecycle. That complexity is justified by its meaning: a problem says that a
component cannot fulfill its contract, and it is visible server-wide. Airline must
not mistake acknowledgement or the disappearance of a reporter for demonstrated
recovery.

Signal choice follows meaning, not severity. A failed test or unreachable service
can be a `fail` health condition without becoming a problem. It becomes a problem
only when the contributor itself cannot provide the capability it advertises—for
example, because a required executable is unavailable.

## At a glance

| Signal | Meaning | Identity and scope | Values | Retention | Commands |
|--------|---------|--------------------|--------|-----------|----------|
| Status | The workflow phase of work whose details are visible in the pane | pane within one window | `active`, `result`, `attention` | Active work and input requests persist until the producer updates them; observed results are deleted | `set`, `clear`, `show` |
| Health | A currently observed domain condition | contributor and claim key within one window | `ok`, `warn`, `fail` | Active or acknowledged until recovery or clear | `set`, `ack`, `clear`, `show` |
| Problem | Failure to provide an advertised capability | contributor and problem key globally, with pane or session origins | `ok`, `warn`, `fail` plus lifecycle state | Claims until recovery, close, resolve, or clear; terminal state until a new report or clear | `set`, `close`, `ack`, `resolve`, `clear`, `show` |

Status uses `active < result < attention`: ongoing work, a result to inspect, and a
request for input. Health and problem use `ok < warn < fail`. `ok` is normal and
invisible; every retained `warn` or `fail` includes a diagnostic message.

Health and problem identify contributors explicitly. A contributor is a stable
software identity, while its key names a stable condition or capability. Severity
and diagnostic text are never part of identity. A contributor mutates only its own
claims; Airline validates framing but does not attempt to authenticate ownership.

## Identity and lifecycle authority

Status identity is structural and Airline-defined. The targeted pane is the key, so
there is exactly one workflow phase per pane and a contributor reports only its
current value. Airline derives the identity from tmux, projects it to the containing
window, and owns automatic observation of `result`. The producer remains responsible
for advancing `active` processing and `attention` after input.

Health and problem identity is semantic and contributor-defined. A contributor
chooses a stable key for each independent condition or capability it owns; this is a
domain identifier, not an Airline-issued token. The explicit contributor identity
allows multiple reporters to use the same key without collision, while stable keys
also allow one contributor to maintain several simultaneous claims. Airline owns
their storage, reduction, acknowledgement, and presentation, but does not assign
meaning to those keys.

Viewing a pane cannot demonstrate that a health condition recovered or that a
missing capability became available. Health and problem therefore require an
authoritative lifecycle event rather than advancing through observation. The
contributor reports current condition and recovery; problem origin hooks may record
that a reporter disappeared; and the user may acknowledge retained state without
claiming recovery.

| Signal | Identity owner | Identity | Normal transition authority |
|--------|----------------|----------|-----------------------------|
| Status | Airline, from tmux structure | pane | producer for `active` and `attention`; Airline for an observed `result` |
| Health | contributor | contributor + health key within a window | contributor reports condition and recovery; user may acknowledge |
| Problem | contributor | contributor + problem key globally, with pane or session origins | contributor reports condition and recovery or authoritatively resolves; hooks close origins; user may acknowledge |

## Status

```mermaid
stateDiagram-v2
    state "No entry" as None
    state "Active<br/>processing" as Active
    state "Result<br/>ready to view" as Result
    state "Attention<br/>waiting for input" as Attention

    [*] --> None
    None --> Active: set active
    None --> Result: set result
    None --> Attention: set attention
    Active --> Result: producer reports completion
    Active --> Attention: producer requests input
    Attention --> Active: producer reports input received
    Attention --> Result: producer reports completion
    Result --> Active: producer reports new work
    Result --> Attention: producer requests input
    Result --> None: clear after viewing
    Active --> None: clear
    Attention --> None: clear
    Result --> None: clear
```

Status is lightweight window-local workflow state with one entry per pane. The pane
is both its identity and its explanation: it contains the progress, result, or
interaction behind the badge. A contributor reduces any subprocesses or concurrent
tools it owns into this one user-visible pane phase rather than exposing process
identity through Airline.

The three values have different transition mechanisms. `active` means processing is
underway and remains until the producer reports a new phase. `attention` means the
workflow is waiting for input and remains until the producer observes that input.
`result` means processing has finished and its output is ready to view; observing the
window fulfills that signal's purpose. A runner's health claim separately describes
whether the completed result was `ok`, `warn`, or `fail`.

`set` creates or replaces the targeted pane's entry. Each effective set or clear
increments a revision counter owned by that pane. `show` includes every current pane
revision for general introspection.

Plain `clear` explicitly deletes the pane entry. Setting `result` also ensures that
Airline's observation hook is installed. When a pane loses focus, Airline supplies
the pane and its current revision to a private conditional operation that deletes
only that exact result revision. Other panes, `active`, `attention`, and any newer
state remain untouched. This deliberately requires the user to leave the pane before
its result is cleared; merely being visible is not treated as proof of observation.
Status has no acknowledged state or retained history after deletion. Contributors
normally advance active work and input requests themselves; they neither install the
observation hook nor handle revision tokens.

A window badge reduces all of its pane phases by user-action priority:
`active < result < attention`. Ongoing work is passive information, a completed
result is ready to inspect, and an input request blocks progress. This ordering is
presentation policy, not severity and not the order every individual workflow must
follow. Interactive processes such as coding agents are the motivating producer for
`attention`; Airline's non-interactive runner does not manufacture that phase.

## Health

```mermaid
stateDiagram-v2
    state "No claim<br/>(ok)" as Healthy
    state "Active<br/>(warn or fail)" as Active
    state "Acknowledged<br/>(hidden)" as Acknowledged

    [*] --> Healthy
    Healthy --> Active: set warn/fail
    Active --> Active: set warn/fail
    Active --> Acknowledged: ack
    Acknowledged --> Acknowledged: report same level
    Acknowledged --> Active: report different level
    Active --> Healthy: set ok or clear
    Acknowledged --> Healthy: set ok or clear
```

Health describes a successful observation of an unhealthy domain result. The
contributor is working well enough to report what it observed; the observed system
may be degraded or failed. Examples include a failed test, an unreachable endpoint,
or a service returning an unhealthy readiness state.

Each contributor and claim key identifies one condition in one window. `set warn`
or `set fail` makes the condition active and visible. `ack` hides the current level
without asserting recovery. Repeated observations at that same level refresh its
diagnostic but remain acknowledged; a change between `warn` and `fail` is a new
semantic state and becomes active again. `show` lists active health, while `show
--all` also includes acknowledged claims.

A later `set ok` demonstrates reporter recovery and removes the claim. `clear`
deletes it directly and has the same final state, but does not itself communicate a
new observation. Health retains acknowledged current state but no terminal history:
after recovery or clear, there is no claim.

Health is never consumed merely by leaving a window. Unlike status, the pane need
not contain its diagnostic, and attention says nothing about whether the observed
condition changed.

## Problem

```mermaid
stateDiagram-v2
    state "No problem" as None
    state "Active<br/>visible, one or more origin claims" as Active
    state "Acknowledged<br/>hidden, claims retained" as Acknowledged
    state "Closed<br/>reporters gone without recovery" as Closed
    state "Resolved<br/>recovery retained as history" as Resolved

    [*] --> None
    None --> Active: set warn/fail
    Active --> Active: add/update an origin
    Active --> Active: origin recovery/close while claims remain
    Active --> Acknowledged: ack
    Acknowledged --> Acknowledged: origin changes, same reduced level remains
    Acknowledged --> Active: reduced level changes
    Active --> Resolved: set ok removes final claim
    Acknowledged --> Resolved: set ok removes final claim
    Active --> Closed: close removes final claim
    Acknowledged --> Closed: close removes final claim
    Closed --> Active: new warn/fail report
    Resolved --> Active: new warn/fail report
    Active --> Resolved: resolve
    Acknowledged --> Resolved: resolve
    Closed --> Resolved: resolve
    Active --> None: clear
    Acknowledged --> None: clear
    Closed --> None: clear
    Resolved --> None: clear
```

A problem means that Airline or a contributor cannot provide an advertised
capability. Problems are global because the broken contract matters independently
of the window where it was discovered. The contributor and problem key identify the
capability; pane and session origins identify the reporters currently asserting
that it is unavailable.

The separate origin claims prevent one reporter from erasing another reporter's
observation. They also let Airline respond accurately when a pane or session exits.
This produces distinct lifecycle operations:

- `set ... warn|fail` adds or updates the current pane or session origin claim. A
  new report reopens `closed` or `resolved` history.
- `set ... ok` demonstrates recovery only for the current origin. If other claims
  remain, the problem follows their reduced level. Removing the final claim records
  the problem as `resolved`.
- `close` removes claims belonging to an origin that disappeared. If it removes the
  final claim, the problem becomes `closed`: retained history records that reporting
  stopped without claiming the capability recovered.
- `ack` hides an active problem without asserting recovery or removing its claims.
  Reports at the same reduced level remain acknowledged; a level change makes the
  problem active again.
- `resolve` is the contributor's authoritative assertion that the underlying
  capability is restored for the whole problem identity. It removes every origin
  claim and retains a `resolved` ledger entry with the last diagnostic.
- `clear` deletes the entire problem identity: current claims and all retained
  active, acknowledged, closed, or resolved history.

Use `set ... ok` when recovery is known only for one pane or session. Use `resolve`
when the contributor can verify the shared requirement itself. For example, a plugin
that reported a missing executable may resolve the problem after finding the
executable, because that verification establishes that its advertised capability is
available again. `ack` is never a recovery assertion, and `close` is never proof of
recovery. Use `clear` only when the retained lifecycle itself should be discarded.

`show` lists active, visible problems. `show --all` includes active, acknowledged,
closed, and resolved entries together with any current origins. The ledger is
retained current lifecycle state, not an append-only event log: a new failure report
reopens and replaces a closed or resolved terminal state.

Airline's own configuration and runner components follow the same contract as
external contributors. A configuration operation that succeeds reports recovery
for the session origin it just evaluated. A component that can authoritatively
verify a globally shared dependency may instead resolve the entire problem.

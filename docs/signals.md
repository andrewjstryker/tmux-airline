# Reporting signals

This guide is for plugin authors and users integrating jobs with Airline. For
ordinary installation and bar configuration, see the [README](../README.md).
Use `airline help status`, `airline help health`, and `airline help problem` for
command syntax. The [lifecycle reference](lifecycle-signals.md) explains retained
state, origin claims, acknowledgement, and recovery.

## Targets and scope

Airline maps its state onto tmux's normal scopes:

- Options set with `set -g @airline-*` are server-wide input, copied by a later
  configuration operation into that operation's session.
- The committed palette, segments, layout, and adapters are private to the invoking
  session and are read through the CLI.
- Session-public options written while evaluating palette/layout files are cleared;
  they are not another user configuration scope.
- Status and health originate in panes and are projected at their containing window.
  Health claims are stored on their pane, while status uses pane identity in its
  window collection. Their documented `-t` targets resolve the corresponding owner.
- Problems belong to the tmux server. A pane-hosted reporter may preserve its
  runtime origin with `problem set -t <pane-target>`.

A window entry has three layers, owned by two parties. **airline** owns the
entry's *color* (the name itself); **plugins** speak through two *badges* that
flank the name. They never collide.

```
 ○ 1:vim        ● 2:build ▲        ◆ 3:agent
 │   └name      │   └name  └health   │   └name
 └status        └status              └status  (needs you)
```

The **status badge** sits *left* of the name; the **health badge** sits *right*.
Because they're on opposite sides, their colors may overlap without ambiguity.

## Entry color (airline-owned): tmux modes

The window name's color is airline's alone — no plugin API. It reflects, in
order, **tmux modes** over the **baseline** (focused / last / normal):

| State                              | Color     |
|------------------------------------|-----------|
| A pane in the window is **zoomed** | `zoom`    |
| The active pane is in **copy mode**| `copy`    |
| `monitor-activity` is **on**       | `monitor` |

Precedence is **zoom > copy > monitor**. With no mode, the normal focused, last,
activity, and bell styling applies.

## Badges (plugin-owned): the `airline` CLI

Plugins drive badges through the **`airline` command** — the supported API. It
owns the underlying tmux options and validates input, so plugins never depend on
option-name conventions.

> **Finding the CLI.** airline publishes its own path in the `@airline-cli`
> tmux option on load, so a cooperating plugin never has to guess the install
> location. This bootstrap handle is the one managed option consumers read
> directly; compatibility information remains behind the public CLI:
>
> ```shell
> airline="$(tmux show -gqv @airline-cli)"
> if [ -n "$airline" ]; then
>   version="$("$airline" version)"
>   [ -n "$version" ] && "$airline" status set active
> fi
> ```
>
> The empty check doubles as an "is airline installed?" probe.

## Contributor identity

Health and problem reporters supply two distinct identifiers: a stable contributor
name and a claim key owned by that contributor. Airline does not maintain a plugin
registry or try to prove ownership, but it stores both fields so two independent
contributors can safely use the same claim key. For example, `tmux-online`
`connectivity` and `tmux-cpu` `connectivity` are separate claims.

Airline-owned configuration reports use contributor `airline` with the stable claim
keys `airline-layout` and `airline-palette`; palette and layout names themselves do
not gain contributor qualification. Runner extensions report as concrete contributors
such as `airline-tap` and `airline-http`, with author-owned claim keys. Core
classifier outcomes use identities such as `airline-runner-classifier-basic`.

The contributor contract is:

- use a stable software identity as the contributor and mutate only its claims;
- keep severity and diagnostic text out of the key so identity remains stable;
- include an instance in the claim key when concurrent instances report independently;
- use `ok` when a retained health claim recovers; reserve `clear` for destructive
  removal and `ack` for user acknowledgement;
- use `problem set ... ok` when the selected pane origin recovers, and
  `problem resolve` only when the contributor has verified that the underlying
  capability is restored for every origin represented by that problem;
- report an inability to provide the contributor's advertised capability as a
  problem, while successfully observed unhealthy domain state remains health.

Status is intentionally lighter. Each pane owns one workflow phase because the pane
itself contains the explanation. A contributor reduces any internal subprocesses or
tools into that pane-level state.
Health identity is contributor plus claim key within a pane. Problem identity is
contributor plus claim key globally, while Airline separately records the pane or
session origins currently asserting it. Contributors and keys must be nonempty and
contain neither whitespace nor `:`; the colon is reserved for private storage
framing.

**Status** (left) — one workflow phase per pane. Airline reduces every pane in the
window to its highest-priority phase:

```tmux
airline status set active      # ○ processing (amber)
airline status set result      # ● output ready (green) — outranks active
airline status set attention   # ◆ waiting for input (amber)
airline status clear
airline status show            # pane ids + current phases + revisions
```

Levels reduce by user-action priority: `active < result < attention`. Ongoing work
is passive information, completed output is ready to inspect, and an input request
blocks progress. This is presentation priority rather than severity. A window with
no status entry shows nothing.

**Health** (right) — a single condition glyph reduced from any number of claims;
airline shows the **worst**. `ok` (or no claim) shows
**nothing** — a clean right side means healthy:

```tmux
airline health set example-agent context fail "connection refused"     # ▲ broken (red)
airline health set example-build tests warn "tests are still running with failures"
# badge now shows one glyph at the worst level (fail)
airline health ack example-agent context     # user has seen this fail state
airline health set example-agent context ok  # recovery clears it; drops to warn
airline health show                         # contributor + key + condition
airline health show --all                   # include acknowledged health
```

Health and problem share the levels `ok < warn < fail`. `ok` means reporter
recovery: for health it removes the claim; for problem it resolves one origin and
records `resolved` history when the final origin recovers. `clear` reaches the same
empty health state through explicit deletion rather than a reported observation.
`warn` means the component degraded gracefully and can keep working; `fail` means it
could not recover and is broken. `warn` uses the palette's amber `alert` role; `fail`
uses its red `stress` role. Glyphs are fixed (a distinct shape per visible state, so
badges stay legible without color). Every retained `warn` or `fail` condition has a
diagnostic message. Health's optional `-t <pane-target>` precedes the keyed condition
tuple so the trailing message stays opaque. Messages are user-facing text supplied
by the reporter: Airline validates their framing but assigns them no meaning. Signal
commands place every option before their contributor, key, or value operands.

Status values are workflow phases with distinct transition mechanisms. `active`
remains while the producer is processing, and `attention` remains while the producer
is waiting for input. The producer advances either phase when its work changes.
`result` means processing has finished and the pane contains output ready to view.
Each effective status set or clear increments a counter owned by that pane. Setting
`result` ensures that Airline's focus hook is installed; contributors do not install
the hook or handle revision tokens. The hook uses a private revision-guarded callback,
so leaving a pane deletes only the exact result that was observed while leaving every
other pane, `active`, `attention`, and any newer result untouched. Merely being
visible in a window is not treated as proof of observation. Plain `status clear`
explicitly deletes the targeted pane's entry. `status show` includes the current
revision for general introspection. Producers normally advance active work and input
requests; an Airline-aware coding agent is the motivating interactive producer for
`attention`. Runner health separately communicates whether a completed result was
`ok`, `warn`, or `fail`.

Health and problem are never consumed by viewing a window. They expose explicit
`ack`, which retains the underlying condition but hides
its badge and omits it from normal `show`; `show --all` includes acknowledged state.
A message-only refresh at the same level remains acknowledged. Any `warn` / `fail`
level change resets acknowledgement and makes the new state visible. Reporter
recovery removes a health claim, so a later failure starts unacknowledged.

Because color and badges live on different layers, a window can show a mode
color, a health glyph, and a status glyph all at once without contention.

## Global problems

An airline-aware widget can fail gracefully and report why through the global
`problem` API. A problem means that Airline or one of its contributors cannot
provide an advertised capability; it is not window or pane attention. Active
problems are immediately visible in every initialized session. Airline reduces
their claims with the same `ok < warn < fail` severity ladder as health and shows
one aggregate glyph at the extreme right.

```shell
if ! command -v sensors >/dev/null 2>&1; then
  airline problem set tmux-cpu sensors warn "required program 'sensors' was not found"
  printf '?'
  exit 0
fi

# This pane can now provide the capability; withdraw only its claim.
airline problem set tmux-cpu sensors ok
```

By default, a CLI claim belongs to the current pane. Select another pane with
`problem set -t <pane-target> ...`. Session-origin claims are created internally
for palette and layout configuration failures.
Several panes and sessions may assert the same contributor/key pair independently;
`problem set ... ok` removes only the current origin's claim. Airline installs tmux
pane/session close hooks to retire claims when their origins disappear without
asserting recovery.

`problem show` lists only active problems. `problem ack <contributor> <key>`
acknowledges and hides the current level without discarding history or active claims.
A same-level diagnostic refresh remains acknowledged; a level change makes the
problem active again. Use `problem show --all [<contributor> [<key>]]` to inspect the
complete `active`, `acknowledged`, `closed`, and `resolved` lifecycle ledger and its
current origins.
`problem resolve <contributor> <key>` is an authoritative contributor recovery
operation: use it after verifying that the underlying capability is restored
globally. It removes every origin claim, including stale assertions that have not
run again, and retains a `resolved` ledger entry. If recovery is known only for one
pane, use `problem set [-t <pane-target>] ... ok` for that origin instead; the ledger
becomes `resolved` when the final claim recovers. `problem close` is normally
hook-driven, but is public so jobs may retire pane- or session-origin claims
explicitly without asserting recovery; its final claim produces `closed` history.
`problem clear <contributor> <key>` is destructive: it removes the ledger and every
active origin claim.

For the complete selection rules and lifecycle state diagrams, see
[Signal lifecycles](lifecycle-signals.md).

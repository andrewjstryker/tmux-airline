# Widgets

A widget is a trusted Bash catalog file that returns its own tmux format. It chooses
text, conditions, colors, and any observation job. Airline composes fragments in
layout order, restores the segment baseline around each fragment, and adds padding
and separators once per segment. TPM status plugins are not required.

```bash
#| summary: Prefix indicator
#| usage:
airline_widget_format() {
  (( $# == 0 )) || return 2
  printf '%s' '#[fg=#{@airline-active}]#{?client_prefix,PREFIX,}'
}
```

Register the containing directory with `airline widget register <dir>`. Use
`widget list` for discovery and `widget describe <name> [arguments...]` to inspect
metadata, availability, and the literal returned format. Inspection never starts
jobs. Place widgets through a layout:

```bash
airline_layout_configure() {
  "$1" segment left-out '#S'
  "$1" widget right-mid cpu --warn 70 --critical 90
  "$1" segment right-mid ' | '
  "$1" widget right-mid online --host example.com
  "$1" widget-optional right-out battery
}
```

`widget-optional` omits a widget only when its availability check returns 3. Missing
names, invalid arguments, and malformed formats fail the layout. Repeated placements
are independent instances. Switching layouts retires previous instances and their
claims. A global segment override applied with `session apply` retires only that
slot's widgets.

## Shipped widgets

| Name | Observation | Presentation and availability |
|---|---|---|
| `cpu` | Linux `/proc/stat`, minimum 5 seconds between observations | CPU utilization; warning 70%, critical 90%; `—` until a delta is available |
| `battery` | First readable Linux system battery in `/sys/class/power_supply`, every 30 seconds | Capacity percentage; alert at 30%, stress at 10%; omitted when hardware is absent |
| `online` | One ICMP echo to `--host`, default `1.1.1.1`, every 10 seconds | Filled/empty circle for reachable/unreachable; requires `ping` |
| `prefix` | Native `client_prefix` and `client_key_table` | Prefix or non-root key-table name; no process |

Online means the chosen host answered ICMP, not that every Internet service works.
Battery capacity is for one device, not an aggregate across multiple batteries.

CPU sums user, nice, system, idle, iowait, irq, softirq, and steal counters. Guest
counters are already included in user/nice and are not added again. Idle plus iowait
is treated as idle time. Counter resets, zero elapsed time, and the first observation
produce `—`; valid deltas produce a rounded utilization percentage.

## Optional observation runtime

Native-only widgets need just `airline_widget_format`. Sampled widgets can implement
`airline_widget_sample [arguments...]`, emit one scalar, and include `widget_job` in
their format. `widget_reading` returns the native expression for that instance's
cached scalar. Put palette references and conditional presentation in the format;
tmux does not recursively expand job output.

Format construction receives `AIRLINE_WIDGET_SESSION` (canonical session id) and
`AIRLINE_WIDGET_INSTANCE`. The worker also receives `AIRLINE_WIDGET_STATE_DIR`, a
private per-server/session/instance directory for baselines. Arguments retain their
boundaries. `widget_quote` quotes shell argv; `widget_literal` escapes literal `#`
characters for tmux. Helpers are available during format construction; sample code
runs in a separate Bash worker and should be self-contained.

Header `interval` sets a minimum sampling interval (default 5 seconds, at most
999999); `timeout` sets the execution budget (default 1 second, at most 999 and no
larger than the interval). Sampling requires `flock` and GNU `timeout`. A per-instance
lock prevents overlap. Sampling occurs outside the configuration transaction;
publication verifies the instance still belongs to the owning session. tmux redraw
cadence can make sampling less frequent than the interval.

Successful samples return status 0 and one line of at most 4096 bytes. Diagnostics
belong on stderr. The hosted runtime publishes `?` on a failed or timed-out sample
and reports an instance-specific `airline-widget` problem. Widgets choose how to
render `?` and initial empty values. The next successful sample recovers that claim.
Retirement waits for bounded sampling outside the configuration lock before closing
the claim and removing state. Session closure and subsequent initialization collect
departed-session caches.

Formats must be one line, at most 8192 bytes, with at most one trailing newline.
They may contain native tmux expressions, Unicode, and local style directives, but
no terminal controls or layout-level alignment/list/range directives. Source-time
code must be quiet; format construction must not sample or mutate tmux. Definitions
are trusted code, so these checks are contract validation, not a security sandbox.

## Migration

Replace `adapter use` declarations and plugin placeholder strings with `widget
<slot> <name> [arguments...]`. The old adapter CLI and catalog are removed; register
custom formats in the widget catalog. `prefix` replaces `prefix-highlight`.

Widgets read the effective palette directly from public session options such as
`#{@airline-primary}` and `#{@airline-alert}`. Palette changes and suspend/resume
update these options without replacing widget identities or CPU baselines. See
[palette configuration](palettes.md) and the [contract](widget-contract.md).

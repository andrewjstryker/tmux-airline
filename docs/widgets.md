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

Tmux 3.2 or newer is required for numeric meter comparisons.

| Name | Observation | Presentation and availability |
|---|---|---|
| `cpu` | Linux `/proc/stat`, minimum 5 seconds between observations | `=`, `≡`, `≣` at 30%/80%; independent warning colors at 70%/90%; `—` until a delta is available |
| `battery` | First readable Linux system battery in `/sys/class/power_supply`, every 30 seconds | Capacity level `▁`–`█` while discharging, `⚡` when charging/full/attached; `--display both` adds a separate status icon; omitted when hardware is absent |
| `online` | One ICMP echo to `--host`, default `1.1.1.1`, every 10 seconds | `●` in primary/stress color for reachable/unreachable, `—` before a reading; requires `ping` |
| `prefix` | Native client and pane state | Bracketed prefix key, Copy, Sync, or custom key-table badge; no process |

Online means the chosen host answered ICMP, not that every Internet service works.
Battery capacity is for one device, not an aggregate across multiple batteries.
Battery levels advance at 6%, 20%, 35%, 50%, 65%, 80%, and 95%, preserving the
adapter's meter. Levels use stress below 20%, alert below 50%, emphasized below
80%, and primary otherwise. Missing or unknown battery status retains the capacity meter; an unknown capacity
displays `—`. In `both` mode, the meter is followed by `🔋` when discharging or
`⚡` when charging/full/attached, with no status icon for unknown status.

Prefix precedence is prefix key, pane mode (`Copy`), synchronized panes (`Sync`),
then a non-root client key-table name. Badges use inner-bg foreground and active,
copy, or special backgrounds. Prefix displays tmux’s configured key (for example
`[C-b]`); `--show-copy off` and `--show-sync off` disable those two indicators.
The idle root key table produces no badge.

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

## Persistent defaults and placement overrides

Set global tmux options named `@airline-widget-<name>-<option>` in `tmux.conf`:

```tmux
set -g @airline-widget-cpu-warn 70
set -g @airline-widget-cpu-critical 90
set -g @airline-widget-cpu-meter-medium 30
set -g @airline-widget-cpu-meter-high 80
set -g @airline-widget-online-host example.com
set -g @airline-widget-online-timeout 3
set -g @airline-widget-battery-display compact
set -g @airline-widget-prefix-show-sync on
```

Precedence is explicit placement argument, nonempty global option, then widget
built-in default. These are global inputs; session-scoped options with the same
names are not consulted. An unset or empty global option uses the built-in default.
For example, `widget right-mid cpu --warn 80` overrides the global warning threshold
only for that placement. Repeated placements remain independent.

| Widget | Options and built-in defaults |
|---|---|
| `cpu` | `warn=70`, `critical=90`, `meter-medium=30`, `meter-high=80`, `low-icon==`, `medium-icon=≡`, `high-icon=≣` |
| `battery` | `display=compact` (`compact` or `both`), `charging-icon=⚡`, `discharging-icon=🔋` (used in `both` mode) |
| `online` | `host=1.1.1.1`, `timeout=1` (integer seconds, 1–8), `online-icon=●`, `offline-icon=●` |
| `prefix` | `show-copy=on`, `show-sync=on` (each `on` or `off`) |

Every option also has a corresponding `--<option> <value>` placement argument.
CPU thresholds are integers from 0 to 100; warn must not exceed critical, and
meter-medium must not exceed meter-high. Meter thresholds choose glyphs; warning
thresholds choose colors. Icons are literal text, not tmux formats.

Online's timeout is the Linux ping reply timeout. The hosted worker has a fixed
10-second execution budget, including DNS resolution. A hostname exercises DNS;
an IP address does not. A failed probe reports an Airline problem and displays `—`;
a completed probe that receives no reply displays the offline icon.

Defaults are resolved and validated when a layout is loaded. The same resolved
argument vector goes to format construction, availability checks, and every sample
for that instance. Changing a global option does not change an already loaded
instance. Reload the layout after changing defaults, for example `airline layout use
adaptive` (or `airline layout load <path>` for a file). Reloading replaces instances
and resets CPU baselines. `session apply`, palette changes, and suspend/resume do not
reload widget policy. Invalid effective options reject a candidate layout, including
optional placements, leaving the previously loaded layout intact.

`widget describe <name> [arguments...]` reports `effective-arguments` using the current
global defaults and supplied overrides, plus the resulting format. It does not
sample or modify existing instances. Layout inspection uses the same resolution.

Custom widgets opt into this policy with an `options` metadata field containing
space-separated long option names, and one `default-<option>` field per option.
All declared options take one value. The host supplies each option once, in metadata
order, preserving argument boundaries. Widgets validate values in their format
function; their sampler receives the captured arguments without reading global
options. Widgets without `options` metadata keep their existing argv contract.
`widget_text` escapes literal text embedded in a native conditional, including icons.
Sampling intervals and execution budgets remain definition metadata; there is no
shared device-selection or refresh-policy option.

## Migration

Replace `adapter use` declarations and plugin placeholder strings with `widget
<slot> <name> [arguments...]`. The old adapter CLI and catalog are removed; register
custom formats in the widget catalog. `prefix` replaces `prefix-highlight`.
The adaptive and full layouts place online at left-mid, prefix at right-in, CPU at
right-mid, and battery after the date at right-out. Optional widgets are selected by
capability availability, not by TPM installation.

Widgets read the effective palette directly from public session options such as
`#{@airline-primary}` and `#{@airline-alert}`. Palette changes and suspend/resume
update these options without replacing widget identities or CPU baselines. See
[palette configuration](palettes.md) and the [contract](widget-contract.md).

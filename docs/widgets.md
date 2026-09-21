# Widgets

A widget is a trusted catalog entry with a `.sh` format definition and, when it needs
external data, an extensionless runtime executable with the same logical name. The
format definition returns one tmux status-format fragment. It assumes that Airline
has already established the segment's `fg` and `bg`; it may change those values, but
must restore them before its expression ends. Airline publishes each requested
widget expression in a private session option; tmux expands it through native `E:`
references. Airline adds padding and separators once per segment. Tmux owns status refreshes;
Airline supplies no widget scheduler or stateful runtime.

```bash
#| summary: Prefix indicator
#| usage:
airline_widget_format() { # <segment-fg> <segment-bg>
  local fg="$1" bg="$2"
  shift 2
  printf '%s' '#{?client_prefix,PREFIX,}'
}
```

Register the containing directory with `airline widget register <dir>`. Use
`widget list` for discovery and `widget describe <name>` to inspect
metadata, availability, and the literal returned format. Inspection never starts
jobs. Place widgets through a layout:

```bash
airline_layout_configure() {
  "$1" segment left-out '#S'
  "$1" segment right-mid '#{E:@airline--widget-cpu} | #{E:@airline--widget-online}'
  "$1" segment right-out '#{E:@airline--widget-battery}#{E:@airline--widget-power}'
}
```

A requested widget that returns unavailable (status 3) reports a warn problem and
contributes no content. Reloading the layout rechecks availability and recovers the
same placement's problem when it becomes available.
Missing names, invalid arguments, and malformed formats report a failure through
the problem service and leave that widget position empty. Other segment content
continues to render. Repeated placements share one expression and configuration, with placement-specific claims. Replacing a
layout retires removed placements and their claims. A global segment override
applied with `session apply` retires only that slot's widgets.

## Shipped widgets

Tmux 3.2 or newer is required for numeric meter comparisons.

| Name | Observation | Presentation and availability |
|---|---|---|
| `cpu` | sibling `cpu` executable reports a current usage snapshot | low, medium, or high level using configurable thresholds |
| `battery` | sibling `battery` executable reads the first readable Linux system battery | Capacity level `▁`–`█`, colored by charge level |
| `power` | sibling `power` executable reads the first readable Linux system battery | `🔋` while discharging and `⚡` when charging/full/attached |
| `online` | sibling `online` executable performs one fast ICMP check | `●` in primary/stress color for reachable/unreachable; requires `ping` |
| `prefix` | Native client and pane state | Prefix, Copy, Sync, or custom key-table badge; no process |
| `problem` | sibling `problem` executable reports `airline problem show --level` | Alert-colored `△` for warn, blinking stress-colored `▲` for fail; hidden when clear |

Online means the chosen host answered ICMP, not that every Internet service works.
Battery capacity and power source are independent widgets for one device, not an
aggregate across multiple batteries. Battery levels advance at 6%, 20%, 35%, 50%,
65%, 80%, and 95%, preserving the adapter's meter. Levels use stress below 20%,
alert below 50%, emphasized below 80%, and primary otherwise. An unknown capacity
displays `—`; an unknown power source displays `—`.

Prefix precedence is `Prefix`, pane mode (`Copy`), synchronized panes (`Sync`), then
a non-root client key-table name. Badges use inner-bg foreground and active, copy, or
special backgrounds. `--show-copy off` and `--show-sync off` disable those two
indicators.
The idle root key table produces no badge.

The CPU widget reports a current snapshot and reduces it to three presentation levels.
It does not provide a detailed monitor or retain historical state in Airline. If its
snapshot tool is unavailable, the widget emits an empty fragment and reports a warn
problem because it cannot fill its advertised contract. CPU level is display data; it
does not create a health claim or an overload problem. A user who needs detailed CPU
information should use a dedicated monitor such as `btop`.

## Runtime executable

The optional extensionless executable `<name>` is invoked directly by tmux through a
`#()` expression emitted by `<name>.sh`. It receives the resolved observation
arguments and emits one scalar value, text or numeric, on one line. It must be
stateless, quick, and quiet except for that value. It must not call Airline, write
tmux options, create Airline-managed files, lock, sleep, or schedule work. Tmux's
`status-interval` is the only refresh contract.

Airline does not cache, throttle, timeout, retry, supervise, or redraw a runtime
executable. A third-party widget may implement private optimizations, but those are
outside the Airline contract. A supplied widget that needs historical state or a
scheduler is not an Airline catalog widget until it is redesigned.

Formats must be one line, at most 8192 bytes, with at most one trailing newline.
They may contain native tmux expressions, Unicode, and local style directives, but
no terminal controls or layout-level alignment/list/range directives. Source-time
code must be quiet; format construction must not sample or mutate tmux. Definitions
are trusted code, so these checks are contract validation, not a security sandbox.

## Configuration through tmux options

Set global tmux options named `@airline-widget-<name>-<option>` in a tmux `.conf` file:

```tmux
set -g @airline-widget-cpu-medium 60
set -g @airline-widget-cpu-high 85
set -g @airline-widget-online-host example.com
set -g @airline-widget-online-timeout 3
set -g @airline-widget-power-connected-icon 'AC'
set -g @airline-widget-prefix-show-sync on
```

A nonempty global option overrides the widget's built-in default. Session-scoped
options with the same names are not consulted. An unset or empty global option
uses the built-in default. These options are the only parameter interface;
placements and `widget describe` do not accept argument overrides.

| Widget | Options and built-in defaults |
|---|---|
| `cpu` | `medium=60`, `high=85`, `low-icon==`, `medium-icon=≡`, `high-icon=≣` |
| `battery` | no options |
| `power` | `battery-icon=🔋`, `connected-icon=⚡` |
| `online` | `host=1.1.1.1`, `timeout=1` (integer seconds, 1–8), `online-icon=●`, `offline-icon=●` |
| `prefix` | `show-copy=on`, `show-sync=on` (each `on` or `off`) |

CPU thresholds are integers from 0 to 100; medium must not exceed high. Thresholds
choose the three display levels; they do not create health or problem claims. Icons
are literal text, not tmux formats.

Online's timeout is the command's own request timeout. A hostname exercises DNS; an
IP address does not. The runtime executable owns its failure and unavailable-data
presentation; Airline does not turn runtime stderr into a problem or impose a second
timeout.

Each widget reads and validates its own public options while constructing its
expression. It supplies any arguments needed by its runtime companion through
`widget_runtime`. Airline neither interprets widget option metadata nor translates
options into arguments. Changing an option requires reloading the layout, for
example `airline layout use full`. Invalid values leave that widget's expression
empty and report a problem; other segment content continues to render.

`widget describe <name>` invokes the same format function and reports availability
and the generated expression. Inspection reads public options but does not sample
or change configuration or problem claims.

A custom widget owns its `@airline-widget-<name>-...` namespace, defaults, and
validation. Read options directly with `tmux show-option -gqv` inside the format
function, not at source time. For example:

```bash
airline_widget_format() {
  local fg="$1" bg="$2" icon
  icon="$(tmux show-option -gqv @airline-widget-example-icon)" || return
  icon="${icon:-READY}"
  printf '%s' "$(widget_text "$icon")"
}
```

Unset or empty options use defaults chosen by the widget. Treat values as data;
quote them and escape literal text inserted into tmux formats. Widgets may read
only their own public configuration; mutation and private-state access remain
Airline's responsibility. No `options` or `default-*` metadata is needed.

## Migration

Replace standalone `widget` / `widget-optional` declarations, `adapter use`, and
the earlier `{{widget ...}}` placeholders with native
`#{E:@airline--widget-<name>}` references inside segment strings. Move inline
arguments to `@airline-widget-<name>-<option>` tmux options.
Combine formerly appended fragments into one string per segment. The old adapter
CLI and catalog are removed; register custom formats in the widget catalog. `prefix` replaces `prefix-highlight`.
The full layout places online at left-mid, prefix at right-in, CPU at right-mid,
and battery followed by power after the date at right-out. Unavailable requested
widgets report through the problem service.

Published widgets receive `default` for `fg` and `bg`; a native style wrapper
captures and restores each placement’s surrounding colors and attributes. Airline's
palette contract is exposed through session options such as
`#{@airline-palette-primary}` and `#{@airline-palette-alert}`. A widget that changes
either style must restore the supplied values before its fragment ends. Palette
changes update the session options and cause Airline to render the segment again. See
[palette configuration](palettes.md) and the [contract](widget-contract.md).

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
  "$1" segment right-mid '#{E:@airline--widget-online} #{E:@airline--widget-cpu} #{E:@airline--widget-power}'
  "$1" segment left-in '#{E:@airline--widget-problem}'
  "$1" segment right-out '%H:%M'
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

Tmux 3.2 or newer is required for numeric threshold comparisons.

| Name | Observation | Presentation and availability |
|---|---|---|
| `cpu` | sibling `cpu` executable reports a current usage snapshot | low, medium, or high level using configurable thresholds |
| `power` | sibling `power` executable reads state and capacity from the first readable Linux system battery | Charge-colored `BAT`, `CHG`, or `AC`; corresponding glyphs in Nerd Font mode |
| `online` | sibling `online` executable reads NetworkManager connectivity and physical default routes | `LAN`, `WiFi`, or `OFF`; requires `nmcli` and `ip` |
| `prefix` | Native client and pane state | Prefix, Copy, Sync, or custom key-table badge; no process |
| `problem` | sibling `problem` executable reports `airline problem show --level` | Alert-colored `WARN`, blinking stress-colored `FAIL`; corresponding glyphs in Nerd Font mode; no content when clear; the containing slot retains its normal padding |

Online uses NetworkManager's existing connectivity observation, without triggering
a probe. Wired and wireless use primary for full connectivity and alert for limited
access or a captive portal. Disconnected uses stress. Unknown observations,
unsupported connection types, or runtime query failures display `—` in primary.
This requires a running NetworkManager; connectivity accuracy and freshness depend
on its configuration. See [nmcli connectivity states](https://networkmanager.dev/docs/api/latest/nmcli.html).

When several physical connections are active, the lowest-metric physical default
route selects wired or wireless (IPv4 first, then IPv6). VPN/tunnel devices do not
replace that identity. For limited connectivity without a default route, the first
connected wired/wireless device is used. Complex bridges, policy routing, and
non-Ethernet/non-Wi-Fi transports are not resolved by this widget; unrecognized
routes yield unknown rather than a guessed connection type.

Power represents one device, not an aggregate across multiple batteries. It shows
no meter or percentage. Discharging uses stress below 20%, alert from 20–49%,
emphasized from 50–89%, and primary from 90%. Charging and connected without
charging both use emphasized below 90% and primary from 90%; neither uses alert
or stress, including when an intentional charge limit holds capacity below 90%.
A battery reporting discharging uses the battery icon and colors even when attached.
Unknown status, or missing/invalid capacity, displays
`—` in primary. Host notifications remain responsible for urgent battery warnings.

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

## Icons and text

Built-in widgets use short text by default. To require Nerd Font glyphs, set:

```tmux
set -g @airline-nerd-fonts on
```

The option accepts `on` or `off`; unset or empty means `off`. Airline reads it
once per layout construction and shares the resolved choice with every widget.
There are no per-widget icon overrides or runtime font checks. Install a Nerd Font
in the terminal before enabling it, and reload the layout to apply a change.
Invalid values reject the candidate layout without replacing the active one.
Standalone `widget describe` resolves the same option once for inspection.

| Subject | Text | Nerd Font icon names |
|---|---|---|
| Network | `LAN`, `WiFi`, `OFF` | `nf-md-ethernet`, `nf-md-wifi`, `nf-md-lan_disconnect` |
| CPU | `CPU` | `nf-oct-cpu` |
| Power | `BAT`, `CHG`, `AC` | `nf-md-battery`, `nf-md-battery_charging`, `nf-md-power_plug` |
| Problem | `WARN`, `FAIL` | `nf-fa-warning`, `nf-fa-times_circle` |

Shapes identify the subject or source; colors carry the same meaning in both modes.
Prefix/mode badges remain text. Unknown readings remain `—`.
For different symbols or presentation policies, register a custom widget.

## Configuration through tmux options

Set global tmux options named `@airline-widget-<name>-<option>` in a tmux `.conf` file:

```tmux
set -g @airline-widget-cpu-medium 60
set -g @airline-widget-cpu-high 85
set -g @airline-widget-prefix-show-sync on
```

A nonempty global option overrides the widget's built-in default. Session-scoped
options with the same names are not consulted. An unset or empty global option
uses the built-in default. These options are the only parameter interface;
placements and `widget describe` do not accept argument overrides.

| Widget | Options and built-in defaults |
|---|---|
| `cpu` | `medium=60`, `high=85` |
| `power` | none |
| `online` | none |
| `prefix` | `show-copy=on`, `show-sync=on` (each `on` or `off`) |

CPU thresholds are integers from 0 to 100; medium must not exceed high. Thresholds
choose the three display levels; they do not create health or problem claims.

Each widget with additional options reads and validates them while constructing its
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

The `battery` meter has been replaced by the combined `power` widget. Replace
`#{E:@airline--widget-battery}` (or the old battery/power pair) with
`#{E:@airline--widget-power}`.

Built-in per-widget icon options have been removed. Use `@airline-nerd-fonts`
for the shared text/glyph choice or write a custom widget. The `online` widget
keeps its catalog name but now uses NetworkManager and `ip`; its former host
and timeout options have been removed.

Replace standalone `widget` / `widget-optional` declarations, `adapter use`, and
the earlier `{{widget ...}}` placeholders with native
`#{E:@airline--widget-<name>}` references inside segment strings. Move inline
arguments to `@airline-widget-<name>-<option>` tmux options.
Combine formerly appended fragments into one string per segment. The old adapter
CLI and catalog are removed; register custom formats in the widget catalog. `prefix` replaces `prefix-highlight`.
The full layout keeps host/session context on the left, prefix at right-in,
network/CPU/power together at right-mid, problems at left-in, and date/time at right-out.
All shipped layouts place problems at left-in. The widget emits nothing when
clear and grows naturally to show a warning or failure. The renderer keeps normal
padding around configured slots even when their widgets are quiet; unconfigured
slots retain only their chevrons. A problem appearing can shift the window list,
providing an additional visual cue. Unavailable requested
widgets report through the problem service.

Published widgets receive `default` for `fg` and `bg`; a native style wrapper
captures and restores each placement’s surrounding colors and attributes. Airline's
palette contract is exposed through session options such as
`#{@airline-palette-primary}` and `#{@airline-palette-alert}`. A widget that changes
either style must restore the supplied values before its fragment ends. Palette
changes update the session options and cause Airline to render the segment again. See
[palette configuration](palettes.md) and the [contract](widget-contract.md).

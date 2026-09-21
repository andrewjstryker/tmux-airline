# Widgets

A widget is a trusted catalog entry with a `.sh` format definition and, when it needs
external data, an extensionless runtime executable with the same logical name. The
format definition returns one tmux status-format fragment. It assumes that Airline
has already established the segment's `fg` and `bg`; it may change those values, but
must restore them before its expression ends. Airline composes fragments in layout
order and adds padding and separators once per segment. Tmux owns status refreshes;
Airline supplies no widget scheduler or stateful runtime.

```bash
#| summary: Prefix indicator
#| usage:
airline_widget_format() { # <segment-fg> <segment-bg> [<widget-args>...]
  local fg="$1" bg="$2"
  shift 2
  printf '%s' '#{?client_prefix,PREFIX,}'
}
```

Register the containing directory with `airline widget register <dir>`. Use
`widget list` for discovery and `widget describe <name> [arguments...]` to inspect
metadata, availability, and the literal returned format. Inspection never starts
jobs. Place widgets through a layout:

```bash
airline_layout_configure() {
  "$1" segment left-out '#S'
  "$1" widget right-mid cpu --medium 60 --high 85
  "$1" segment right-mid ' | '
  "$1" widget right-mid online --host example.com
  "$1" widget-optional right-out battery
  "$1" widget-optional right-out power
}
```

`widget-optional` omits a widget only when its availability check returns 3. A required
widget that returns unavailable reports a warn problem and contributes no fragment.
Missing names, invalid arguments, and malformed formats fail the layout. Repeated placements
are independent instances. Switching layouts retires previous instances and their
claims. A global segment override applied with `session apply` retires only that
slot's widgets.

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

## Persistent defaults and placement overrides

Set global tmux options named `@airline-widget-<name>-<option>` in a tmux `.conf` file:

```tmux
set -g @airline-widget-cpu-medium 60
set -g @airline-widget-cpu-high 85
set -g @airline-widget-online-host example.com
set -g @airline-widget-online-timeout 3
set -g @airline-widget-power-connected-icon 'AC'
set -g @airline-widget-prefix-show-sync on
```

Precedence is explicit placement argument, nonempty global option, then widget
built-in default. These are global inputs; session-scoped options with the same
names are not consulted. An unset or empty global option uses the built-in default.
For example, `widget right-mid cpu --medium 70` overrides the global medium threshold
only for that placement. Repeated placements remain independent.

| Widget | Options and built-in defaults |
|---|---|
| `cpu` | `medium=60`, `high=85`, `low-icon==`, `medium-icon=≡`, `high-icon=≣` |
| `battery` | no options |
| `power` | `battery-icon=🔋`, `connected-icon=⚡` |
| `online` | `host=1.1.1.1`, `timeout=1` (integer seconds, 1–8), `online-icon=●`, `offline-icon=●` |
| `prefix` | `show-copy=on`, `show-sync=on` (each `on` or `off`) |

Every option also has a corresponding `--<option> <value>` placement argument.
CPU thresholds are integers from 0 to 100; medium must not exceed high. Thresholds
choose the three display levels; they do not create health or problem claims. Icons
are literal text, not tmux formats.

Online's timeout is the command's own request timeout. A hostname exercises DNS; an
IP address does not. The runtime executable owns its failure and unavailable-data
presentation; Airline does not turn runtime stderr into a problem or impose a second
timeout.

Defaults are resolved and validated when a layout is loaded. The same resolved
argument vector goes to format construction and, when present, the runtime companion.
Changing a global option does not change an already composed format. Reload the layout
after changing defaults, for example `airline layout use full` (or `airline layout
load <path>` for a file). Invalid effective options reject a candidate layout,
including optional placements, leaving the previously loaded layout intact.

`widget describe <name> [arguments...]` reports `effective-arguments` using the current
global defaults and supplied overrides, plus the resulting format. It does not
sample or modify existing instances. Layout inspection uses the same resolution.

Custom widgets opt into this policy with an `options` metadata field containing
space-separated long option names, and one `default-<option>` field per option.
All declared options take one value. The host supplies each option once, in metadata
order, preserving argument boundaries. Widgets validate values in their format
function; their runtime companion receives the captured observation arguments.
Widgets without `options` metadata keep their existing argv contract. There is no
shared Airline refresh-policy option.

## Migration

Replace `adapter use` declarations and plugin placeholder strings with `widget
<slot> <name> [arguments...]`. The old adapter CLI and catalog are removed; register
custom formats in the widget catalog. `prefix` replaces `prefix-highlight`.
The full layout places online at left-mid, prefix at right-in, CPU at right-mid,
and battery followed by power after the date at right-out. Optional widgets are
selected by capability availability, not by TPM installation.

Widgets receive the segment `fg` and `bg` from `airline_widget_format`. Airline's
palette contract is exposed through session options such as
`#{@airline-palette-primary}` and `#{@airline-palette-alert}`. A widget that changes
either style must restore the supplied values before its fragment ends. Palette
changes update the session options and cause Airline to render the segment again. See
[palette configuration](palettes.md) and the [contract](widget-contract.md).

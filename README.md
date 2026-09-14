# tmux-airline

A tmux status line inspired by vim-airline. Powerline-style chevrons, a layered
color hierarchy, swappable palettes, and a small CLI that lets plugins and your
own config drive the bar.

<p align="center">
  <img src="airline-screenshot.png" alt="tmux-airline screenshot" width="800">
</p>

Features:

- Three-tier status bar with powerline chevrons
- Swappable color **palettes** (dark, light, Solarized) — or your own
- Composable **layouts** that arrange the bar, plus a CLI to drive segments and
  per-window badges
- Native **widgets** for CPU level, battery, reachability, and prefix state, with
  persistent defaults and colors from the active palette
- Suspend/resume for nested tmux sessions

## Installation

This plugin requires **tmux 3.2+** and Bash 4.3+ (for associative arrays and
namerefs). The online runtime requires `ping`; battery data currently supports
Linux.

Tmux 3.2 supplies the numeric format comparisons used by CPU and battery meters.
Older versions cannot render those thresholds correctly.

### With [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm) (recommended)

Add to `.tmux.conf`:

```tmux
set -g @plugin 'andrewjstryker/tmux-airline'
```

Press `<prefix> + I` to install.

### Manual

```shell
git clone https://github.com/andrewjstryker/tmux-airline ~/clone/path
```

Add to the bottom of `.tmux.conf`:

```tmux
run-shell ~/clone/path/airline.tmux
```

Then reload:

```shell
tmux source-file ~/.tmux.conf
```

`airline.tmux` initializes the plugin and exposes the `airline` CLI. It binds
**no keys** — you wire your own where needed (see *Nested sessions* below).

### Put `airline` on your PATH

From the plugin directory, install its small launcher into `~/.local/bin`:

```shell
make install
```

Ensure `~/.local/bin` is on your `PATH`. To use another location, set `PREFIX`
or `BINDIR`:

```shell
make install PREFIX="$HOME"
make install BINDIR="$HOME/bin"
```

The launcher finds the active plugin through tmux, so it keeps working if TPM
moves the plugin directory. Tmux-airline must be initialized in the tmux server;
otherwise the launcher prints an actionable error. The same install places Bash
and Zsh completions under the prefix's standard `share` directories. Your shell
or completion manager must include those directories in its normal completion
search path.

## Core concepts

Choose a palette for colors, a layout for arrangement, and widgets for live content. Segments hold the contents of individual blocks:

| Concept     | What it is                                                        | You change it with            |
|-------------|-------------------------------------------------------------------|-------------------------------|
| **palette** | The colors — a set of named roles (`inner-bg`, `active`, `ok`, …) | `palette use`, or session option edits    |
| **segment** | One powerline block's content, in a fixed slot                    | a layout, or `set -g`         |
| **layout**  | A composition that fills slots with ordered fragments           | `layout use`                  |
| **widget** | A stateless tmux format fragment with an optional scalar runtime companion | a layout |

Palette roles are public session options, so widgets can read `#{@airline-palette-primary}`
directly. Global colors seed new sessions. For an initialized session, edit its
palette options and run `airline session apply`. Segment overrides remain global
inputs applied to the invoking session.

The configuration catalogs share a small set of verbs:

| Verb | Purpose |
|------|---------|
| `list` | Discover available names. |
| `describe <name>` | Inspect an entry before choosing it; palettes and layouts include evaluated contents. |
| `use <name>` | Apply a named palette or layout. |
| `load <file>` | Apply a palette or layout file without registering it. |
| `register <dir>` | Add a search directory; its names can shadow shipped entries. |
| `show` | Inspect active palette/layout configuration; widgets appear in `session show`. |

For example:

```shell
airline palette list
airline palette describe dark
airline palette use dark
airline layout use full
airline session show
```

For exact options, use `airline help`, `airline help palette`, or
`airline help palette use`. Bash and Zsh completions follow the same grammar.

## Palettes

A palette is a set of named color **roles**. The bar, badges, and window colors
all reference roles, never raw colors — so swapping the palette recolors
everything at once.

### Backgrounds — the three chevron tiers

| Role        | Where                          |
|-------------|--------------------------------|
| `outer-bg`  | Left/right edge blocks         |
| `middle-bg` | The blocks one step in         |
| `inner-bg`  | Window list / center           |

### Content colors — text by visual weight

| Role         | Used for                      |
|--------------|-------------------------------|
| `secondary`  | Default / low-priority text   |
| `primary`    | Normal text                   |
| `emphasized` | Section labels, active text   |

### Semantic roles — color by meaning

| Role       | Meaning                        |
|------------|--------------------------------|
| `active`   | Current window, active pane    |
| `special`  | Clock, special modes           |
| `ok`       | Success / completion (green)   |
| `alert`    | Activity, degraded (amber)     |
| `stress`   | Bell, critical (red)           |
| `zoom`     | Zoomed pane indicator          |
| `copy`     | Copy mode indicator            |
| `monitor`  | Monitor mode indicator         |

`ok`/`alert`/`stress` form a green/amber/red triad. `ok` is for **discrete
success** (a job or agent that *finished well*) — a meter's "good" state is just
the normal baseline, so only event-based signals have a distinct "succeeded"
state to paint green.

### Choosing and overriding a palette

Airline ships several palettes and picks `default` on first run. Switch with
`palette use` — it reloads the colors and re-applies the bar:

```tmux
airline palette use dark
```

| Palette           | Description                                     |
|-------------------|-------------------------------------------------|
| `default`         | Airline's shipped look (256-color dark)         |
| `dark`            | Neutral dark, explicit 256-color codes          |
| `light`           | Neutral light, explicit 256-color codes         |
| `solarized-dark`  | Solarized dark (assumes a Solarized terminal)   |
| `solarized-light` | Solarized light (assumes a Solarized terminal)  |

`airline palette list` lists what's on the search path; `airline palette
show` prints the active palette and every role; `airline palette show name`
prints just the active name (for scripts).

To override a color, write its session option and apply from that session:

```shell
tmux set-option @airline-palette-active colour201
airline session apply
```

This clears the palette name. `palette show` reads the effective public colors,
including dimmed colors while suspended. Apply manual edits before resuming so
Airline captures them in its restoration palette. Global colors are initialization
defaults only; selecting a palette does not change another session or the globals.
Use `palette use <name>` to restore a complete named palette.

A custom palette is a tmux file containing
`set-option @airline-palette-<role> <color>` lines; `layouts/palettes/default.conf` is a complete
example. Put the file in a directory, register that directory, and select the
palette by filename. A registered name shadows a shipped one:

```tmux
airline palette register ~/.config/airline/palettes
airline palette use my-palette
```

For a one-off file, use `airline palette load /path/to/palette`. See
[palette selection and inspection](docs/palettes.md) for file requirements.

## Segments and layouts

The bar is the **window list** in the center, flanked by a left and a right
**segment stack**. There are six fixed slots — three per side — and the powerline
**tier** (which background, hence the depth gradient) is baked into each slot
name, so the gradient is automatic:

```
┌──────────┬──────────┬─────────┬──────────────┬─────────┬──────────┬──────────┐
│ left-out │ left-mid │ left-in │ window list  │ right-in│ right-mid│ right-out│
│ (outer)  │ (middle) │ (inner) │  (inner-bg)  │ (inner) │ (middle) │ (outer)  │
└──────────┴──────────┴─────────┴──────────────┴─────────┴──────────┴──────────┘
   ←────────── left stack ──────────→          ←────────── right stack ──────────→
```

| Slot        | Side  | Tier   |
|-------------|-------|--------|
| `left-out`  | left  | outer  |
| `left-mid`  | left  | middle |
| `left-in`   | left  | inner  |
| `right-in`  | right | inner  |
| `right-mid` | right | middle |
| `right-out` | right | outer  |

A segment's content is a normal tmux format string. You set it directly and
re-apply — the CLI reads segments back but does not write them:

```tmux
# put the kubectl context in the right-inner slot
set -g @airline-segment-right-in '#[fg=colour39]⎈ #(kubectl config current-context)'
airline session apply

# inspect the slots (bare = all, or name one)
airline segment show
airline segment show right-in
```

### Layouts

Usually you don't set slots by hand — a **layout** does. A layout is a script
that fills slots with literal and widget formats as one composition. `layout use`
constructs those formats once and records them. Palette changes publish live colors
without rerunning the layout or replacing widget instances; `apply` captures manual
edits and renders the committed arrangement:

```tmux
airline layout use minimal
airline layout show          # the active layout + its file
airline layout describe full # inspect evaluated segments and widgets without applying
airline layout list     # what's on the layout path
```

See [layout inspection and application](docs/layouts.md) for evaluation and validation rules.

| Layout     | What it composes                                                    |
|------------|---------------------------------------------------------------------|
| `default`  | The dependency-free standard arrangement                          |
| `full`     | Init's default — session, prefix, date, and available CPU/online/battery widgets |
| `minimal`  | A pared-down bar                                                    |

Switching layouts starts from a clean slate, so a layout owns exactly the arrangement
it declares. A layout is trusted Bash with one required function. The function uses
its callback argument to declare segments and widgets:

```bash
airline_layout_configure () {
  local declare="$1"
  "$declare" segment left-out '#S'
  "$declare" widget right-mid cpu
  "$declare" segment right-mid ' | '
  "$declare" widget right-mid prefix
}
```

Airline validates the whole declaration before replacing private layout state.
Unknown slots, invalid widgets, nested Airline commands, and stdout are errors.
Repeated declarations append fragments within a slot. Omitted slots are intentionally empty. Put the file in a registered
layout directory and select it by filename. A failed selection preserves the last
committed layout and raises the global `airline-layout` problem with that session as
its origin; a successful layout selection resolves that origin's claim.

The **window-list entry** itself is fixed as `#I:#W` (index:name) and styled by
the window colors below rather than configured as a segment.

## Widgets

Widgets return tmux format fragments and choose their presentation using public
palette options. Airline establishes the segment `fg` and `bg` before each fragment;
if a widget changes either value, the fragment must restore the supplied values before
it ends. Widget runtime commands are stateless scalar producers evaluated by tmux's
normal status refresh; Airline provides no widget scheduler or runtime wrapper.

| Widget | Source |
|---|---|
| `cpu` | current CPU usage reduced to low, medium, or high |
| `battery` | First Linux system battery's capacity |
| `online` | ICMP reachability of a chosen host; requires `ping` |
| `prefix` | Native prefix, Copy, Sync, and key-table badges; no subprocess |

Use `airline widget list`, `airline widget describe cpu --medium 60`, and
`airline widget register <dir>` for discovery. Layout declarations activate widgets.
Persistent defaults use `@airline-widget-<name>-<option>` global tmux options;
placement arguments override them. Reload the layout to apply changed defaults.
The adapter catalog and CLI have been removed; replace adapter/plugin placeholders
with widget placements. See [widgets](docs/widgets.md) for migration, authoring,
platform limits, and runtime behavior.

## Daily use

Inspect the current bar configuration with `airline session show`. After changing
session color or global segment options, run `airline session apply`. Select another palette
or layout with `use`; each selection applies to the invoking session.

The window name reflects tmux focus and mode state. Zoom, copy, and activity-monitor
modes use their palette roles, in that priority order. Integrations may add a status
badge on the left (processing, result ready, or input needed) and a health badge on
the right (warning or failure). A problem badge at the far right indicates an
unavailable capability. To inspect an unfamiliar badge:

```shell
airline status show
airline health show
airline problem show
```

### Nested sessions (suspend/resume)

When running tmux inside tmux (e.g., a local session SSH'd into a remote one),
every layer looks identical and keystrokes only reach the outer session.
`airline session toggle` suspends the outer session:

- The outer prefix is disabled and keystrokes pass through to the inner session
- The outer status bar dims to a flat, muted palette so you can tell which
  layer is active

airline binds no keys itself; bind your own, using the published CLI handle so
it works wherever airline is installed. Because `suspend` switches tmux's
`key-table` to `off`, bind the toggle in **both** the `root` table (fires while
active) and the `off` table (fires while suspended), so one key round-trips:

```tmux
bind -T root F12 run "#{@airline-cli} session toggle"
bind -T off  F12 run "#{@airline-cli} session toggle"
```

Inspect the current state with `airline session show state` (`active` | `suspended`).

## Help and advanced use

Installation and the configuration above are enough for everyday use. Explore the
installed CLI as needed:

```shell
airline help
airline help layout
airline help layout describe
```

- [Reporting signals](docs/signals.md): plugin integration and workflow status,
  health observations, problem reports, and acknowledgement.
- [Process runners](docs/runners.md): run commands or watch services with reusable
  monitoring compositions.
- [Signal lifecycles](docs/lifecycle-signals.md): reference for ownership, retention,
  recovery, and multi-origin problems.
- [Runner element contracts](docs/runner-elements.md): author classifiers, filters,
  probes, and named compositions.
- [Catalogs](docs/catalogs.md) and [CLI conventions](docs/cli.md): discovery, metadata,
  targets, and exit statuses.
- [Development and transaction recovery](docs/development.md): testing, architecture,
  and diagnosing stale transactions.

See [CHANGELOG.md](CHANGELOG.md) for completed changes and [TODO.md](TODO.md) for
remaining work.

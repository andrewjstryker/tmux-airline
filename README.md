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
- **Adapters** that recolor tmux-cpu, tmux-battery, tmux-online-status, and
  tmux-prefix-highlight from the active palette
- Session-wide widget **problems**, reduced to one extreme-right warning with
  full diagnostics available through the CLI
- Suspend/resume for nested tmux sessions

## Installation

This plugin requires **tmux 3.0+** and Bash 4+ (for associative arrays), and
has no other external dependencies. It is tested on tmux 3.4 and uses tmux
features available from 3.0 onward.

> **tmux 3.0** is needed for the format comparison operators (`#{==:…}`,
> `#{?…}` over user options) that drive the per-window entry color and the
> badge/segment rendering. On older tmux the status line will not render
> correctly.

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

`airline.tmux` runs `airline init`, which publishes the CLI path, registers the
built-in search paths, and applies a default palette + layout on first run. It
binds **no keys** — you wire your own (see below).

## How it fits together

Four things, driven by one `airline` CLI:

| Concept     | What it is                                                        | You change it with            |
|-------------|-------------------------------------------------------------------|-------------------------------|
| **palette** | The colors — a set of named roles (`inner-bg`, `active`, `ok`, …) | `palette use`, or `set -g`    |
| **segment** | One powerline block's content, in a fixed slot                    | a layout, or `set -g`         |
| **layout**  | A composition that fills the slots (and picks adapters)           | `layout use`                  |
| **adapter** | A bridge that paints a third-party plugin from the palette        | `layout` (or `adapter use`)   |

Palettes and segments are **static config** — plain `@airline-*` tmux options
you set the idiomatic way; the CLI only reads them back for discovery, and
`airline apply` bakes whatever they hold into the bar. Layouts and adapters are
**dynamic** — scripts the CLI executes. Per-window **badges** (status/health)
and session-wide **problems** are live signals plugins and widgets raise at runtime.

## Nested sessions (suspend/resume)

When running tmux inside tmux (e.g., a local session SSH'd into a remote one),
every layer looks identical and keystrokes only reach the outer session.
`airline state toggle` suspends the outer session:

- The outer prefix is disabled and keystrokes pass through to the inner session
- The outer status bar dims to a flat, muted palette so you can tell which
  layer is active

airline binds no keys itself; bind your own, using the published CLI handle so
it works wherever airline is installed. Because `suspend` switches tmux's
`key-table` to `off`, bind the toggle in **both** the `root` table (fires while
active) and the `off` table (fires while suspended), so one key round-trips:

```tmux
bind -T root F12 run "#{@airline-cli} state toggle"
bind -T off  F12 run "#{@airline-cli} state toggle"
```

Under the hood `suspend` sets tmux's `prefix` to `None` and `key-table` to `off`
(so only your `off`-table bindings fire) and derives a flat look from the
palette; `resume` restores both. Inspect the axis with `airline state show`
(`active` | `suspended`).

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

`airline palette available` lists what's on the search path; `airline palette
show` prints the active palette and every role; `airline palette show name`
prints just the active name (for scripts).

Override individual roles with a normal tmux option, then re-apply:

```tmux
set -g @airline-active "colour214"
set -g @airline-stress "colour196"
airline apply
```

A palette file is just a tmux source file of `set -g @airline-<role> <color>`
lines (see `palettes/default`). To add your own, drop a file in a directory,
bless it, and `use` it — a name you register shadows a shipped one:

```tmux
airline palette register ~/.config/airline/palettes
airline palette use my-palette
```

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
airline apply

# inspect the slots (bare = all, or name one)
airline segment show
airline segment show right-in
```

### Layouts

Usually you don't set slots by hand — a **layout** does. A layout is a script
that fills the slots (and turns on the matching adapters) as one composition.
`layout use` runs it and records it, so a later `palette use`/`apply` re-applies
the same arrangement against the new colors:

```tmux
airline layout use minimal
airline layout show          # the active layout + its file
airline layout available     # what's on the layout path
```

| Layout     | What it composes                                                    |
|------------|---------------------------------------------------------------------|
| `adaptive` | Init's default — probes installed plugins, composes only what's present, degrades to session + date |
| `default`  | The standard full arrangement                                       |
| `full`     | Every slot populated                                                |
| `minimal`  | A pared-down bar                                                    |

Switching layouts starts from a clean slate (every slot is cleared first), so a
layout owns exactly the arrangement it declares. To build your own, write a
script that sets `@airline-segment-*` options (and calls `airline adapter use`),
then `register` its directory and `use` it — the same model as palettes.

The **window-list entry** itself is fixed as `#I:#W` (index:name) — a rendering
constant, styled by the window colors below rather than a segment.

## Plugin adapters

An **adapter** teaches a third-party plugin to draw in airline's palette. It's a
small snippet that sets the plugin's own color options from the active palette —
so tmux-cpu, tmux-battery, and friends match the bar and recolor whenever the
palette changes. Adapters ship for:

| Plugin                 | Adapter          | Slot it usually fills |
|------------------------|------------------|-----------------------|
| tmux-online-status     | `online`         | `left-mid`            |
| tmux-prefix-highlight  | `prefix-highlight` | `right-in`          |
| tmux-cpu               | `cpu`            | `right-mid`           |
| tmux-battery           | `battery`        | `right-out`           |

The `adaptive` layout detects which of these are installed (by directory name in
the plugin folder) and wires up only those — an uninstalled plugin leaves its
slot empty (the block collapses to just its background). airline only sets the
plugin's colors; the plugin draws its own widget.

You rarely call adapters directly — a layout invokes them — but you can:
`airline adapter use cpu`, `airline adapter show` (what's applied), `airline
adapter available` (what's on the path).

## Window list signals

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

### Entry color (airline-owned): tmux modes

The window name's color is airline's alone — no plugin API. It reflects, in
order, **tmux modes** over the **baseline** (focused / last / normal):

| State                              | Color     |
|------------------------------------|-----------|
| A pane in the window is **zoomed** | `zoom`    |
| The active pane is in **copy mode**| `copy`    |
| `monitor-activity` is **on**       | `monitor` |

The focused window is drawn reverse-video, so this single signal color renders
as the name **foreground** on inactive windows and as the highlight
**background** on the focused one — the chevrons follow it, so focus is never
lost. Precedence is **zoom > copy > monitor**; with no mode, the
normal/last/activity/bell styling applies.

### Badges (plugin-owned): the `airline` CLI

Plugins drive badges through the **`airline` command** — the supported API. It
owns the underlying tmux options and validates input, so plugins never depend on
option-name conventions.

> **Finding the CLI.** airline publishes its own path in the `@airline-cli`
> tmux option on load, so a cooperating plugin never has to guess the install
> location:
>
> ```shell
> airline="$(tmux show -gqv @airline-cli)"
> [ -n "$airline" ] && "$airline" status set agent active
> ```
>
> The empty check doubles as an "is airline installed?" probe.

**Status** (left) — a window's app-status, at one of three levels. Many
contributors can report under their own keys; airline shows the highest-ranked
one:

```tmux
airline status set build active      # ○ watching  (amber)
airline status set build result      # ● finished well (green) — outranks active
airline status set build attention   # ◆ needs you (amber)
airline status clear build
airline status show                  # keys + current values
```

Levels are `active` / `result` / `attention`; `result` outranks `active`. A
window with no status contributor shows nothing.

**Health** (right) — a single severity glyph reduced from any number of
contributors; airline shows the **worst**. `ok` (or no contributor) shows
**nothing** — a clean right side means healthy:

```tmux
airline health set ctx stress        # ▲ critical (red)
airline health set build alert       # △ degraded (amber)
# badge now shows one glyph at the max severity (stress)
airline health clear ctx             # drops to alert
airline health show                  # contributors + reduced result
```

Severities are `ok` / `alert` / `stress` (green / amber / red). Glyphs are fixed
(a distinct shape per state, so badges stay legible without color). All badge
commands accept `-t <target>` to act on a window other than the current one.

**Consume-on-view (`--transient`).** By default the setter owns clearing — a
badge stays until something clears it. For a state whose setter can't observe
that you've *seen* it (a finished job, an agent waiting for input), set it
`--transient` and airline clears it once you've viewed the window and moved on:

```tmux
airline status set agent result --transient   # clears when you leave the window
airline health set build stress --transient
```

airline registers a single `pane-focus-out` hook (idempotently) that clears that
window's transient signals — sticky ones are untouched — and enables
`focus-events`, so the feature works without extra setup.

Because color and badges live on different layers, a window can show a mode
color, a health glyph, and a status glyph all at once without contention.

## Session problems

An airline-aware widget can fail gracefully and report why through the
session-scoped `problem` API. Problems are keyed contributors with a severity
and message. Airline retains every contributor for inspection, reduces them
with the same `ok < alert < stress` ordering as health, and shows one aggregate
glyph at the extreme right. No problems (or only `ok`) renders nothing.

```shell
session="$(tmux display-message -p '#{session_id}')"

if ! command -v sensors >/dev/null 2>&1; then
  airline problem set cpu alert "required program 'sensors' was not found" -t "$session"
  printf '?'
  exit 0
fi

airline problem clear cpu -t "$session"
```

Several widgets may report independently; clearing the worst problem naturally
downgrades the aggregate to the next severity. `problem show` lists every key,
severity, and message. `problem show <key>` returns that problem as a raw,
tab-delimited `severity<TAB>message` tuple. Background widgets should pass an
explicit session target because “current session” may be ambiguous outside a
pane.

## The `airline` CLI

One entry point drives everything. Top-level verbs plus a handful of nouns, each
with its own verbs. `-t` targets a window for status/health and a session for
problem.

```
airline init                 # seed defaults + publish @airline-cli, then render (binds nothing)
airline apply                # re-apply the layout and render from the current source of truth
airline show                 # print the active configuration
airline help                 # usage (also -h / --help, and <noun> help)

airline palette  show [name|<element>] | available | use <name> | register <dir>
airline segment  show [<slot>]                 # read-only; write with set -g @airline-segment-<slot>
airline layout   show [name|path] | available | use <name> | load <path> | register <dir>
airline adapter  show | available | use <name> | load <path> | register <dir>
airline status   set <key> <level>    [--transient] [-t <win>] | clear <key> [-t <win>] | show [<key>] [-t <win>]
airline health   set <key> <severity> [--transient] [-t <win>] | clear <key> [-t <win>] | show [<key>] [-t <win>]
airline problem  set <key> <severity> <message> [-t <session>] | clear <key> [-t <session>] | show [<key>] [-t <session>]
airline state    suspend | resume | toggle | show
```

Two conventions run through it:

- **`use` vs `register`.** `use <name>` loads a bare name from a blessed
  directory; `register <dir>` blesses one (and shadows shipped names). `load
  <path>` runs a one-off file by path (adapters and layouts only).
- **`show`.** Bare `show` is a human summary; `show <field>` prints one raw
  value, newline-terminated, safe for `$(…)`. `available` lists the catalog a
  `use` can pick from. Editing a color or segment option is free; the bar
  re-renders on the next `apply` (or `use`, which ends in one).

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core):

```shell
bats test/
```

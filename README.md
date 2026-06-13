# tmux-airline

A tmux status line inspired by vim-airline. Uses powerline-style chevrons and
a layered color hierarchy with multiple theme options.

<p align="center">
  <img src="airline-screenshot.png" alt="tmux-airline screenshot" width="800">
</p>

Features:

- Three-tier status bar with powerline chevrons
- Dark, light, and Solarized themes included
- Suspend/resume for nested tmux sessions
- Optional integration with tmux-online-status, tmux-cpu, tmux-battery, and
  tmux-prefix-highlight

## Installation

This plugin requires **tmux 3.0+** and Bash 4+ (for associative arrays), and
has no other external dependencies.

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

## Nested sessions (suspend/resume)

When running tmux inside tmux (e.g., local session SSH'd into a remote
session), every layer looks identical and keystrokes only reach the outer
session. Press **F12** to suspend the outer session:

- The outer prefix is disabled and keystrokes pass through to the inner session
- The outer status bar dims to a flat, muted palette so you can tell which
  layer is active

Press **F12** again to resume the outer session and restore normal colors.

This works by toggling tmux's `key-table` between `root` (normal) and `off`
(suspended, where only F12 is bound). The `@airline-suspended` option tracks
the current state.

## Color system

The status bar is built from a `THEME` associative array with three layers of
configuration: backgrounds, content colors, and semantic highlights.

### Backgrounds

Three tiers that create the chevron depth effect:

| Key         | Role                           |
|-------------|--------------------------------|
| `outer-bg`  | Left/right edge sections       |
| `middle-bg` | Hostname / CPU sections        |
| `inner-bg`  | Window list / center           |

### Content colors

Text colors ordered by visual weight:

| Key          | Role                          |
|--------------|-------------------------------|
| `secondary`  | Default / low-priority text   |
| `primary`    | Normal text                   |
| `emphasized` | Section labels, active text   |

### Semantic highlights

Colors assigned by meaning rather than position:

| Key        | Meaning                        |
|------------|--------------------------------|
| `active`   | Current window, active pane    |
| `special`  | Clock, special modes           |
| `ok`       | Success / completion (green)   |
| `alert`    | Activity, medium battery       |
| `stress`   | Bell, low battery, high CPU    |
| `zoom`     | Zoomed pane indicator          |
| `copy`     | Copy mode indicator            |
| `monitor`  | Monitor mode indicator         |

`ok`/`alert`/`stress` form a green/orange/red status triad. `ok` is for
**discrete success** (a job or agent that *finished well*) — note the original
meter widgets (cpu/battery) never needed it, since a meter's "good" state is
just the normal/uncolored baseline; only event-based signals have a distinct
"succeeded" state to paint green.

### Overriding colors

Set any `@airline-*` option in `.tmux.conf` before the plugin loads:

```tmux
set -g @airline-active "colour2"
set -g @airline-stress "colour196"
```

### Themes

The active theme is controlled by the `@airline-theme` option, which defaults
to `dark`. The value maps to a file under `themes/`:

```tmux
set -g @airline-theme "dark"              # 256-color dark (default)
set -g @airline-theme "light"             # 256-color light
set -g @airline-theme "solarized-dark"    # requires Solarized palette
set -g @airline-theme "solarized-light"   # requires Solarized palette
```

Included themes:

| Theme              | Description                                    |
|--------------------|------------------------------------------------|
| `dark`             | Neutral dark, explicit 256-color codes (default)|
| `light`            | Neutral light, explicit 256-color codes        |
| `solarized-dark`   | Solarized dark, requires Solarized palette     |
| `solarized-light`  | Solarized light, requires Solarized palette    |

A theme file is a plain tmux source file that sets the `@airline-*` color
options. See `themes/dark` for the full list. To create a custom theme,
add a new file to `themes/` and set the option before the plugin loads:

```tmux
set -g @airline-theme "my-theme"    # loads themes/my-theme
set -g @plugin 'andrewjstryker/tmux-airline'
```

## Status bar layout

The bar is the **window list** in the centre, flanked by a left and a right
**segment stack**. A segment is a powerline block; airline draws the chevrons:

```
┌─────────┬────────┬──────────────────┬──────────┬───────┬──────────────┐
│ online  │ host   │   window list    │ prefix   │ cpu   │ date, battery │
│ (outer) │(middle)│    (inner-bg)    │ (inner)  │(middle)│   (outer)    │
└─────────┴────────┴──────────────────┴──────────┴───────┴──────────────┘
   ← left stack →                          ← right stack →
```

Segments are a registered, ordered stack managed by the **`airline` CLI** — the
same model as status badges. A segment has two required parts — a **side**
(`left`/`right`) and **content** (a tmux format) — plus an optional **priority**
(ascending = closer to the window list; default 50). Register one with:

```tmux
airline segment register <name> --side left|right --format <fmt> [--priority N]
```

The **background tier** (`outer`/`middle`/`inner`, which drives the powerline
depth) is *derived from position*, not specified: the block at the outer edge is
`outer`, the next one in is `middle`, the rest `inner`. So you place a segment
with `--priority` and the gradient falls out automatically — there is no tier to
keep in sync. airline ships these defaults (tiers shown are the derived result):

| Segment  | Side  | Priority | Tier (derived) | Default content          |
|----------|-------|----------|----------------|--------------------------|
| `online` | left  | 10       | outer          | Online status indicator  |
| `host`   | left  | 20       | middle         | Hostname                 |
| `prefix` | right | 10       | inner          | Prefix highlight         |
| `cpu`    | right | 20       | middle         | CPU usage                |
| `date`   | right | 30       | outer          | Date/time + battery      |

Add, reorder, or replace segments at runtime:

```tmux
# add a segment between cpu (priority 20) and date (30) — tier is derived
airline segment register k8s --side right --priority 25 \
  --format '#[fg=colour39]⎈ #(kubectl config current-context)'

# override a default by re-registering its name
airline segment register host --side left --format '#S'

# remove one, or inspect the stack (segment list shows the derived tier)
airline segment unregister cpu
airline segment list
```

You own ordering (`--priority`) and content (`--format`); airline owns the
chevrons and the tier backgrounds. The content is a normal tmux format, so
dynamic parts (`#{...}`, `#(...)`, `strftime`) stay live; changing the *roster*
rebuilds the bar. (Registering the defaults happens once per server, so a config
reload won't undo your customizations.)

If you really need to force a block's background, `--tier outer|middle|inner` is
an explicit override — but reach for it only when the derived depth is wrong;
normally leaving it off is what keeps the gradient consistent.

The **window-list entry** itself is templated by the `@airline-tmpl-window`
option (default `#I:#W`):

```tmux
set -g @airline-tmpl-window '#W'        # window name only, no index
```

## Window list signals

A window entry has three layers, owned by two parties. **airline** owns the
entry's *color* (foreground/background); **plugins** speak through *badges* that
flank the name. They never collide.

```
 ⚠ 1:vim        2:zsh ⟳        3:build ⚙
 │  └name        └name └status   └name └status
 └health gutter (left)           status stack (right)
   entry color (the name itself) = airline only
```

### Entry color (airline-owned): tmux modes

The window name's color is airline's alone — no plugin API. It reflects, in
order, **tmux modes** (a zoomed pane, copy mode, a monitored window) over the
**baseline** (focused / last / normal):

| State                              | Color     |
|------------------------------------|-----------|
| A pane in the window is **zoomed** | `zoom`    |
| The active pane is in **copy mode**| `copy`    |
| `monitor-activity` is **on**       | `monitor` |

Because the focused window is drawn *reverse-video* (its background is the
highlight; the flat background becomes the knockout foreground), this single
"signal color" is rendered as the **name foreground** on inactive windows and as
the **highlight background** on the focused window — the chevrons follow it, so
focus is never lost. Precedence is **zoom > copy > monitor**; with no mode, the
normal/last/activity/bell styling applies.

### Badges (plugin-owned): the `airline` CLI

Plugins drive badges through the **`airline` command** — the supported API.
It owns the underlying tmux options and validates input, so plugins never depend
on option-name conventions. Two channels flank the name:

> **Finding the CLI.** airline publishes its own path in the `@airline-cli`
> tmux option on load, so a cooperating plugin never has to guess the install
> location:
>
> ```shell
> airline="$(tmux show -gqv @airline-cli)"
> [ -n "$airline" ] && "$airline" status set agent active
> ```
>
> The empty check doubles as a "is airline installed?" probe.

**Status** — a durable, ordered stack of named lanes on the **right**. Register a
lane once (glyph + priority); light it on a window with a palette token; clear it
when done. Many lanes can show at once, left→right by ascending priority:

```tmux
airline status register agent ⟳ 20      # declare a lane: glyph ⟳, priority 20
airline status register ci ⚙ 10         # lower priority renders further left
airline status set agent active         # light 'agent' on the current window
airline status clear agent              # clear it
airline status list                     # show lanes + current values
```

You own ordering (via `priority`) and glyphs — airline renders exactly the lanes
you register, in that order, and never auto-deconflicts.

**Health** — a single severity glyph in the **left gutter**, reduced from any
number of contributors. Each contributor reports under its own key; airline shows
the **worst** severity. `ok` (or no contributor) shows **nothing** — a clean
gutter means healthy:

```tmux
airline health set ctx stress           # this window's context is critical
airline health set build alert          # …and a build is degraded
# gutter now shows one glyph at the max severity (stress)
airline health clear ctx                # drops to alert
airline health list                     # contributors + reduced result
```

Severities are `ok` / `alert` / `stress` (green / amber / red). The glyph is `●`
by default; override with `@airline-health-glyph`. All badge commands accept
`-t <target>` to act on a window other than the current one.

**Consume-on-view (`--transient`).** By default the setter owns clearing — a
badge stays until something clears it. For a state whose setter can't observe
that you've *seen* it (a job that finished, an agent waiting for input), set it
`--transient` and airline clears it once you've viewed the window and moved on:

```tmux
airline status set agent ok --transient    # clears when you leave the window
airline health set build stress --transient
```

airline registers a single `pane-focus-out` hook that clears that window's
transient signals (sticky ones are untouched) and enables `focus-events` — so
the feature works without extra setup. The hook is registered idempotently, so
reloads and repeated use never stack duplicates.

Because color and badges live on different layers, a window can show a mode
color, a health glyph, and several status badges all at once without contention.

## Plugin integrations

Default widgets are used when the corresponding plugin is installed alongside
tmux-airline (detected by directory name in the plugin folder):

| Plugin                 | Segment  | What it shows            |
|------------------------|----------|--------------------------|
| tmux-online-status     | `online` | Online/offline dot       |
| tmux-prefix-highlight  | `prefix` | Prefix/copy/zoom state   |
| tmux-cpu               | `cpu`    | CPU load with color      |
| tmux-battery           | `date`   | Battery level and source |

If a plugin is not installed, its segment renders empty (the powerline block
collapses to just its background).

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core):

```shell
bats test/
```

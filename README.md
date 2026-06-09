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

> **tmux 3.0** is needed because section templates are resolved live in the
> status line via `#{E:...}` expansion of `@airline_tmpl_*` user options (both
> added in tmux 3.0). This is what lets a template be set at any time — before
> or after airline loads, or at runtime — and take effect on the next redraw.
> On older tmux the status line will not render correctly.

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

The status bar has six sections, each backed by a function:

```
┌────────────┬──────────┬─────────────────────┬─────────────┬────────────┬──────────────┐
│ left_outer │ left_mid │    window list      │ right_inner │ right_mid  │ right_outer  │
│  (online)  │ (host)   │                     │  (prefix)   │   (cpu)    │ (date, batt) │
└────────────┴──────────┴─────────────────────┴─────────────┴────────────┴──────────────┘
```

Each section has a default widget but accepts a custom tmux format string via
`@airline_tmpl_*` options:

| Option                        | Default content         |
|-------------------------------|-------------------------|
| `@airline_tmpl_left_outer`    | Online status indicator |
| `@airline_tmpl_left_middle`   | Hostname                |
| `@airline_tmpl_window`        | `#I:#W`                 |
| `@airline_tmpl_right_inner`   | Prefix highlight        |
| `@airline_tmpl_right_middle`  | CPU usage               |
| `@airline_tmpl_right_outer`   | Date/time + battery     |

Example:

```tmux
set -g @airline_tmpl_left_middle '#S'   # session name instead of hostname
set -g @airline_tmpl_window '#W'        # window name only, no index
```

### How templates resolve

Sections **reference** their `@airline_tmpl_*` option rather than snapshotting
it at load. Internally each section emits
`#{?@airline_tmpl_X,#{E:@airline_tmpl_X},<default>}`, which tmux re-evaluates on
every status redraw. Two consequences:

- You can set a template **any time** — before or after airline loads, or at
  runtime — and it takes effect on the next redraw. Plugins that register a
  segment by setting one of these options therefore don't depend on load order.
- Because tmux's `#{?…}` treats an **empty value or the literal `0`** as unset,
  a section explicitly set to `0` shows its default rather than `0`. (Any real
  template — a format string or text — behaves as written.)

### Per-window color (`@airline-window-color`)

A window can be recolored by setting the **window-scoped** option
`@airline-window-color` to one of airline's palette tokens — `active`, `alert`,
`stress`, `special`, `monitor`, `copy`, `zoom`:

```tmux
tmux set -w -t <window> @airline-window-color alert   # flag a window
tmux set -wu -t <window> @airline-window-color         # clear it
```

airline maps the token to the theme color and renders it as **foreground** on
inactive windows and as the **background** (chevrons included) on the active
window. Unset → the window renders normally. airline neither knows nor cares
*what* sets the option — it just colors the window — so any tool can drive it
(e.g. flagging a window whose long-running job, agent, or build wants
attention). It's evaluated per window on every redraw, so changes show up live.

**Clearing.** By default the *setter* owns clearing — airline shows the color
until something unsets the option. For a state the setter can't observe being
"seen" (e.g. a finished job you'd glance at and move on from), set the companion
flag `@airline-window-color-transient`:

```tmux
tmux set -w -t <window> @airline-window-color special
tmux set -w -t <window> @airline-window-color-transient 1   # clear on unfocus
```

airline registers a single `pane-focus-out` hook that clears a transient
window's color once you've **viewed it and moved on** (so it stays lit while you
read it, then resets). Non-transient colors are never auto-cleared. This is the
one focus hook — registered once by airline so plugins don't each add competing
ones. It requires `focus-events on` (enable it yourself, or let the plugin that
sets transient colors enable it).

## Plugin integrations

Default widgets are used when the corresponding plugin is installed alongside
tmux-airline (detected by directory name in the plugin folder):

| Plugin                 | Section      | What it shows            |
|------------------------|--------------|--------------------------|
| tmux-online-status     | left outer   | Online/offline dot       |
| tmux-prefix-highlight  | right inner  | Prefix/copy/zoom state   |
| tmux-cpu               | right middle | CPU load with color      |
| tmux-battery           | right outer  | Battery level and source |

If a plugin is not installed, its section falls back to empty or the default
template.

## Testing

Tests use [bats-core](https://github.com/bats-core/bats-core):

```shell
bats test/
```

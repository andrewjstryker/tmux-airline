# tmux-airline

A tmux status line inspired by vim-airline. Uses powerline-style chevrons and
a layered color hierarchy built on the Solarized palette.

Features:

- Three-tier status bar with powerline chevrons
- Solarized dark color palette (user-replaceable)
- Suspend/resume for nested tmux sessions
- Optional integration with tmux-online-status, tmux-cpu, tmux-battery, and
  tmux-prefix-highlight

## Installation

This plugin requires Bash 4+ (for associative arrays) and has no other
external dependencies.

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

| Key         | Role                           | Solarized dark |
|-------------|--------------------------------|----------------|
| `outer-bg`  | Left/right edge sections       | `base00`       |
| `middle-bg` | Hostname / CPU sections        | `base01`       |
| `inner-bg`  | Window list / center           | `base02`       |

### Content colors

Text colors ordered by visual weight:

| Key          | Role                          | Solarized dark |
|--------------|-------------------------------|----------------|
| `secondary`  | Default / low-priority text   | `base0`        |
| `primary`    | Normal text                   | `base1`        |
| `emphasized` | Section labels, active text   | `base2`        |

### Semantic highlights

Colors assigned by meaning rather than position:

| Key        | Meaning                        | Solarized dark |
|------------|--------------------------------|----------------|
| `active`   | Current window, active pane    | yellow         |
| `special`  | Clock, special modes           | magenta        |
| `alert`    | Activity, medium battery       | orange         |
| `stress`   | Bell, low battery, high CPU    | red            |
| `zoom`     | Zoomed pane indicator          | violet         |
| `copy`     | Copy mode indicator            | blue           |
| `monitor`  | Monitor mode indicator         | cyan           |

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

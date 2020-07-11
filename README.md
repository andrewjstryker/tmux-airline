# tmux airline

**Warning:** this code is still in progress and not yet in as alpha release
stage.

Builds a status line similar in style to vim-airline.

Abstract tmux status lines into TPM plugin. What makes this compelling?

- [ ] Defines an attractive, usable status line out of the box
- [ ] Defines a color scheme contract
- [ ] Uses solarized color palette
- [ ] Toggles between dark and light variants
- [ ] Accepts user-defined palettes
- [ ] Follows powerline look and feel
- [ ] Integrates with the following widgets
  - [ ] Battery
  - [ ] Online
  - [ ] System stats

## Installation

This plugin does not have external dependencies other than Bash.

### Installation with [Tmux Plugin Manager](https://github.com/tmux-plugins/tpm) (recommended)

Add plugin to the list of TPM plugins in `.tmux.conf`:

```tmux
set -g @plugin 'andrewjstryker/tmux-airline'
```

Hit `<prefix> + I` to fetch the plugin and source it.

If format strings are added to `status-right`, they should now be visible.

### Manual Installation

Clone the repo:

```shell
git clone https://github.com/tmux-plugins/tmux-battery ~/clone/path
```

Add this line to the bottom of `.tmux.conf`:

```tmux
run-shell ~/clone/path/battery.tmux
```

From the terminal, reload TMUX environment:

```shell
tmux source-file ~/.tmux.conf
```

If format strings are added to `status-right`, they should now be visible.


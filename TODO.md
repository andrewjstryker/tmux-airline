# TODO

There is no known required architectural work for 2.0. Airline now uses native
tmux ownership consistently: global user input, private session configuration and
problems, and window-local status/health signals.

## Future ideas

### Palette cycling

The pieces already exist: the active palette is recorded, names resolve through an
ordered search path, and `palette use` replaces the session snapshot and repaints
active adapters. A future `palette cycle` command could advance through a configured
list.

The open design choice is whether that ordered list is supplied directly to the CLI
or enters through global configuration and is then copied into private session state.

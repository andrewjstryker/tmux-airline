# TODO

There is no known required architectural work for 2.0. Airline now uses native
tmux ownership consistently: global user input, private session configuration and
problems, and window-local status/health signals.

## Future ideas

### Improve file layout clarity

We should introduce some hierarchy in the file system to clearly separate code
that is part of the airline from configuration type code. Currently, the
latter is all flat at the top-level of the repository, making the organization
less obvious. Further, the testing structure should follow a similar pattern.

### Palette cycling

The pieces already exist: the active palette is recorded, names resolve through an
ordered search path, and `palette use` replaces the session snapshot and repaints
active adapters. A future `palette cycle` command could advance through a configured
list.

The open design choice is whether that ordered list is supplied directly to the CLI
or enters through global configuration and is then copied into private session state.

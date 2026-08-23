# TODO

There is no known required architectural work for 2.0. Airline now uses native
tmux ownership consistently: global user defaults, session-local mutable runtime
state and problems, and window-local status/health signals.

## Future ideas

### Palette cycling

The pieces already exist: the active palette is recorded, names resolve through an
ordered search path, and `palette use` re-applies the current layout. A future
`palette cycle` command could advance through a configured list.

The open design choice is where that ordered list should live: an explicit
session option such as `@airline-palettes "dark light"`, or the palette search-path
order.

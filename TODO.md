# TODO

There is no known required architectural work for 2.0. Airline now uses native
tmux ownership consistently: global user defaults, session-local mutable runtime
state and problems, and window-local status/health signals.

## Future ideas

### Pane orientation

Runners can create panes. Tmux supports vertical and horizontal panes. We
should follow the Tmux convention here.

### Improve file layout clarity

We should introduce some hierarchy in the file system to clearly separate code
that is part of the airline from configuration type code. Currently, the
latter is all flat at the top-level of the repository, making the organization
less obvious. Further, the testing structure should follow a similar pattern.

### Verify session scoping

Tmux provides three scopes for options:
 - Global for the server
 - Session
 - Window

Airline expect users to declare options following its convention in
`tmux.conf`. This can introduce a situation where a user modifies a global
option but airline does not care as it works with the values it copies into
its session scoped option catalog.

We need to verify that the arrangement is working as expected. Further, the
CLI API needs to make this clear.

### Completions

Since airline is a CLI, airline should generate its own completion file for
zsh and bash.

### Palette cycling

The pieces already exist: the active palette is recorded, names resolve through an
ordered search path, and `palette use` re-applies the current layout. A future
`palette cycle` command could advance through a configured list.

The open design choice is where that ordered list should live: an explicit
session option such as `@airline-palettes "dark light"`, or the palette search-path
order.

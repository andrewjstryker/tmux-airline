# Layout inspection and application

Layouts are trusted Bash files defining `airline_layout_configure`. Its callback
accepts `segment <slot> <format>`, `widget <slot> <name> [arguments...]`, and
`widget-optional <slot> <name> [arguments...]`. Repeated declarations append within
the slot; spacing between fragments is explicit. Undeclared slots are empty.

`layout use <name>` and `layout load <path>` validate the complete candidate before
replacing the selected arrangement. Unknown slots or widget names, malformed formats,
bad arguments, nested Airline commands, stdout noise, and evaluation failures reject
the candidate with status 80. Only optional availability (status 3) permits omission.
An attempted application reports failures through the session's `airline-layout`
problem claim; later success recovers it.

`layout describe <name>` reports metadata, composed segment formats, and each
fragment in declaration order, including widget source and quoted arguments. It
constructs formats and checks availability without sampling, executing embedded jobs,
committing configuration, or changing problems. Source and configure code must stay
free of external side effects; inspection isolation is not a sandbox.

`layout show [name|path]` reports the active selection; `layout list` reads metadata
only. Palette changes preserve the selected formats and widget identities. Replacing
a layout retires its former observations and claims. Segment overrides applied through
`session apply` retire widgets in the replaced slots.

See [widgets](widgets.md) for examples and [catalogs](catalogs.md) for resolution.

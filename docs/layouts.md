# Layout inspection and application

`layout describe <name>` resolves a catalog entry and reports its metadata, evaluated
segments, and adapter declarations. Segment rows follow the standard slot order and
contain the declared tmux format strings, without rendering them. Undeclared slots
are shown empty, matching how applying a layout clears omitted slots.

Adapters appear in declaration order. A `use` row names a catalog adapter; a `load`
row gives an absolute file path. An empty adapter list is shown as `(none)`.
Inspection checks that referenced adapters exist, but does not source them or prove
that they will execute successfully.

Inspection uses the same declaration evaluator as `layout use` and `layout load`.
The definition must provide `airline_layout_configure`, accept the supplied declaration
function, and remain quiet on stdout. Invalid declarations, duplicate slots or adapter
keys, missing adapters, and failed evaluation reject the description with status `80`.
Catalog resolution and metadata errors use the shared catalog error path.

Evaluation runs in a subshell for inspection. Airline does not commit segments or
adapter membership, change the selected layout, repaint adapters, render, or mutate
problem claims and retained configuration errors. Failed inspection reports its error
on stderr; only an attempted application participates in the layout problem lifecycle.

Layout files are trusted shell. Their configuration may depend on the current
environment, as the shipped `adaptive` layout depends on installed plugins. The
description reflects that environment at inspection time. Subshell isolation prevents
shell variables and functions from leaking into the caller; it does not sandbox
external side effects authored into the layout. Definitions should declare their
configuration through the supplied function.

`layout show [name|path]` continues to report the active selection. `layout list`
reads metadata without evaluating definitions. See [catalogs and discovery](catalogs.md)
for the common metadata and resolution rules.

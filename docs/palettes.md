# Palette selection and inspection

`palette use <name>` selects a palette from the session's catalog. `palette load
<file>` applies an unregistered file for one invocation, recording its absolute path
as provenance. Both validate a complete set of roles, commit the effective palette,
publish public session roles, and render. `palette show name` reports the selected
catalog name or loaded path; `palette show [<role>]` reads the effective values.

`palette describe <name>` combines the shared catalog metadata with every evaluated
role, in the same order as `palette show`. It does not select the palette, replace
effective configuration, render, or change problem claims. It
describes the file's values rather than incorporating global user overrides.

All three commands share the layout domain's palette evaluator. Palette files use
native tmux configuration syntax. Under the session's configuration transaction,
the evaluator rewrites public role names into private staging names and sources
the staged file for that session,
captures every required nonempty role, and clears staging again. Only `use` and
`load` commit the captured values and provenance. Incomplete files and source errors
fail with status `70`, clean staging, and do not commit the candidate palette.
Failed application reports the session's palette problem; failed inspection only
returns a diagnostic, because it did not attempt to change the active palette.

Palette files are trusted tmux configuration, not sandboxed data, and use the `.conf`
extension. Use session-local `set-option @airline-palette-<role> <value>` assignments
in palette files. The staging
mechanism cleans those roles; it cannot undo arbitrary commands or global settings
placed in the file. Metadata-only `palette list` does not evaluate files.

This evaluation is why sourcing a palette with `tmux source-file` is not equivalent
to `palette load`: sourcing alone does not validate completeness, capture Airline's
restoration configuration, record provenance, or redraw the bar.

See [catalogs and discovery](catalogs.md) for metadata and search paths.

## Public palette options

Every initialized session publishes all effective display roles as
`@airline-palette-<role>` options. Native formats can read
`#{@airline-palette-primary}` directly. Suspend/resume
publishes dimmed/restored colors while preserving private unsuspended values.

Global palette options seed new sessions only. To change an initialized session,
write a session option (`tmux set -t work @airline-palette-active colour201`) and run
`airline session apply` from that session. Apply captures edits that differ from the
last published display palette and clears the palette selection's provenance.
Unchanged dimmed colors never become restoration values. When editing while
suspended, apply before resuming. Raw writes are immediately readable but do not
validate, update provenance, or request a redraw themselves. Unsetting a role and
applying republishes its saved value; use `palette use` to restore a named palette.

## tmux-airline 2.0.0

A complete rework of tmux-airline's architecture and public API.

Highlights:

- New `airline` CLI for palettes, layouts, adapters, signals, and session state
- Session-scoped palettes and layouts
- Composable layouts and plugin adapters
- Per-window status and health badges
- Session-wide problem reporting
- Nested-session suspend/resume
- Installable PATH launcher via `make install`
- Shipped catalogs grouped by domain under `layouts/` and `runners/`

This release is entirely breaking. Existing 1.x configuration and integrations
must be updated; see the README for the new usage model.
Repository-relative references must likewise use the new domain paths, such as
`layouts/palettes/default`, `layouts/definitions/default`, and
`runners/probes/http`.

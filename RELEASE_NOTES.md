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

This release is entirely breaking. Existing 1.x configuration and integrations
must be updated; see the README for the new usage model.

# TODO — remaining work to 2.0

Tracked against the design in `notes.md` (settled model) and `DESIGN.md`. The
architecture is settled; remaining work is additive.

## Done — the settled-model rework

- **Prefix policy → `tmux.sh`.** ✅ Only `tmux.sh` writes the `@airline-` / `@airline--`
  literals (`pub_*` / `prv_*` / `prv_name`); everything above uses bare keys. Invariant
  **B** retargeted and green.
- **Test isolation.** ✅ `test/fake-tmux.sh` sources the real `tmux.sh` and replaces
  the leaf cores; `logic.bats` + `collections.bats` run in-process (~7× faster).
  `tmux.bats`/`cli.bats` stay on a real server on purpose.
- **Palette rename (A).** ✅ `theme` → `palette` throughout (CLI noun, `themes/` →
  `palettes/`, `THEME` → `PALETTE`). No public option renamed — no user breakage.
- **Dynamic adapters (B).** ✅ `adapters/*` are bash snippets applied by `adapter use`
  (`opt_set_global @<plugin>-* "${PALETTE[role]}"`) — literal colors, re-applied on a
  palette change. No function wrapper, no install guard. Lint scans them (Invariant A).
- **`use` / `register` + `layout` (C).** ✅ One search-path resolver over `collections.sh`;
  `use <name>` is name-only (register blesses a dir — the sole trust boundary); `use`
  records `@airline--<kind>`. `layout` is an interpreted composition (adapter/segment
  only), stored in `@airline--layout`; `apply` re-runs it, so a palette swap re-colors
  the adapters. `bundles/` → `segments/`.
- **Default-if-unset (D).** ✅ `init` runs `palette use default` / `layout use default`
  when unset, behind the first-run sentinel; ships `palettes/default`, `layouts/default`.
- **Docs (E).** ✅ `DESIGN.md` reconciled to the settled model.

## Remaining

### Solarized palettes are broken for `use`
`palettes/solarized-*` use shell vars (`$base03`) that `source-file` won't expand.
- [ ] Rewrite them as plain `set -g @airline-* colourN` files so `palette use` loads them.

### `show` — recursive, static/public only
Top-level `airline show` walks the **static/public** nouns (palette, segment, and the
public top-level) and recurses into each noun's `show`. Dynamic window-scoped
status/health are excluded from the global walk (they keep their own `show`).
- [ ] Implement top-level `show` (iterate static nouns → recurse).

### `help` — self-documenting
Help text lives inline next to each verb via a marker convention; one pass extracts
and formats it. Reference: `../makefile-helper/generate-help.awk` (`#>` / `#!` /
continuation; aligned + colorized).
- [ ] Choose extraction (awk vs sed) + marker convention; annotate `api.sh`; replace
      the static heredoc. Same iterate-and-recurse structure as `show`.

### Glyphs — redundant encoding + watchable
Don't rely on color alone (color-blind users). Add a glyph channel on the existing
two lanes (status left, health right) — not new vocabulary.
- [ ] Per-state glyph alongside color (additive).
- [ ] If tmux supports it, blink the badge for `active` (= "watchable / ongoing") —
      terminal-dependent, additive over the glyph, never the sole signal.

### Palette cycling (left open, not built)
The pieces exist (active recorded in `@airline--palette`, name resolution, `palette use`
re-applies). A future `palette cycle` reads an ordered list + the current and advances.
- [ ] Decide the list source (`@airline-palettes "dark light"` vs the palette path order).

## 2.0 — declare feature complete
After the above, the architecture is stable and remaining work is additive (default
config, shipped palettes/segments/adapters/layouts). The `use`/`register`/`layout`
model that was the one open architectural question is now built.

# TODO — remaining work to 2.0

Tracked against the design rationale in `notes.md`. Each item is scoped to the
current architecture; none requires an architectural change. When all are done,
the lint is fully green and the feature surface is complete (see "2.0" below).

## Widgets migration  (closes Invariant A)

Move `scripts/plugins/*.sh` → `widgets/*.sh` and route their tmux access through
`tmux.sh`. This is the last red on the architecture lint.

- [ ] Migrate each widget (battery, cpu, online, prefix_highlight, shared.sh).
- [ ] Wire widget color config into `render`.
- [ ] Ship widget bundles.
- [ ] `test/lint-architecture.sh A` goes green; drop the worklist exception.

## Prefix policy → tmux.sh  (the tmux.sh "earns its place" resolution)  ✅

Only `tmux.sh` knows the literal `@airline-` (public) and `@airline--` (private)
prefixes. Everything above addresses airline options by **bare key** through
prefix-aware accessors. Native tmux options keep their real names (not policy).

- [x] `tmux.sh` gained `pub_*` (public, global), `prv_name` (name builder), and
      `prv_*_global` / `prv_*_window` (private) — bare key in, prefix applied.
- [x] `render.sh` lost all literals — `AIRLINE_OPT_*` → `AIRLINE_KEY_*` bare keys;
      palette/segment reads use `pub_get`, badges use `prv_*` + `prv_name`.
- [x] `collections.sh` no longer builds `@airline--%s`; `_coll_reg`/`_coll_key`
      compose the `<ns>` shape and route through `prv_name`.
- [x] `api.sh` `_static_*` take a bare-key prefix and use `pub_*`; lifecycle uses
      `prv_*` + the renamed constants.
- [x] Config/data stay literal (`themes/*`, `bundles/*`, user `set -g @airline-*`)
      — the public prefix is the user contract.
- [x] Invariant B retargeted: the prefix lives only in `tmux.sh`. Pattern
      `@airline--?[a-z%$]` catches names + constructors, skips prose. **B green.**

## Collect the test-isolation payoff  (the tmux.sh other half)  ✅

`tmux.sh` is the single tmux chokepoint; tests above it now stub it and run
in-process instead of spinning up a real tmux server per test.

- [x] `test/fake-tmux.sh` — sources the real `tmux.sh` (composed logic stays under
      test) and replaces only the leaf cores + standalone verbs with in-memory
      bash arrays. `tmux.bats` remains the contract the fake must match.
- [x] `logic.bats` + `collections.bats` run on the fake (no server). Speedup:
      ~78s → ~11s for the two suites (~7×).
- [x] `cli.bats` (real CLI subprocess + dispatch) and `tmux.bats` (the mechanical
      layer's contract vs the real binary) deliberately stay on the real server —
      faking them would erase what they exist to prove.

Note: the fake's state is in-process, so a mutation under bats `run` (a subshell)
does not persist — three redraw-gate tests were rewritten to call directly and
capture status via `|| rc=$?`. A real server sidestepped this only because its
state is external.

## `show` — recursive, static/public only

Top-level `airline show` walks **static/public** nouns (theme, segment, public
top-level) and recurses into each noun's `show`. Dynamic window-scoped
status/health are excluded from the global walk (they keep their own `show`).

- [ ] Implement top-level `show` (iterate static nouns → recurse).
- [ ] Confirm dynamic nouns are excluded from the global walk.

## `help` — self-documenting

Help text lives inline next to each verb via a marker convention; one pass
extracts and formats it. Reference: `../makefile-helper/generate-help.awk`
(`#>` normal, `#!` special, `\t#>` continuation; aligned + colorized). Or a
simpler sed: print range → filter marker → transform.

- [ ] Choose extraction (awk pattern vs sed) and marker convention.
- [ ] Annotate verbs in `api.sh`; replace the static heredoc usage.
- [ ] Help follows the same iterate-and-recurse structure as `show`.

## `use` — search-path + register

Replace the stub (cwd, then one hardcoded subdir) with an ordered search path.

- [ ] airline maintains a search path; registers its own `themes/`, `bundles/`.
- [ ] `use` walks the path, first match wins.
- [ ] `register` prepends directories to the path.
- [ ] Decide storage: a plain ordered `@airline--path` option may fit better than
      reusing `collections.sh` (window-keyed tuples ≠ global ordered list — check
      the impedance before assuming reuse).
- [ ] Migrate solarized themes to plain `set -g @airline-*` files so `use` loads
      them (they currently use shell vars and are broken for `use`).

## Glyphs — redundant encoding + watchable

Don't rely on color alone (color-blind users). Add a glyph channel; keep meaning
to the existing two lanes (status left, health right) — not new vocabulary.

- [ ] Per-state glyph alongside color (additive, not replacing color).
- [ ] If tmux supports it, blink the badge for `active` (= "watchable / ongoing").
      Blink is terminal-dependent — additive over the glyph, never the sole signal.

## 2.0 — declare feature complete

After the above, the architecture is stable and remaining work is additive
(default config, packaged widgets, shipped themes). One open scoping call:

- [ ] `use`/`register` is the only item that adds a concept rather than a config.
      Decide: ship the full search-path/register in 2.0, or scope `use` down to a
      fixed list and defer `register` to 2.x.

# tmux-airline — Design

Status of this document:

- **Settled** — module architecture, layering, dependency direction, the
  build-time enforcement strategy, and the CLI/API surface. Don't relitigate
  without a reason.

## Principles

1. **Semantic public surface, mechanical internal surface.** The CLI speaks in
   domain terms (`status`, `health`, `segment`, `theme`, `bundle`); it funnels down through
   composition logic to a single mechanical layer that talks to tmux. Callers
   never set `@airline-*` options by hand.
2. **One path to set state.** Internal startup, user commands, and plugin calls
   all take the same route — the CLI, and `init`/`apply` beneath it. There is no second,
   divergent way to build or repaint the bar. (This is the rule the old
   `main()` / `_airline_rebuild` split violated, which is why a theme change
   only half-repainted.)
3. **The middle is logic.** Composition — the badge stack, the health reduce,
   segment-slot assembly, render expressions, theme application — is expressed
   in domain terms and never calls tmux directly.
4. **No runtime enforcement.** Bash gives us one global namespace and no
   visibility modifiers, so layers are a convention. We enforce it at **build
   time** with a lint, not at runtime.
5. **Validate at the boundary; trust the interior.** Input is checked once, at
   the CLI boundary (against `compose.sh`'s predicates). Everything below — the
   store, the composition — trusts what it is handed, so no function carries both
   "is this valid?" and "do the work." This mirrors the original's split between
   `airline_segment_register` (validates) and `_segment_define` (trusting store);
   trusted internal callers use the store directly and skip validation.

## Invariants carried from the original

The rework improves layering, but the original had qualities worth *not*
regressing. Treat these as a checklist as code migrates:

1. **Boundary validation, trusting interior** (Principle 5) — don't push input
   checks into shared interior functions.
2. **Redraw-gating** — only refresh the client when the *rendered* value actually
   changes (old `airline_status_set`). `apply` must use `opt_setif_*` ("exit 0 =
   changed") to gate the redraw, or we regress flicker/responsiveness.
3. **Idempotent, sentinel-gated defaults** — a reload must not clobber runtime
   customization (old `register_default_segments` sentinel). `init`/`apply` keep this.

## Modules & roles

| File | Role | Calls `tmux`? | Depends on |
|------|------|:---:|------------|
| `airline.tmux` | **Entry point.** Run by TPM / `run-shell`. Invokes `init` through the CLI (which composes the bar; the sentinel skips the clobber on a bare reload); holds no logic. | no (only invokes the CLI) | `airline` |
| `airline` | **CLI / API — the boundary.** Public surface for users, `airline.tmux`, and external plugins. Parses and **validates** input (the only place it is checked), then stores via `opt_*` or dispatches to `compose.sh`. Holds the command handlers and the `use` data-file readers. | no | `compose.sh`, `tmux.sh` |
| `compose.sh` | **Composition.** Loads the palette and implements `apply` — composing the bar (`status-left/right`, window formats, `*-style`, pane, clock) from the stored `@airline-*` state. Owns the shared vocabulary — slot/element names + the predicates the CLI validates against — and *trusts* its inputs. Reads/writes only through `collections.sh` / `tmux.sh`. | **no** | `collections.sh`, `tmux.sh`, `widgets/*.sh` |
| `collections.sh` | **Collections (status & health only).** A registry (explicit key list) + per-key tuples over options, split with bash `IFS` — the "0 or more" shape behind lit lanes and health contributors. Pure bash on `opt_*`; no direct tmux calls, no domain terms. Segments are *not* collections. | no (via `tmux.sh`) | `tmux.sh` |
| `tmux.sh` | **Mechanical.** The *sole* caller of the `tmux` binary: scoped option get/set/unset, redraw, `source-file`, hooks, binds. No airline-invented abstractions. | **yes (only here)** | — |
| `widgets/*.sh` | **External widget adapters.** Configure third-party tmux plugins for airline — translate `THEME` into their `@plugin-*` options (cpu, battery, online, prefix-highlight). Logic tier. | no (via `tmux.sh`) | `tmux.sh` |
| `scripts/*.sh` | **Generic helpers.** Cross-cutting shell utilities with no render role (e.g. plugin-install checks). Reserved for generic concerns — *not* widgets. | no | — |
| `themes/*` | **Built-in themes.** Delimited data (`<element> <color>`), read by `theme use` and replayed as `theme set` calls. Not sourced, not executed. | n/a (data) | — |
| `bundles/*` | **Built-in status-bar bundles.** Delimited data (`<slot> <format>`), read by `bundle use` and replayed as `segment set` calls. | n/a (data) | — |

Notes:

- **Collections are their own layer, not part of `tmux.sh`.** tmux defines
  options, hooks, binds, and redraw — *not* dynamic keyed collections, which are an
  airline abstraction. So `collections.sh` sits *above* `tmux.sh`, built on its
  `opt_*` functions. Because it makes no direct tmux calls it stays *off* the lint
  allowlist, leaving `tmux.sh` the genuinely sole tmux caller.
- **Only status and health are collections.** They hold 0-or-more dynamic entries.
  Segments are a *fixed* set of named slots — plain keyed `opt_*`, no collection,
  no registry. Themes are files. Don't grow the collection abstraction back over
  things that aren't variable-cardinality.
- **`tmux.sh` is named for where tmux calls live, not for "options only."** It
  also owns redraw, hooks, binds, and mode toggles. Don't let the short name
  tempt the suspend/hook code back into the logic layer.
- **`widgets/` vs `scripts/`.** `widgets/` holds the external on-bar widgets
  configured for airline (the cpu/battery/online/prefix adapters); `scripts/` is
  reserved for generic shell concerns. Keep the two from blurring — a new bar
  widget goes in `widgets/`, a generic utility in `scripts/`.

## Dependency graph

Every edge points *down* toward `tmux.sh`; nothing points back up. The graph is
acyclic — that linearity is the property the file split exists to guarantee.

```mermaid
graph TD
    TPM([TPM / run-shell]):::ext --> ENTRY["airline.tmux<br/><i>entry point</i>"]
    EXT([users &amp; external plugins]):::ext --> CLI["airline<br/><i>CLI / API — public surface</i>"]
    ENTRY --> CLI
    CLI --> LOGIC["compose.sh<br/><i>composition logic</i>"]
    LOGIC --> WIDGETS["widgets/*.sh<br/><i>external widget adapters</i>"]
    LOGIC --> COLL["collections.sh<br/><i>status/health registry</i>"]
    LOGIC --> MECH["tmux.sh<br/><i>mechanical — sole tmux caller</i>"]
    WIDGETS --> MECH
    COLL --> MECH
    LOGIC -. "use: reads data" .-> DATA["themes/* · bundles/*<br/><i>delimited data</i>"]
    MECH ==> TMUX([tmux server]):::ext

    classDef ext fill:#eee,stroke:#999,color:#333,font-style:italic;
```

A representative write path — the semantic→mechanical funnel for one command:

```mermaid
graph LR
    A["airline status set bell alert"] --> B["compose.sh<br/>validate · gate redraw"]
    B --> RS["collections.sh<br/>coll_set_window"]
    RS --> C["tmux.sh<br/>opt_set_window · redraw"]
    C --> D[("@airline-* options")]
```

## Data flow: stage, freeze, and what stays live

airline's `@airline-*` options are the **source of truth** (input): the status /
health registries, the segment slots, the theme colors, and config. tmux stores
them but takes no behavior from them. The tmux-native options that actually render
the bar (`status-left`, `window-status-format`, the `*-style` options, pane
borders, clock) are **derived output**. `set` mutates the source of truth;
`apply` freezes it into the derived output:

```mermaid
graph LR
    INIT(["init"]):::verb -- "seeds defaults<br/>(clobbers)" --> S
    SET(["set / use"]):::verb -- "stage (no render)" --> S
    subgraph IN["airline state — source of truth"]
        S["@airline-* options<br/>registries · slots · theme · config"]
    end
    S -- "apply — freeze<br/>(pure · idempotent)" --> T
    subgraph OUT["tmux render state — derived"]
        T["status-left/right · window-status-format<br/>*-style · pane-border · clock"]
    end
    T --> R([tmux renders the bar]):::ext

    classDef ext fill:#eee,stroke:#999,color:#333,font-style:italic;
    classDef verb fill:#dde,stroke:#669,color:#224;
```

- **`set` stages.** A config `set` writes one `@airline-*` option and stops. The
  bar still shows the previously-frozen values; staging is just "the source of
  truth moved, the render is now stale."
- **`apply` freezes.** It reads the *current* source of truth and composes the
  derived output — baking palette colors in as literal constants, and (for
  `theme`) reconfiguring the widgets' `@cpu_*`/`@batt_*` colors from the new
  palette. `apply` composes from the whole source of truth, so it is **not**
  per-noun isolated: a staged `theme set` is picked up by any later `apply`. That
  is correct — derived output is a snapshot of the source of truth at freeze time,
  not a per-noun delta.
- **`init`** seeds airline's input state (default slots, F12 binds, `@airline-cli`,
  config — clobbering to a baseline behind a sentinel), then composes. The entry
  point calls `init` on first run *and* on a bare config reload; the sentinel
  skips the clobber on reload, so re-sourcing `.tmux.conf` recomposes without
  resetting runtime state. There is no separate top-level render verb.

### What freezes and what stays live

This is the constant-vs-dynamic split. The bar holds three kinds of value, and
`apply` only ever freezes the first:

1. **Constants — colors.** Every theme color is baked at `apply` as a literal
   `colourN` (or hex): into the composed chrome (block bg/fg, chevrons,
   `*-style` options) and into the widgets' `@cpu_*`/`@batt_*` options. A color
   changes only at the next `apply`. This is the "freeze."
2. **Selectors — live, choose among frozen colors.** A `#{?…}` expression tmux
   re-evaluates every render to pick *which baked color* shows: the lane token,
   the health severity, the window mode (zoom > copy > monitor > active). The
   colors in the selector are frozen at `apply`; *which branch fires* is live.
   `status`/`health` `set` drive these by writing the option the selector reads,
   then forcing a redraw — no recompose.
3. **Widget & clock readings — live, the point of a widget.** `#{cpu_percentage}`,
   `#{cpu_fg_color}`, `%H:%M`, the online dot — tmux and the plugins re-evaluate
   these every status-interval. airline **never** recomposes for them; they live
   as `#{…}` refs inside the frozen format string.

The law: **a color is frozen; a selector is live; a reading is live.** `apply`
freezes colors and nothing else — never the things that vary between applies. This
is why `theme set`/`use` need an `apply` (they move frozen colors) but a job
lighting a status lane does not (it moves a live selector, redraw only).

What calls what:

- `airline.tmux` (entry point) → `init` (first run clobbers; reload recomposes).
- a config `set`/`clear` (`theme`, `segment`) → stages only; the caller runs
  `<noun> apply` when ready (so several `set`s can batch into one freeze).
- `theme use` / `bundle use` → stages ×N then applies once, on the caller's behalf.
- a runtime event (`status set`, `health set`) → option write + redraw, no `apply`.
- a user who hand-edited an `@airline-*` override → the relevant `<noun> apply`.

This replaces the divergent `main()` / `_airline_rebuild` pair: one compose path,
so a theme switch repaints the whole bar.

## Enforcement (build-time lint)

No runtime guards. A lint (gated in CI next to shellcheck, surfaced as
`test/architecture.bats` with didactic failure messages) checks two invariants:

- **A — only `tmux.sh` invokes the `tmux` binary.** Allowlist: `tmux.sh`.
  `collections.sh` is *not* on it — it reaches tmux only through `opt_*`, so there
  are no direct calls to flag. (`themes/` and `bundles/` are pure data — no tmux
  calls to begin with.) Excluded: the `AIRLINE_TMUX` test shim's `tmux ()` wrapper.
- **B — the private `@airline-*` schema has one source of truth.** Callers pass
  option *names* to `opt_*`, so names legitimately appear at call sites (Invariant
  A still guarantees they reach tmux only through the option layer). What B forbids
  is *duplicating the layout*: the collection key scheme (`@airline-<ns>` list +
  `@airline-<ns>-<key>` tuples) is built only in `collections.sh`, and fixed scalar
  names live as named constants referenced elsewhere. (Data files use *semantic*
  names — `active`, `right-mid` — not `@airline-*`, so they don't participate.)

These are grep-able. The plan is to land the lint first and let it run **red** —
its violation list (today: everything in the current `airline.tmux`, the existing
record store, and the ~46 `tmux set` calls in the widget adapters) becomes the
rework worklist.

## The CLI/API surface

The public, stable contract. Users, `airline.tmux`, and external plugins drive
airline through these verbs; nobody sets `@airline-*` options by hand. Argument
detail (flags like `--transient`, `-t <window>`, `--side`, `--format`) lives in
`airline --help`; this section fixes the *grammar*, not the man page. (The
`-t <window>` flag, where it appears, scopes *which window* a command targets —
a separate axis from the positional `<target>` a `set` writes to.)

### Top-level verbs (whole-system, no noun)

```
airline init                 # seed airline state from defaults, then compose the bar
airline suspend | resume     # set the suspended flag + recompose; also toggles prefix/key-table
airline help                 # usage  (also -h / --help, and <noun> help)
```

### Nouns and their verbs

```
airline status   register | unregister | set | clear | show
airline health                          set | clear | show
airline segment                         set | clear | apply | show
airline theme    set | use | apply | show
airline bundle   use
```

`apply` is a per-noun verb, not a top-level one (see *Data flow* below): a config
`set` stages, and `<noun> apply` freezes the staged state into the bar.

### Verb conventions

The verbs are not chosen per noun — they fall into three fixed roles, and which
roles a noun gets is determined by its data model:

| Verb | Role | status | health | segment | theme | bundle |
|------|------|:--:|:--:|:--:|:--:|:--:|
| `register` / `unregister` | declare an entry that carries config (glyph + priority) | ✓ | — | — | — | — |
| `set` / `clear` | write / remove a **value** at a **target** | ✓² | ✓² | ✓ | set¹ | — |
| `apply` | **freeze** the staged state into composed tmux output | — | — | ✓ | ✓ | — |
| `use <name>` | replay a delimited **data file** as `set`s, then `apply` once | — | — | — | ✓ | ✓ |
| `show` | read current state | ✓ | ✓ | ✓ | ✓ | — |

¹ `theme set <element> <color>`; no `clear` — a `use` replaces the whole palette.
² **Config `set` stages; runtime `set` signals.** A `segment`/`theme` `set` only
  writes the source-of-truth option (no render); an `apply` freezes it into the
  bar. A `status`/`health` `set` is a live runtime event — it renders immediately
  (redraw-gated), so it has no staging step and no `apply`.

- **`register`/`unregister`** when an entry carries presentation config that must
  be declared before use — a status *lane* (glyph + priority). The registry is
  airline-owned.
- **`set <target> <value>` / `clear <target>`** write or remove a *value* at a
  target — a lane's lit token, a health key's severity, a segment slot's format, a
  theme color element. `set` **always** takes a (target, value) pair; no
  exceptions. For the **config** nouns (`segment`, `theme`) a `set` only *stages*:
  it writes the source-of-truth `@airline-*` option and renders nothing — an
  `apply` freezes it. For the **runtime** nouns (`status`, `health`) a `set` is a
  live event that renders immediately. (The `-t <window>` flag is a separate axis:
  it scopes *which window*, not what is being set.)
- **`apply`** freezes a config noun's staged state into the bar: it reads the
  source-of-truth `@airline-*` options, bakes the palette colors into the tmux
  output as constants, and — for `theme` — reconfigures the on-bar widgets from
  the new palette. The baked values hold until the next `apply`. It is idempotent
  and redraw-gated (rewrites only the tmux options that actually changed). There
  is **no top-level `apply`**; it is a per-noun verb (`theme apply`, `segment
  apply`), and `init`/`suspend`/`resume` drive the same compose internally.
- **`use <name>`** replays a delimited data file as a batch of staged `set`s
  followed by a single `apply` — a theme file is `<element> <color>` lines (→
  `theme set` ×N, then `theme apply`), a bundle file is `<slot> <format>` lines (→
  `segment set` ×N, then `segment apply`). It only ever reads data and stages
  values — no sourcing, no execution — so `<name>` may be a packaged file or an
  absolute path with equal safety. See *Data files* below.
- **`show`** always — the component's current state (for `theme`, the current
  palette). One read verb across all nouns; we deliberately do not mirror tmux's
  own `show`/`list` split, for internal consistency.

The asymmetries are the data model showing through, not inconsistencies:

- **health has no `register`** — keys are dynamic contributors (one per
  job/agent) with no config; created on first `set`, gone on `clear`.
- **segment has no `register`** — its targets are a *fixed* set of named slots
  (`left-out`, `left-mid`, `left-in`, `right-in`, `right-mid`, `right-out`), so
  there is nothing to declare; you `set`/`clear` a slot's format. Not a
  collection — just keyed options at known names.
- **theme has no `clear`; bundle has only `use`** — `theme set <element> <color>`
  writes one color and a `theme use` replaces the whole palette, so there's nothing
  to `clear`. A bundle is *only* a data file you `use` (its individual writes are
  `segment set`s), so it carries no setter of its own.

### Private verbs

Internal but CLI-reachable callbacks use a leading underscore:

```
airline _unfocus <window-id>     # pane-focus-out hook callback (clears --transient signals)
```

`init` and the per-noun `apply` are public (no underscore): the entry point,
mutations, and users all call them.

### Data files (`themes/`, `bundles/`) and `use`

Themes and bundles are **delimited data files** — not scripts, not tmux
source-files:

```
themes/<name>     <element> <color>     e.g.  active    colour214
bundles/<name>    <slot> <format>       e.g.  right-mid #{cpu_fg_color}#{cpu_icon}…
```

`theme use <name>` reads the theme file, stages a `theme set <element> <color>` per
line, then runs one `theme apply`; `bundle use <name>` stages a `segment set <slot>
<format>` per line, then one `segment apply`. That is the whole mechanism.
Consequences:

- **No execution.** A data file can only ever yield validated `set` calls, so a
  `<name>` is safe whether packaged or an absolute path — `use` reads data, it
  never sources or runs code.
- **Semantic, not tmux, names.** Files name *elements* and *slots* (`active`,
  `right-mid`), never `@airline-*`; airline owns that mapping. Invariant B holds
  for free, and the files contain no tmux calls — nothing to lint.
- **`set` stages; `apply` freezes.** A `use` is N staged `set`s then one `apply`;
  if `set` rendered, a 14-line theme would repaint 14 times. Config `set`s (theme,
  segment) only write the source of truth; `apply` composes. (status/health `set`
  are the exception — runtime events that redraw immediately, not part of a batch.)
- **Widget colors aren't in the data; backgrounds aren't either.** A bundle's cpu
  slot is static text like `#{cpu_fg_color}#{cpu_icon}`, referencing `@cpu_*` (the
  thresholds `apply`'s widget config bakes from the palette) — so the format is
  theme-agnostic data. A slot may live-reference a *foreground* role,
  `#[fg=#{@airline-emphasized}]`: that's the published palette read live, and since
  the palette only moves at `apply` it is effectively a constant too. But a slot
  must **never set a background** — compose owns the block's tier `bg` and bakes
  the flanking chevrons to match it, so a data-supplied `bg=` would desync the
  chevron seam. The role→widget mapping is logic; it lives in `apply`, not in
  theme files.

The `airline`-runs-a-file-that-calls-`airline` cycle is benign: the inner calls are
staged `set`s (no re-entry), and `use` does the single `apply` at the end.

## The mechanical layer (`tmux.sh`)

The sole caller of the `tmux` binary. Conventions:

- **No flags, ever.** Fixed positional args; scope and behavior are encoded in the
  *name* (`opt_set_window`, not `opt_set -w`). This is what makes the lint a grep.
- **Returns:** getters echo to stdout (empty when unset); predicates use exit
  status; mutators are silent.
- **Composition:** a few private cores (`_opt_*`) do the actual call; every public
  function is a thin wrapper that bakes in scope/behavior.
- **Modern Bash (4.3+):** `[[ ]]`, `printf %s` over `echo`, arrays, namerefs where
  they save a subshell.
- A function exists **only for a tmux subcommand that isn't an option.** Built-in
  options (`prefix`, `key-table`, `focus-events`, `status-left`, …) go through
  `opt_set_global` / `opt_unset_global`, not bespoke functions.

### Scalar options (`opt_*`)

Private cores — the last positional is the option name, everything before it is
scope:

```bash
_opt_show  () { tmux show-options -qv "$@"; }   # _opt_show  <scope…> <name>
_opt_write () { tmux set-option   -q  "$@"; }   # _opt_write <scope…> <name> <value>
_opt_clear () { tmux set-option   -qu "$@"; }   # _opt_clear <scope…> <name>
```

Public matrix — five verbs × two scopes (`global`, `window`):

| Verb | global | window | Purpose |
|------|--------|--------|---------|
| get   | `opt_get_global <name>` | `opt_get_window <win> <name>` | echo value, empty if unset |
| getor | `opt_getor_global <name> <def>` | `opt_getor_window <win> <name> <def>` | echo value, or default if unset |
| set   | `opt_set_global <name> <val>` | `opt_set_window <win> <name> <val>` | write (always) |
| setif | `opt_setif_global <name> <val>` | `opt_setif_window <win> <name> <val>` | set-if-needed — write only when changed; **exit 0 = changed** |
| unset | `opt_unset_global <name>` | `opt_unset_window <win> <name>` | remove |

Window functions always take an explicit window id; "current" is resolved by the
caller via `current_window`.

### Standalone verbs (distinct subcommands)

| Function | tmux call | Purpose |
|----------|-----------|---------|
| `redraw` | `refresh-client -S` | force a bar re-eval (no client → harmless) |
| `source_file <path>` | `source-file` | source a tmux config file (themes are data now, not sourced — candidate for removal if unused) |
| `current_window` | `display-message -p '#{window_id}'` | resolve "current" for window-scoped callers |
| `hook_set <spec> <cmd>` / `hook_unset <spec>` | `set-hook -g` / `-gu` | the focus-out consume-on-view hook |
| `key_bind <table> <key> <cmd>` / `key_unbind <table> <key>` | `bind-key` / `unbind-key` | the F12 suspend/resume binds |

## Collections (`collections.sh`) — status and health only

status and health each hold *0 or more* dynamic entries — lanes lit on a window,
health contributors reporting in — which tmux's flat option store has no concept
of. `collections.sh` adds exactly that, and **only** for these two; segments are
not a collection (they're fixed slots — see the CLI section). No tmux calls (built
on `opt_*`), no domain knowledge: `status` / `health` arrive as the `ns` argument.

Two storage shapes, each a single-delimiter string split with bash `IFS`/`read` —
no awk, no jq, no subprocess on the hot path:

```
@airline-<ns>          registry: a space-delimited list of keys (membership)
@airline-<ns>-<key>    that entry's fixed-arity tuple, tab-delimited
```

Rules:

- **Names are data, never inferred.** Membership is the registry list; we never
  discover entries by globbing/parsing `@airline-*` option names. Keys are only
  ever *constructed* from `(ns, key)`, so a key may contain `-`.
- **One delimiter per option.** Registry = space-delimited names; tuple =
  tab-delimited fields (the lone arbitrary field, a status glyph, is never a tab).
  Fixed arity: `set` writes the whole tuple, so field positions stay stable.
- **Storage ≠ render.** A collection holds airline's bookkeeping; `apply` reads it
  and projects the options tmux renders (the per-lane render references, the
  reduced health scalar). The store is never itself the live render reference —
  that coupling in the old model is why changing storage *looked* like it broke
  rendering.

`coll_*` mirror `opt_*`'s scope suffix (`_global` / `_window <win>`). Ops:
`register` / `unregister` (key-list membership), `members` (the list),
`get` / `set` (the per-key tuple), and `reduce` (health's max severity). Pure
bash, zero-dependency.

This refines the existing `record.sh`: keep the registry list, pack each entry's
attributes into one tab-delimited tuple instead of an option-per-attribute, and
drop segments out of it entirely.

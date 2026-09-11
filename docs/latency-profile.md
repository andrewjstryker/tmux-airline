# Latency profile and storage-design assessment

Status: an analysis of the current implementation with prospective recommendations.
Nothing here is an accepted change. [TODO.md](../TODO.md) records which items are
candidates for work; [CHANGELOG.md](../CHANGELOG.md) records what has been done.

[Performance measurements](performance.md) report what each operation costs. This
document reports where that cost goes, and assesses a specific design question: has
avoiding an external dependency such as `jq` cost us complexity and latency?

Reproduce every figure below with:

```sh
python3 scripts/profile-latency > /tmp/airline-latency.json
```

It writes a summary to stderr and full JSON to stdout, runs against a disposable
tmux server on its own socket under a temporary home, and never contacts the user's
tmux server. `--groups` selects a subset of `primitives`, `attribution`, `hotspots`,
and `scaling`. `strace` and `jq` are optional; the corresponding measurements are
skipped when absent. Neither is a runtime dependency.

## Summary

The concern is well founded in one of its three parts, but the remedy it suggests
does not follow: adopting `jq` would help the current code and then stand in the way
of the change that helps far more.

| Concern | Real? | Measured cost | Best remedy |
|---|---|---|---|
| Information encoded in keys, forcing reduction across keys | Yes | ~13 ms per stored member, per operation | Nameref reads, then a secondary index |
| List and tuple encoding handled internally | Yes | ~15 lines; no measurable latency | None; leave it |
| Numbers indistinguishable from text | Yes | ~5 lines of validation | None; irreducible |

The dominant avoidable cost is not any of the three. It is the use of command
substitution — `value="$(accessor …)"` — to return a value *inside a single
process*. Each one forks. During a transaction the data being fetched is already
resident in a Bash associative array in that same process.

## Where the time goes

One repeated `session init`, split by component. Subprocess counts come from a
traced run; the prices come from untraced primitive measurements, so no `ptrace`
overhead enters the attribution. The residual is a remainder, not a measurement.

| Component | Count | Cost |
|---|---|---|
| CLI startup, library sourcing, dispatch | 1 | 25.5 ms |
| `tmux` subprocess round trips | 33 | 154.0 ms |
| Bash `$(…)` forks (clone with no exec) | 103 | 89.7 ms |
| Bash interpretation (~14,400 traced commands, residual) | — | 163.0 ms |
| **Total** | | **432.2 ms** |

The ways to move one value, measured in isolation:

| Primitive | Cost |
|---|---|
| Bash nameref return | ~0.010 ms |
| Bash `$(function-call)` | 0.871 ms |
| `tmux` client round trip | 4.667 ms |
| `jq` invocation | 5.985 ms |

A `jq` call costs more than a tmux round trip, and roughly two orders of magnitude
more than a nameref return. The nameref figure sits near the harness's resolution
limit and varies between 0.004 and 0.015 ms across runs; treat it as "negligible"
rather than as a precise value.

## Concern 1 — encoding information in keys

Confirmed, and it scales. One `problem set` / `problem set … ok` pair against a
growing ledger:

| Other claims stored | Pair latency |
|---|---|
| 0 | 272.4 ms |
| 20 | 524.6 ms |
| 60 | 1076.4 ms |

About 13.4 ms of marginal latency per stored claim, per operation.

The cause is as described: a claim id is `kind:origin:contributor:key` while a
ledger id is `contributor:key`, so answering "which claims match this (contributor,
key)?" means scanning every member. Five call sites do this —
`_signal_problem_recompute`, `_signal_problem_close_unlocked`,
`_signal_problem_resolve_unlocked`, `_signal_problem_clear_unlocked`, and
`_signal_problem_show_unlocked` in `lib/signal.sh`.

What the measurement adds is *why* each scanned member is expensive. Inside a
transaction, `_opt_snapshot` has already loaded every one of those tuples into
`_AIRLINE_OPT_VALUE` (`lib/tmux.sh`), and `_opt_read` serves them from that array
with no tmux call. The scan is not paying for I/O. It pays ~0.87 ms per read for
the fork in `tuple="$(coll_get …)"`, to fetch a string already in memory in the
same process — and the marginal cost is 13.4 ms rather than 0.87 ms because a
set/clear pair touches each member about fifteen times across its scans.

So the layout costs one traversal per operation, which is cheap; the *idiom used to
traverse it* costs roughly two orders of magnitude more than it needs to.

There is corroborating evidence that this idiom already costs correctness, not only
speed: `_opt_setif` in `lib/tmux.sh` carries a comment explaining that it must
pre-warm the snapshot because "Bash would discard the lazy snapshot with that
subshell." The fork boundary was worked around rather than removed.

### Where `jq` actually lands

Honest accounting, because the answer flips depending on what it is compared against:

- **Against the code as written**, `jq` wins. A document query is flat per operation
  — call it 12-25 ms for the read-modify-write invocations a set/clear pair needs —
  against 13.4 ms *per member*. It breaks even at roughly two claims.
- **Against the code with nameref reads**, `jq` loses badly. Fifteen touches at
  ~0.01 ms is ~0.15 ms per member, so the flat cost does not pay for itself until
  well over a hundred members.

Airline's collections hold single digits. The second comparison is the one that
matters, because the nameref change is strictly cheaper to make than adopting a
document store: it is internal, changes no storage format, and extends a convention
the write path already uses. `jq` would also become the project's first runtime
dependency beyond tmux (README: "has no other external dependencies") while
foreclosing the faster option.

## Concern 2 — internal list and tuple encoding

Real, and the cheapest of the three. `lib/collections.sh` is 123 lines; the encode
and decode is about 15 of them — the `IFS=$'\t'` join in `_coll_set`, the
`${tuple%%$'\t'*}` first-field extraction, and the `IFS=$'\t' read -r` at each call
site. The invariants are enforced at the boundary rather than assumed:
`_signal_validate_key` rejects whitespace and `:`, and `_signal_validate_condition`
rejects tabs.

`jq` would not delete this code; it would relocate it. Constructing JSON from shell
strings and splitting results back into shell variables is the same work with worse
quoting hazards than "no tabs", plus a process. The genuine cost here is the
reserved characters charged to users — `:` in keys and contributors, tabs in
messages — not complexity or latency.

## Concern 3 — numbers indistinguishable from text

Real and irreducible. `[[ "$revision" =~ ^[0-9]+$ ]]` appears four times in
`lib/signal.sh` plus once validating the hook argument: about five lines, costing
microseconds.

A text boundary exists at both ends — tmux options are text, and Bash variables are
text. JSON numbers would survive inside the document and be stringified the moment
one is read into a shell variable, so the validation would remain with an extra
process in the path. Keep the regex checks.

## Two findings outside the original three

Both are larger than concerns 2 and 3 combined.

**Snapshot parsing dominates Bash work.** `_opt_snapshot_line` and `_opt_decode`
together account for 51.5% of every Bash command executed during an init. Five
snapshots run per init, parsing 386 option lines in total — 57 global session and
55 global window options on a bare server — nearly all of which Airline never reads.
That is three `show-options -q -gw` and three `-q -g` calls plus the parsing.

**Seven unbatched tmux calls for catalog paths.** `catalog_paths` resolves
`@airline--path-adapter`, `-classifier`, `-filter`, `-layout`, `-palette`, `-probe`,
and `-runner` as seven separate `show-options -qv` round trips outside any
workspace — about 33 ms for data one already-loaded session snapshot would serve.
They are 7 of the 15 `show-options` calls in a repeat init.

## Recommendations

Ranked by measured payoff. None requires a new dependency, and none changes the
public grammar, option names, or storage format.

1. **Add nameref-destination read variants** (`coll_get_into`, `coll_members_into`,
   `opt_get_into`) and convert the loop-resident call sites in `lib/signal.sh`,
   `lib/render.sh`, and `lib/layout.sh`. There are 62 command-substitution read
   sites in `lib/`; the hot ones are all inside loops, and 13.7% of all traced
   commands already execute inside a subshell. This removes most of the ~90 ms of
   fork cost and takes the per-member scan constant from ~13 ms to a fraction of a
   millisecond, so the 60-claim case falls back toward its 0-claim baseline. It
   also dissolves the `_opt_setif` subshell workaround. The write path already uses
   this idiom throughout — every `_signal_*_unlocked` and `_project` takes a
   `<destination>` — so this extends an established convention rather than adding
   one.

2. **Preload the session scope once** before the catalog path reads so all seven
   resolve from the workspace (~33 ms).

3. **Narrow or reuse the snapshot.** Snapshot parsing is over half of every Bash
   command executed during an init. Either filter to `@airline-`-prefixed lines
   during the parse, or let one workspace survive across the transactions within a
   single CLI invocation.

4. **If the ledger scan still measures after (1)**, fix it structurally rather than
   with a query language: add a secondary registry keyed by `contributor:key`
   holding the matching claim ids, so recompute reads one membership list instead
   of filtering all of them. That is the real answer to "keys should not carry
   meaning" — a second index, not a document store.

5. **Leave concerns 2 and 3 alone.** Together they are about 20 lines and no
   measurable time, and both would get worse with an external JSON tool.

## Implication for the native-core proposal

This profile is evidence that initialization latency is not primarily "Bash is
slow." Roughly a third is tmux subprocess and IPC cost that a C++ port retains, and
a large share of the Bash cost is two specific removable patterns rather than
diffuse interpreter overhead. Re-measure after items 1-3 before reassessing the
[C++ core and Lua catalog proposal](native-core-proposal.md); the numbers it would
be judged against are likely to move substantially.

## Limits

Single machine, five samples per figure, detached sessions, no attached-client
redraw. Component timings are taken untraced; only the subprocess *counts* come
from a traced run, and the interpretation figure is a residual rather than a
measurement. Run-to-run variation across the totals here is roughly 10%, so treat
the component split as an attribution rather than a precise budget. These are
observations for guiding work, not thresholds. Absolute values vary with hardware,
tmux version, and Bash version; the ratios between primitives are the durable
result.

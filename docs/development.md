# Development

For the architecture, internal boundaries, design rationale, and testing strategy,
see [DESIGN.md](../DESIGN.md). Focused design documents begin with
[Signal lifecycles](lifecycle-signals.md). Completed project work is summarized
in [CHANGELOG.md](../CHANGELOG.md); prospective consolidation work lives in
[TODO.md](../TODO.md).

The full suite exercises real isolated tmux servers. Tests require Bats, tmux,
Bash, GNU timeout, flock, and `script` (for the attached-client rendering check):

```shell
make test
```

For focused development, `make test-fast` runs only static and in-memory behavior
tests. `make test-layout`, `make test-session`, `make test-signal`,
`make test-transaction`, `make test-widget`, and `make test-runner` pair tests
with the corresponding `lib/` module; `make test-integration` runs every real-tmux
suite. Behavior belongs in fast tests; run the real-tmux integration suite before
merging to main. Run `make lint` for ShellCheck and the architecture guards.

## Performance and deferred architecture

See [performance measurements](performance.md) for the isolated CLI benchmark
harness and comparison limits, and the [latency profile](latency-profile.md) for
where that time goes, an assessment of the collection storage design, and the
prospective work it suggests. The [C++ core and Lua catalog proposal](native-core-proposal.md)
is deferred pending measured latency and maintenance experience after stabilization.

## Transaction recovery

Airline serializes collection updates with owner-scoped tmux locks. A process killed
with `SIGKILL` cannot run cleanup, so its transaction marker can remain behind. The
diagnostics make that rare state discoverable and recoverable:

```shell
airline transaction show
# scope<TAB>owner<TAB>namespace<TAB>active|stale<TAB>pid<TAB>age-seconds

airline transaction clear global server problem
airline transaction clear window '@3' status
```

`transaction clear` only releases a stale marker; it refuses to clear one whose
recorded owner process is still alive. Recovery is separate from the problem API so
diagnosing a stuck problem transaction never depends on acquiring that same lock.

The operands are positional, in this order: **scope, target, namespace**.
Use `global server problem` for the global problem transaction, `session <target>
config` for session configuration, or `window <target> status|health` for a window
signal transaction. See `airline help transaction clear` for syntax.

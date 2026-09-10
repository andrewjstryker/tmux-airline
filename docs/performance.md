# Performance measurements

Run the development-only harness with Python 3, Bash, and tmux installed:

```sh
python3 scripts/measure-performance > /tmp/airline-performance.json
python3 scripts/measure-performance --samples 10 --warmups 2 > /tmp/airline-performance-later.json
```

It writes progress and a millisecond summary to stderr, and JSON containing all
samples, medians, ranges, source revision, working-tree status, and runtime versions
to stdout. Keep the JSON files outside the checkout or in your own results archive.
Python is a measurement dependency only; Airline's runtime dependencies are unchanged.

Each iteration creates a disposable tmux server on a unique socket under `/tmp`,
with no tmux configuration, a temporary home/config directory, and one detached
session/pane. It removes inherited Airline/tmux overrides and Bash startup injection
variables. The pane runs an explicit sleep command. Cleanup kills only that server.
The harness does not connect to the user's tmux server.

| Measurement | Timed work |
|---|---|
| `cli_version` | Direct CLI launch, library loading, dispatch, and version output |
| `fresh_init` | First `session init` on an already running, uninitialized server |
| `repeat_init` | A second `session init` on the same session |
| `unchanged_apply` | `session apply` without pending user edits |
| `health_set_clear` | Two CLI calls: publish one warning, then recover that claim |
| `runner_basic` | Synchronous runner executing `true` |
| `runner_tap` | Named TAP runner executing Bash to emit one passing assertion |

The cases run in that order on each fresh server. Setup and teardown are excluded
from measurements; CLI process creation and output capture are included. Runner
cases include their lifecycle work and child process overhead. A command failure
or timeout aborts the run instead of entering a successful timing sample. The
default timeout is 60 seconds per command; use `--timeout` to change it.

The default is one discarded warmup iteration and five recorded iterations.
Fresh initialization means fresh Airline/tmux state, not cold filesystem or CPU
caches. This is a detached-session baseline, not an end-to-end measurement of TPM,
terminal startup, attached-client redraw, or a user's complete tmux configuration.
The installable PATH shim is also outside the timed path.

Initialization uses the shipped default palette and adaptive layout. Adaptive
layout detection can find sibling plugins beside this checkout, even with a
temporary home. Keep those installations and the checkout location constant when
comparing runs, or use equivalent clean checkouts without sibling plugins. Keep
machine load, power settings, and runtime versions comparable as well.

Use repeated runs to distinguish a change from noise. These measurements are
observations, not CI pass/fail thresholds. Five samples do not establish reliable
tail latency. They do not attribute elapsed time to Bash versus tmux: profiling
would be a separate next step if the measurements justify it.

The [deferred native-core proposal](native-core-proposal.md) records how these
measurements inform a possible C++/Lua migration.

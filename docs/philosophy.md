# Project philosophy

Airline targets Unix-like operating systems with Bash and tmux. The Unix process
model, ordinary file descriptors and pipes, signals, exit statuses, and standard
command-line utilities are load-bearing parts of the platform. Bash and tmux are
the tools Airline composes on top of those facilities, not implementation details
to work around. Airline reports the limits that remain visible to it.

## Use the platform

The Unix-like environment provides processes, file descriptors, pipes, signals,
and standard utilities. Bash provides shell composition, traps, and access to that
process model. Tmux provides scoped key-value options (server, session, window,
and pane), format expressions, commands, and the status refresh cadence.
Airline uses those primitives directly. A design
should first ask how the platform already expresses the behavior before introducing
an Airline mechanism.

Tmux owns status refresh. A widget supplies a native format fragment and, when
needed, a quick scalar command evaluated by tmux. Airline does not add a second
scheduler to compensate for tmux's refresh model.

Runners use the operating system's ordinary process and stream behavior. Pipes,
FIFOs, `tee`, and operating-system buffering define the back-pressure contract.
Airline does not add file spilling or a custom buffer to make a filter appear more
capable.

## Keep ownership explicit

Each layer owns the behavior its platform provides:

- tmux owns scoped key-value options, schedules refreshes, and evaluates status formats;
- widgets construct formats and report scalar values;
- the Unix-like operating system and Bash provide process, signal, and stream mechanics;
- runners interpret commands and observations;
- Airline composes these parts, validates their contracts, and reports failures it
  can observe.

Airline should not conceal an ownership boundary with a duplicate subsystem. A
third-party widget or runner may use private optimizations, locks, caches, or
schedulers, but those mechanisms are outside Airline's catalog contracts.

## Detect and report

When Airline can detect that something is wrong, it should report it through the
appropriate problem or command result. Validation, liveness checks, cleanup, and
problem recovery are useful because they describe observable behavior. Speculative
recovery machinery that compensates for an unowned limitation is not.

The goal is honest behavior: preserve the platform's semantics, clean up what
Airline owns, and make failures visible without inventing guarantees that Bash or
tmux cannot provide.

## A design test

Before adding infrastructure, ask:

1. Can the Unix-like platform, Bash, or tmux provide this directly?
2. Which layer owns the behavior and its failure mode?
3. Is the capability essential to Airline's purpose, or is it compensating for a
   limitation that should remain visible?
4. Can the contract stay stateless, native, and understandable?

If the platform already provides the behavior, use it. If Airline cannot observe or
repair a failure within those primitives, document that boundary instead of adding
an unrelated subsystem.

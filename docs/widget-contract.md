# Widget contract

A widget follows the [project philosophy](philosophy.md): it uses tmux's native
format and refresh model rather than supplying a parallel runtime service.

A catalog widget is a trusted, stateless Bash format provider. Its format definition
is `<name>.sh`; an optional extensionless `<name>` executable supplies a scalar to a
tmux `#()` expression. Tmux owns status refreshes. Airline provides no widget state,
scheduling, caching, locking, timeouts, retries, or runtime supervision.

## Catalog shape

```text
widgets/battery.sh       # format definition
widgets/battery          # optional runtime executable
```

Shell catalog definitions use `.sh`; tmux configuration files use `.conf`. The
logical name used by discovery and layout declarations omits the extension. The
extensionless executable is a runtime companion selected by the format definition,
not a second catalog definition.

## Airline inputs

Airline provides the session palette as public options:

```text
@airline-palette-outer-bg       @airline-palette-middle-bg
@airline-palette-inner-bg       @airline-palette-primary
@airline-palette-secondary      @airline-palette-emphasized
@airline-palette-active         @airline-palette-special
@airline-palette-ok             @airline-palette-alert
@airline-palette-stress         @airline-palette-zoom
@airline-palette-copy           @airline-palette-monitor
```

Global palette values seed sessions. An initialized session publishes its effective
palette, which widgets read through live tmux format references. Palette changes
render the layout again, so each placement receives the current segment colors.

Widget policy belongs to `@airline-widget-<name>-<option>`. Each widget reads its
own public options directly with `tmux show-option -gqv` while composing the
expression, applies defaults, and validates values. Airline passes only foreground
and background arguments. It does not interpret option metadata, fetch widget
configuration, or construct configuration argument lists. Public options are user
inputs; the generated `@airline--widget-<name>` expression remains private output.

## Format definition

Airline calls the definition during layout evaluation:

```bash
airline_widget_format() { # <segment-fg> <segment-bg>
  local fg="$1" bg="$2"
  shift 2
  printf '%s' '#{?client_prefix,PREFIX,}'
}
```

The first two arguments are the `fg` and `bg` already established by the containing
segment. The fragment assumes that styling is in place and returns one valid tmux
status-format expression. It may change foreground or background to present a value,
but it must restore both supplied values before its expression ends. Airline does not
repair a leaking widget; a widget that violates this contract is broken.

The expression may contain native tmux conditionals, substitutions, palette references,
and `#()` calls. A runtime call emits data only; its output is not recursively treated
as a second tmux format. Keep style directives and palette references in the format
definition itself.

The definition must be quiet while sourced and while constructing the format. It must
not sample hardware, execute the runtime companion, mutate tmux, create files, or
depend on previous invocations. Airline validates the returned fragment for framing,
control characters, and layout-level directives, but does not interpret its
presentation or police trusted widget code.

## Runtime executable

The optional extensionless companion is invoked directly by tmux through `#()`. It
receives the observation arguments selected by the format definition and emits one
scalar value, text or numeric, on one line. It must be stateless and quick enough for
the user's `status-interval`. It never writes Airline state. It may read Airline
state only through the public `airline` CLI, the same interface any other caller
uses: the shipped `problem` widget reports `airline problem show --level`. A widget reads a
reduced scalar the CLI already maintains rather than parsing a command's presentation
output. It does not read private `@airline--` options or call tmux directly.

Third-party widgets may choose private optimizations, files, locks, or scheduling;
those are outside Airline's contract. Airline supplies no equivalent mechanism for
catalog widgets. A stateful or scheduled implementation is not a conforming Airline
widget.

## Availability and inspection

A widget may expose `airline_widget_available` for a cheap layout-time
capability check. It must not run the runtime executable. The check assesses whether
the widget can fill its advertised contract. Unavailability (status 3) reports a
`warn` problem and publishes an empty expression so
the rest of the layout remains valid.

An advertised widget dependency that fails during format construction follows the
same problem contract: report a `fail` claim through the problem service, publish an
empty expression, and leave the layout valid. This reports that the widget cannot
fill its contract without turning display data into a health or overload claim.

`widget describe` evaluates the format definition and reports its literal expression.
It does not execute `#()` calls, invoke the runtime companion, or change active
configuration. There is no `airline widget eval` or `airline widget run` runtime path.

## Composition

A layout declares complete segment strings containing native
`#{E:@airline--widget-<name>}` references. Airline publishes each requested widget's
expression once in a private session option; tmux owns expansion. The host passes
`default` foreground/background values to format construction and wraps the result
in native `push-default`, `default`, and `pop-default` style directives. Those
capture and restore the surrounding style independently at each placement. Widget
formats must not manipulate the default-style stack themselves.

Render establishes the segment baseline once and adds padding, chevrons, and
separators at the segment boundary. Empty widget expressions contribute no content;
literal spacing and the containing segment's chrome remain. Repeated placements
share the same expression and widget-owned configuration, with separate lifecycle
claims for each placement. Parameters come only from tmux options; neither layout
strings nor `widget describe` accept overrides.

The complete path is:

```text
layout use/load
  → source <name>.sh
  → call airline_widget_format default default
  → widget reads and validates its own public tmux options
  → publish @airline--widget-<name> and the unchanged segment reference
tmux status refresh
  → expand #{E:@airline--widget-<name>}
  → evaluate any #() jobs inside that expression
  → read the runtime scalar
  → apply tmux conditionals and the session palette
```

See [widgets](widgets.md) for shipped examples and [catalogs](catalogs.md) for
discovery and file naming.

# Layout inspection and application

Layouts are trusted Bash files defining `airline_layout_configure`. Its callback
accepts `segment <slot> <format>`. Each string defines the entire segment: literal
text and native tmux expressions. Later declarations replace earlier definitions
of the same slot. Only final definitions are prepared; undeclared slots are empty.

```bash
airline_layout_configure() {
  local declare="$1"
  "$declare" segment left-out '#h'
  "$declare" segment left-mid '#S #{E:@airline--widget-online}'
  "$declare" segment right-in '#{E:@airline--widget-prefix}'
  "$declare" segment right-out '%H:%M #{E:@airline--widget-battery}#{E:@airline--widget-power} #{E:@airline--widget-problem}'
}
```

`#{E:@airline--widget-<name>}` is native tmux syntax. Airline discovers these
references in final segment definitions, builds each named widget once, and
publishes its format in a private **session** option. The segment retains the
reference; tmux's `E:` modifier expands the option in the current display context.
Native conditionals can surround references. A doubled hash (`##{E:...}`) remains
escaped and does not request a widget. Other tmux formats pass through unchanged.
Use the direct `E:` form shown above to declare a widget dependency; indirect
references through other user options are not discovered.

Widget parameters come exclusively from global `@airline-widget-<name>-<option>`
options and built-in defaults read and validated by the widget itself.
Repeated placements share one generated expression
and configuration. There is no inline argument or placeholder language.

Airline publishes expressions wrapped in native `push-default` / `pop-default`
style directives. Widgets receive `default` for their foreground and background,
so they restore the style at their placement even across differently colored
segments. The segment owns literal spacing; composition adds outer padding and
separators. The private generated options are implementation output, not user
configuration. They are removed when the final placement is retired.

`layout use <name>` and `layout load <path>` prepare the complete candidate before
replacing the selected arrangement. Unknown slots, nested Airline commands, layout
stdout noise, and layout evaluation failures reject the candidate with status 80.
Application failures report through the session's `airline-layout` problem claim;
later success recovers it. Tmux owns native format interpretation.

An unavailable requested widget publishes an empty expression and reports a warning
through `airline-widget`. Missing widgets, invalid options, and broken widget
formats publish an empty expression and report a failure. Neighboring segment text
continues to render. Reloading rechecks widgets and resolves a placement's claim
when it recovers. Removing a placement closes its claim. There is no background
retry service. A nonempty segment definition retains its spacing and chrome even
when a referenced widget is empty.

`layout describe <name>` reports metadata, segment strings, and widget expressions,
sources and diagnostics without publishing options or claims.
Slots follow first declaration order; references follow their order in the final
string. Inspection does not sample widgets or execute their runtime jobs. Source
and configure code must remain free of external side effects; inspection is not a
sandbox.

`layout show [name|path]` reports the active selection; `layout list` reads metadata
only. Palette changes preserve generated expressions and widget identities.
Segment overrides applied through `session apply` retire placements in those slots;
a shared widget option remains while another slot still uses it.

See [widgets](widgets.md) for configuration and [catalogs](catalogs.md) for discovery.

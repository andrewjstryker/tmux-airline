get_tmux_option() {
	local option=$1
	local default_value=$2
	local option_value=$(tmux show-option -gqv "$option")
	if [ -z "$option_value" ]; then
		echo "$default_value"
	else
		echo "$option_value"
	fi
}

# Emit a live reference to a template option for the status line. The option is
# resolved on every redraw (#{E:...} expands its value as a format); the default
# is used only while the option is unset/empty. Because the value is referenced
# by name rather than snapshotted, the option may be set before OR after airline
# loads — there is no load-order dependency. Commas in the default are escaped
# so they don't split the surrounding #{?,,} conditional.
#
# Note: #{?...} treats an empty value or the literal "0" as unset, so a template
# set to "0" resolves to the default. Not worth defending against — no real
# section value is "0".
tmpl_ref() {
	local option=$1
	local default=$2
	local escaped=${default//,/#,}
	printf '#{?%s,#{E:%s},%s}' "$option" "$option" "$escaped"
}

# vim: ft=bash

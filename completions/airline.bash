# bash completion for airline
# shellcheck shell=bash
# shellcheck disable=SC2207 # compgen intentionally produces completion arrays.
# Generated from `airline help`; do not edit.
_airline_children () {
  case "$1" in
    '') printf %s version\ help\ session\ palette\ segment\ adapter\ layout\ classifier\ filter\ probe\ runner\ signal\ status\ health\ problem\ transaction ;;
    session) printf %s init\ apply\ show\ suspend\ resume\ toggle ;;
    palette) printf %s show\ use\ list\ register ;;
    segment) printf %s show ;;
    adapter) printf %s use\ load\ show\ list\ register ;;
    layout) printf %s use\ load\ show\ list\ register ;;
    classifier) printf %s show\ list\ register ;;
    filter) printf %s show\ list\ register ;;
    probe) printf %s show\ list\ register ;;
    runner) printf %s show\ list\ register\ run\ watch ;;
    status) printf %s set\ clear\ show ;;
    health) printf %s set\ clear\ show ;;
    problem) printf %s set\ clear\ show ;;
    transaction) printf %s show\ clear ;;
    *) return 1 ;;
  esac
}
_airline_usage () {
  case "$1" in
    version) printf %s '' ;;
    help) printf %s \[\<noun\>\ \[\<verb\>\]\] ;;
    session\ init) printf %s \[-t\ \<session\>\] ;;
    session\ apply) printf %s '' ;;
    session\ show) printf %s \[state\] ;;
    session\ suspend) printf %s '' ;;
    session\ resume) printf %s '' ;;
    session\ toggle) printf %s '' ;;
    palette\ show) printf %s \[name\|\<palette-element\>\] ;;
    palette\ use) printf %s \<palette\> ;;
    palette\ list) printf %s '' ;;
    palette\ register) printf %s \<dir\> ;;
    segment\ show) printf %s \[\<segment\>\] ;;
    adapter\ use) printf %s \<adapter\>... ;;
    adapter\ load) printf %s \<file\> ;;
    adapter\ show) printf %s '' ;;
    adapter\ list) printf %s '' ;;
    adapter\ register) printf %s \<dir\> ;;
    layout\ use) printf %s \<layout\> ;;
    layout\ load) printf %s \<file\> ;;
    layout\ show) printf %s \[name\|path\] ;;
    layout\ list) printf %s '' ;;
    layout\ register) printf %s \<dir\> ;;
    classifier\ show) printf %s \<classifier\> ;;
    classifier\ list) printf %s '' ;;
    classifier\ register) printf %s \<dir\> ;;
    filter\ show) printf %s \<filter\> ;;
    filter\ list) printf %s '' ;;
    filter\ register) printf %s \<dir\> ;;
    probe\ show) printf %s \<probe\> ;;
    probe\ list) printf %s '' ;;
    probe\ register) printf %s \<dir\> ;;
    runner\ show) printf %s \<runner\>\ \[\<arg\>...\] ;;
    runner\ list) printf %s '' ;;
    runner\ register) printf %s \<dir\> ;;
    runner\ run) printf %s \[--here\|--pane\ \[-h\|-v\]\|--window\]\ \[\<runner\>\]\ \[--classify\ \<classifier\>\]\ \[--filter\ \<filter\>\ \[--merge-stderr\]\]\ \[--probe\ \<probe\>\ \[\<arg\>...\]\]\ --\ \<command\>... ;;
    runner\ watch) printf %s \[--here\|--pane\ \[-h\|-v\]\|--window\]\ \[\<runner\>\]\ \[--probe\ \<probe\>\ \[\<arg\>...\]\] ;;
    status\ set) printf %s \<status-key\>\ \<active\|result\|attention\>\ \[--transient\]\ \[-t\ \<window\>\] ;;
    status\ clear) printf %s \<status-key\>\ \[-t\ \<window\>\] ;;
    status\ show) printf %s \[\<status-key\>\]\ \[-t\ \<window\>\] ;;
    health\ set) printf %s \[-t\ \<window\>\]\ \<health-key\>\ \<ok\|warn\|fail\>\ \[\<message\>...\] ;;
    health\ clear) printf %s \[-t\ \<window\>\]\ \<health-key\> ;;
    health\ show) printf %s \[-t\ \<window\>\]\ \[\<health-key\>\] ;;
    problem\ set) printf %s \<session\>\ \<problem-key\>\ \<ok\|warn\|fail\>\ \[\<message\>...\] ;;
    problem\ clear) printf %s \<session\>\ \<problem-key\> ;;
    problem\ show) printf %s \[\<session\>\ \[\<problem-key\>\]\] ;;
    transaction\ show) printf %s '' ;;
    transaction\ clear) printf %s \<session\|window\>\ \<target\>\ \<namespace\> ;;
    session) printf %s '' ;;
    palette) printf %s '' ;;
    segment) printf %s '' ;;
    adapter) printf %s '' ;;
    layout) printf %s '' ;;
    classifier) printf %s '' ;;
    filter) printf %s '' ;;
    probe) printf %s '' ;;
    runner) printf %s '' ;;
    signal) printf %s '' ;;
    status) printf %s '' ;;
    health) printf %s '' ;;
    problem) printf %s '' ;;
    transaction) printf %s '' ;;
    *) return 1 ;;
  esac
}
_airline_description () {
  case "$1" in
    version) printf %s Show\ the\ Airline\ release/API\ version ;;
    help) printf %s show\ command\ help ;;
    session\ init) printf %s seed\ defaults\,\ register\ paths\,\ publish\ the\ CLI\ handle\,\ and\ render ;;
    session\ apply) printf %s Commit\ global\ option\ edits\ and\ render\ the\ session ;;
    session\ show) printf %s print\ the\ active\ configuration\ or\ raw\ session\ state ;;
    session\ suspend) printf %s Mute\ the\ palette\ +\ trap\ the\ prefix\ \(session\ dormant\) ;;
    session\ resume) printf %s Restore\ vibrant\ colours\ +\ release\ the\ prefix ;;
    session\ toggle) printf %s Flip\ active/suspended ;;
    palette\ show) printf %s show\ the\ palette\ summary\ or\ one\ raw\ field ;;
    palette\ use) printf %s load\ a\ complete\ palette\ and\ repaint\ adapters ;;
    palette\ list) printf %s List\ palettes\ on\ the\ search\ path ;;
    palette\ register) printf %s add\ a\ palette\ search\ directory ;;
    segment\ show) printf %s show\ one\ segment\ or\ all\ segments ;;
    adapter\ use) printf %s apply\ palette\ roles\ to\ one\ or\ more\ plugins ;;
    adapter\ load) printf %s apply\ a\ one-off\ adapter\ script ;;
    adapter\ show) printf %s List\ applied\ adapters ;;
    adapter\ list) printf %s List\ adapters\ on\ the\ search\ path ;;
    adapter\ register) printf %s add\ an\ adapter\ search\ directory ;;
    layout\ use) printf %s apply\ a\ named\ layout\ definition ;;
    layout\ load) printf %s apply\ and\ record\ a\ one-off\ layout\ definition ;;
    layout\ show) printf %s show\ active\ layout\ provenance ;;
    layout\ list) printf %s List\ layouts\ on\ the\ search\ path ;;
    layout\ register) printf %s add\ a\ layout\ search\ directory ;;
    classifier\ show) printf %s show\ summary\,\ contract\,\ and\ resolved\ path ;;
    classifier\ list) printf %s List\ classifiers\ available\ to\ runners ;;
    classifier\ register) printf %s add\ a\ classifier\ search\ directory ;;
    filter\ show) printf %s show\ summary\,\ contract\,\ and\ resolved\ path ;;
    filter\ list) printf %s List\ filters\ available\ to\ runners ;;
    filter\ register) printf %s add\ a\ filter\ search\ directory ;;
    probe\ show) printf %s show\ summary\,\ arguments\,\ interval\,\ and\ resolved\ path ;;
    probe\ list) printf %s List\ probes\ available\ to\ runners ;;
    probe\ register) printf %s add\ a\ probe\ search\ directory ;;
    runner\ show) printf %s show\ one\ named\ composition\ with\ resolved\ defaults ;;
    runner\ list) printf %s List\ named\ runner\ compositions ;;
    runner\ register) printf %s add\ a\ runner\ search\ directory ;;
    runner\ run) printf %s run\ a\ command\ with\ monitoring ;;
    runner\ watch) printf %s watch\ probe\ state\ until\ interrupted ;;
    status\ set) printf %s set\ app\ status ;;
    status\ clear) printf %s clear\ app\ status ;;
    status\ show) printf %s show\ a\ window\'s\ app\ status ;;
    health\ set) printf %s set\ window\ health ;;
    health\ clear) printf %s clear\ window\ health ;;
    health\ show) printf %s show\ a\ window\'s\ health ;;
    problem\ set) printf %s set\ or\ recover\ a\ session\ problem ;;
    problem\ clear) printf %s clear\ a\ session\ problem ;;
    problem\ show) printf %s show\ all\ sessions\,\ one\ session\,\ or\ one\ problem ;;
    transaction\ show) printf %s List\ outstanding\ transactions\ and\ owner\ state ;;
    transaction\ clear) printf %s release\ one\ stale\ transaction ;;
    session) printf %s session\ commands ;;
    palette) printf %s palette\ commands ;;
    segment) printf %s segment\ commands ;;
    adapter) printf %s adapter\ commands ;;
    layout) printf %s layout\ commands ;;
    classifier) printf %s classifier\ commands ;;
    filter) printf %s filter\ commands ;;
    probe) printf %s probe\ commands ;;
    runner) printf %s runner\ commands ;;
    signal) printf %s signal\ commands ;;
    status) printf %s status\ commands ;;
    health) printf %s health\ commands ;;
    problem) printf %s problem\ commands ;;
    transaction) printf %s transaction\ commands ;;
    *) return 1 ;;
  esac
}

_airline_dynamic () {   # <semantic-type>
  local type="$1" noun line
  case "$type" in
    palette|adapter|layout|classifier|filter|probe|runner)
      noun="$type"
      command airline "$noun" list 2>/dev/null || true
      ;;
    palette-element)
      command airline palette show 2>/dev/null | while read -r line _; do
        [[ "$line" == name ]] || printf '%s\n' "$line"
      done
      ;;
    segment) command airline segment show 2>/dev/null | while read -r line _; do printf '%s\n' "$line"; done ;;
    status-key) command airline status show 2>/dev/null | while read -r line _; do printf '%s\n' "$line"; done ;;
    health-key) command airline health show 2>/dev/null | while read -r line _; do printf '%s\n' "$line"; done ;;
    session) command tmux list-sessions -F '#{session_name}' 2>/dev/null || true ;;
    window) command tmux list-windows -a -F '#{window_id}' 2>/dev/null || true ;;
  esac
}

_airline_values () {   # <usage-token>
  local token="$1" part inner
  token="${token#[}"; token="${token%]}"; token="${token%...}"
  if [[ "$token" == '<'*'>' ]]; then
    inner="${token#<}"; inner="${inner%>}"
    if [[ "$inner" == *"|"* ]]; then
      IFS='|' read -ra parts <<< "$inner"
      printf '%s\n' "${parts[@]}"
    else
      _airline_dynamic "$inner"
    fi
  elif [[ "$token" == *"|"* ]]; then
    IFS='|' read -ra parts <<< "$token"
    for part in "${parts[@]}"; do _airline_values "$part"; done
    return
  elif [[ "$token" != -* ]]; then
    printf '%s\n' "$token"
  fi
}

_airline_position_token () {   # <usage> <zero-based-position>
  local usage="$1" wanted="$2" token skip="" position=0
  local -a syntax
  usage="${usage//\[/}"; usage="${usage//\]/}"
  read -ra syntax <<< "$usage"
  for ((i=0; i<${#syntax[@]}; i++)); do
    token="${syntax[i]}"
    if [[ -n "$skip" ]]; then skip=""; continue; fi
    case "$token" in
      -t|--classify|--filter|--probe) skip=1; continue ;;
      --|--*|-*) continue ;;
    esac
    if (( position == wanted )); then printf '%s' "$token"; return; fi
    ((position++)) || true
  done
  [[ "$token" == *... && wanted -ge position ]] && printf '%s' "$token"
}

_airline_argument_position () {   # already-entered leaf arguments
  local skip="" count=0 arg
  for arg in "$@"; do
    if [[ -n "$skip" ]]; then skip=""; continue; fi
    case "$arg" in
      -t|--classify|--filter|--probe) skip=1 ;;
      --here|--pane|--window|-h|-v|--merge-stderr) ;;
      --) ;;
      *) ((count++)) || true ;;
    esac
  done
  printf '%s' "$count"
}

_airline_option_values () {   # <usage>
  local usage="$1" token part
  usage="${usage//\[/}"; usage="${usage//\]/}"
  read -ra syntax <<< "$usage"
  for token in "${syntax[@]}"; do
    IFS='|' read -ra parts <<< "$token"
    for part in "${parts[@]}"; do
      [[ "$part" == -* && "$part" != -- ]] && printf '%s\n' "$part"
    done
  done
}

_airline_problem_keys () {   # <session>
  local line
  command airline problem show "$1" 2>/dev/null | while read -r line _; do
    printf '%s\n' "$line"
  done
}

_airline_runner_complete () {   # <run|watch> <current> <prior-args...>
  local mode="$1" current="$2" previous="" arg; shift 2
  (( $# == 0 )) || previous="${!#}"
  for arg in "$@"; do
    if [[ "$arg" == -- ]]; then
      [[ "$mode" == run ]] && compopt -o default
      return
    fi
  done
  case "$previous" in
    --classify) COMPREPLY=( $(compgen -W "$(_airline_dynamic classifier)" -- "$current") ); return ;;
    --filter)   COMPREPLY=( $(compgen -W "$(_airline_dynamic filter)" -- "$current") ); return ;;
    --probe)    COMPREPLY=( $(compgen -W "$(_airline_dynamic probe)" -- "$current") ); return ;;
  esac
  local options='--here --pane --window -h -v --probe'
  [[ "$mode" == run ]] && options+=' --classify --filter --merge-stderr --'
  if [[ "$current" == -* ]]; then
    COMPREPLY=( $(compgen -W "$options" -- "$current") )
  elif (( $# == 0 )); then
    COMPREPLY=( $(compgen -W "$(_airline_dynamic runner) $options" -- "$current") )
  fi
}

_airline_completion () {
  local current="${COMP_WORDS[COMP_CWORD]}" top="${COMP_WORDS[1]:-}" verb path usage previous token position
  local -a prior
  COMPREPLY=()
  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W "$(_airline_children '')" -- "$current") )
    return
  fi
  if [[ "$top" == help ]]; then
    if (( COMP_CWORD == 2 )); then
      COMPREPLY=( $(compgen -W "$(_airline_children '')" -- "$current") )
    elif (( COMP_CWORD == 3 )); then
      COMPREPLY=( $(compgen -W "$(_airline_children "${COMP_WORDS[2]}")" -- "$current") )
    fi
    return
  fi
  if [[ -n "$(_airline_children "$top")" ]]; then
    if (( COMP_CWORD == 2 )); then
      COMPREPLY=( $(compgen -W "$(_airline_children "$top")" -- "$current") )
      return
    fi
    verb="${COMP_WORDS[2]}"; path="$top $verb"; prior=("${COMP_WORDS[@]:3:COMP_CWORD-3}")
  else
    path="$top"; prior=("${COMP_WORDS[@]:2:COMP_CWORD-2}")
  fi
  if [[ "$path" == 'runner run' || "$path" == 'runner watch' ]]; then
    _airline_runner_complete "$verb" "$current" "${prior[@]}"
    return
  fi
  usage="$(_airline_usage "$path")" || return
  previous=""; (( ${#prior[@]} == 0 )) || previous="${prior[-1]}"
  case "$previous" in
    -t)
      [[ "$path" == 'session init' ]] && token=session || token=window
      COMPREPLY=( $(compgen -W "$(_airline_dynamic "$token")" -- "$current") )
      return
      ;;
  esac
  if [[ "$path" == health\ * ]]; then
    local offset=0 count
    [[ "${prior[0]:-}" == -t ]] && offset=2
    count=$(( ${#prior[@]} - offset ))
    case "$verb:$count" in
      set:0|clear:0|show:0)
        COMPREPLY=( $(compgen -W "$(_airline_dynamic health-key) -t" -- "$current") )
        ;;
      set:1) COMPREPLY=( $(compgen -W 'ok warn fail' -- "$current") ) ;;
    esac
    return
  fi
  case "$current" in
    -*) COMPREPLY=( $(compgen -W "$(_airline_option_values "$usage")" -- "$current") ); return ;;
  esac
  position="$(_airline_argument_position "${prior[@]}")"
  if [[ "$path" == 'problem set' || "$path" == 'problem clear' || "$path" == 'problem show' ]] &&
     (( position == 1 )); then
    COMPREPLY=( $(compgen -W "$(_airline_problem_keys "${prior[0]}")" -- "$current") )
    return
  fi
  if [[ "$path" == 'transaction clear' ]]; then
    if (( position == 1 )); then
      COMPREPLY=( $(compgen -W "$(_airline_dynamic "${prior[0]}")" -- "$current") )
      return
    elif (( position == 2 )); then
      [[ "${prior[0]}" == session ]] && token='config problem' || token='status health'
      COMPREPLY=( $(compgen -W "$token" -- "$current") )
      return
    fi
  fi
  token="$(_airline_position_token "$usage" "$position")"
  case "$token" in
    *'<file>'*) compopt -o filenames; COMPREPLY=( $(compgen -f -- "$current") ) ;;
    *'<dir>'*)  compopt -o filenames; COMPREPLY=( $(compgen -d -- "$current") ) ;;
    *'<command>'*) compopt -o default ;;
    *) COMPREPLY=( $(compgen -W "$(_airline_values "$token") $(_airline_option_values "$usage")" -- "$current") ) ;;
  esac
}

complete -F _airline_completion airline

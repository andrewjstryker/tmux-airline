# bash completion for airline
# shellcheck shell=bash
# shellcheck disable=SC2207 # compgen intentionally produces completion arrays.
# Generated from `airline help`; do not edit.
_airline_children () {
  case "$1" in
    '') printf %s version\ help\ session\ palette\ segment\ widget\ layout\ classifier\ filter\ probe\ runner\ process\ status\ health\ problem\ transaction ;;
    session) printf %s init\ apply\ show\ suspend\ resume\ toggle ;;
    palette) printf %s describe\ show\ use\ load\ list\ register ;;
    segment) printf %s show ;;
    widget) printf %s describe\ list\ register\ run ;;
    layout) printf %s describe\ use\ load\ show\ list\ register ;;
    classifier) printf %s describe\ list\ register ;;
    filter) printf %s describe\ list\ register ;;
    probe) printf %s describe\ list\ register ;;
    runner) printf %s describe\ list\ register\ run\ watch ;;
    process) printf %s list\ show\ stop ;;
    status) printf %s set\ clear\ show ;;
    health) printf %s set\ ack\ clear\ show ;;
    problem) printf %s set\ close\ ack\ clear\ resolve\ show ;;
    transaction) printf %s show\ clear ;;
    *) return 1 ;;
  esac
}
_airline_usage () {
  case "$1" in
    version) printf %s '' ;;
    help) printf %s \[\<noun\>\ \[\<verb\>\]\] ;;
    session\ init) printf %s \[-t\ \<session-target\>\] ;;
    session\ apply) printf %s '' ;;
    session\ show) printf %s \[state\] ;;
    session\ suspend) printf %s '' ;;
    session\ resume) printf %s '' ;;
    session\ toggle) printf %s '' ;;
    palette\ describe) printf %s \<palette\> ;;
    palette\ show) printf %s \[name\|\<palette-element\>\] ;;
    palette\ use) printf %s \<palette\> ;;
    palette\ load) printf %s \<file\> ;;
    palette\ list) printf %s '' ;;
    palette\ register) printf %s \<dir\> ;;
    segment\ show) printf %s \[\<segment\>\] ;;
    widget\ describe) printf %s \<widget\>\ \[\<arg\>...\] ;;
    widget\ list) printf %s '' ;;
    widget\ register) printf %s \<dir\> ;;
    widget\ run) printf %s -t\ \<session-target\>\ \<instance\> ;;
    layout\ describe) printf %s \<layout\> ;;
    layout\ use) printf %s \<layout\> ;;
    layout\ load) printf %s \<file\> ;;
    layout\ show) printf %s \[name\|path\] ;;
    layout\ list) printf %s '' ;;
    layout\ register) printf %s \<dir\> ;;
    classifier\ describe) printf %s \<classifier\> ;;
    classifier\ list) printf %s '' ;;
    classifier\ register) printf %s \<dir\> ;;
    filter\ describe) printf %s \<filter\> ;;
    filter\ list) printf %s '' ;;
    filter\ register) printf %s \<dir\> ;;
    probe\ describe) printf %s \<probe\> ;;
    probe\ list) printf %s '' ;;
    probe\ register) printf %s \<dir\> ;;
    runner\ describe) printf %s \<runner\>\ \[\<arg\>...\] ;;
    runner\ list) printf %s '' ;;
    runner\ register) printf %s \<dir\> ;;
    runner\ run) printf %s \[--pane\ \[-h\|-v\]\|--window\]\ \{\<runner\>\ \[\<arg\>...\]\ \|\ \[--classify\ \<classifier\>\ \[\<arg\>...\]\]\ \[--filter\ \<filter\>\ \[\<arg\>...\]\]\ \[--merge-stderr\]\ \[--interval\ \<seconds\>\]\ \[--probe\ \<probe\>\ \[\<arg\>...\]\]\}\ \[--\ \<command\>...\] ;;
    runner\ watch) printf %s \[--pane\ \[-h\|-v\]\|--window\]\ \{\<runner\>\ \[\<arg\>...\]\ \|\ \[--interval\ \<seconds\>\]\ --probe\ \<probe\>\ \[\<arg\>...\]\} ;;
    process\ list) printf %s '' ;;
    process\ show) printf %s \<process-id\> ;;
    process\ stop) printf %s \<process-id\> ;;
    status\ set) printf %s \[-t\ \<pane-target\>\]\ \<active\|result\|attention\> ;;
    status\ clear) printf %s \[-t\ \<pane-target\>\] ;;
    status\ show) printf %s \[-t\ \<window-target\>\] ;;
    health\ set) printf %s \[-t\ \<pane-target\>\]\ \<contributor\>\ \<health-key\>\ \<ok\|warn\|fail\>\ \[\<message\>...\] ;;
    health\ ack) printf %s \[-t\ \<pane-target\>\]\ \<contributor\>\ \<health-key\> ;;
    health\ clear) printf %s \[-t\ \<pane-target\>\]\ \<contributor\>\ \<health-key\> ;;
    health\ show) printf %s \[--all\]\ \[-t\ \<pane-target\>\]\ \[\<contributor\>\ \[\<health-key\>\]\] ;;
    problem\ set) printf %s \[-t\ \<pane-target\>\]\ \<contributor\>\ \<problem-key\>\ \<ok\|warn\|fail\>\ \[\<message\>...\] ;;
    problem\ close) printf %s \[-t\ \<pane-target\>\|--session\ \<session-target\>\]\ \[\<contributor\>\ \[\<problem-key\>\]\] ;;
    problem\ ack) printf %s \<contributor\>\ \<problem-key\> ;;
    problem\ clear) printf %s \<contributor\>\ \<problem-key\> ;;
    problem\ resolve) printf %s \<contributor\>\ \<problem-key\> ;;
    problem\ show) printf %s \[--all\]\ \[\<contributor\>\ \[\<problem-key\>\]\] ;;
    transaction\ show) printf %s '' ;;
    transaction\ clear) printf %s \<global\|session\|window\>\ \<target\>\ \<namespace\> ;;
    session) printf %s '' ;;
    palette) printf %s '' ;;
    segment) printf %s '' ;;
    widget) printf %s '' ;;
    layout) printf %s '' ;;
    classifier) printf %s '' ;;
    filter) printf %s '' ;;
    probe) printf %s '' ;;
    runner) printf %s '' ;;
    process) printf %s '' ;;
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
    help) printf %s Show\ command\ help ;;
    session\ init) printf %s Seed\ defaults\,\ register\ paths\,\ publish\ the\ CLI\ handle\,\ and\ render ;;
    session\ apply) printf %s Commit\ global\ option\ edits\ and\ render\ the\ session ;;
    session\ show) printf %s Print\ the\ active\ configuration\ or\ raw\ session\ state ;;
    session\ suspend) printf %s Mute\ the\ palette\ +\ trap\ the\ prefix\ \(session\ dormant\) ;;
    session\ resume) printf %s Restore\ vibrant\ colours\ +\ release\ the\ prefix ;;
    session\ toggle) printf %s Flip\ active/suspended ;;
    palette\ describe) printf %s Describe\ metadata\ and\ evaluated\ roles\ without\ applying ;;
    palette\ show) printf %s Show\ the\ palette\ summary\ or\ one\ raw\ field ;;
    palette\ use) printf %s Load\ a\ complete\ palette\ and\ publish\ the\ session\ palette ;;
    palette\ load) printf %s Load\ a\ complete\ palette\ file\ and\ publish\ the\ session\ palette ;;
    palette\ list) printf %s List\ palettes\ on\ the\ search\ path ;;
    palette\ register) printf %s Add\ a\ palette\ search\ directory ;;
    segment\ show) printf %s Show\ one\ segment\ or\ all\ segments ;;
    widget\ describe) printf %s Inspect\ a\ widget\ format\ without\ observing ;;
    widget\ list) printf %s List\ widgets\ on\ the\ search\ path ;;
    widget\ register) printf %s Add\ a\ widget\ search\ directory ;;
    widget\ run) printf %s Refresh\ an\ active\ widget\ instance ;;
    layout\ describe) printf %s Describe\ metadata\,\ evaluated\ segments\,\ and\ widgets\ without\ applying ;;
    layout\ use) printf %s Apply\ a\ named\ layout\ definition ;;
    layout\ load) printf %s Apply\ and\ record\ a\ one-off\ layout\ definition ;;
    layout\ show) printf %s Show\ active\ layout\ provenance ;;
    layout\ list) printf %s List\ layouts\ on\ the\ search\ path ;;
    layout\ register) printf %s Add\ a\ layout\ search\ directory ;;
    classifier\ describe) printf %s Describe\ metadata\,\ options\,\ and\ resolved\ path ;;
    classifier\ list) printf %s List\ classifiers\ available\ to\ runners ;;
    classifier\ register) printf %s Add\ a\ classifier\ search\ directory ;;
    filter\ describe) printf %s Describe\ metadata\,\ options\,\ and\ resolved\ path ;;
    filter\ list) printf %s List\ filters\ available\ to\ runners ;;
    filter\ register) printf %s Add\ a\ filter\ search\ directory ;;
    probe\ describe) printf %s Describe\ metadata\,\ options\,\ interval\,\ and\ resolved\ path ;;
    probe\ list) printf %s List\ probes\ available\ to\ runners ;;
    probe\ register) printf %s Add\ a\ probe\ search\ directory ;;
    runner\ describe) printf %s Describe\ one\ named\ composition\ with\ resolved\ defaults ;;
    runner\ list) printf %s List\ named\ runner\ compositions ;;
    runner\ register) printf %s Add\ a\ runner\ search\ directory ;;
    runner\ run) printf %s Run\ a\ command\ or\ repeated\ probe\ in\ the\ foreground ;;
    runner\ watch) printf %s Start\ a\ background\ probe\ and\ print\ its\ process\ ID ;;
    process\ list) printf %s List\ active\ Airline\ invocations\ on\ this\ server ;;
    process\ show) printf %s Inspect\ an\ active\ invocation ;;
    process\ stop) printf %s Stop\ an\ invocation\ and\ its\ owned\ work ;;
    status\ set) printf %s Set\ a\ pane\'s\ workflow\ status ;;
    status\ clear) printf %s Delete\ a\ pane\ status ;;
    status\ show) printf %s Show\ a\ window\'s\ pane\ statuses\ and\ revisions ;;
    health\ set) printf %s Set\ a\ pane\'s\ health ;;
    health\ ack) printf %s Acknowledge\ and\ hide\ one\ pane\ health\ claim ;;
    health\ clear) printf %s Delete\ one\ pane\ health\ claim ;;
    health\ show) printf %s Show\ active\ or\ acknowledged\ pane\ health ;;
    problem\ set) printf %s Report\ or\ recover\ an\ origin\ claim ;;
    problem\ close) printf %s Close\ an\ origin\'s\ claims ;;
    problem\ ack) printf %s Acknowledge\ and\ hide\ the\ current\ problem\ state ;;
    problem\ clear) printf %s Delete\ a\ problem\,\ its\ history\,\ and\ all\ origin\ claims ;;
    problem\ resolve) printf %s Declare\ the\ capability\ restored\ globally\ and\ retain\ resolved\ history ;;
    problem\ show) printf %s Show\ active\ problems\ or\ the\ complete\ lifecycle\ ledger ;;
    transaction\ show) printf %s List\ outstanding\ transactions\ and\ owner\ state ;;
    transaction\ clear) printf %s Release\ one\ stale\ transaction ;;
    session) printf %s session\ commands ;;
    palette) printf %s palette\ commands ;;
    segment) printf %s segment\ commands ;;
    widget) printf %s widget\ commands ;;
    layout) printf %s layout\ commands ;;
    classifier) printf %s classifier\ commands ;;
    filter) printf %s filter\ commands ;;
    probe) printf %s probe\ commands ;;
    runner) printf %s runner\ commands ;;
    process) printf %s process\ commands ;;
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
    palette|widget|layout|classifier|filter|probe|runner)
      noun="$type"
      command airline "$noun" list 2>/dev/null || true
      ;;
    process-id) command airline process list 2>/dev/null | awk '{print $1}' ;;
    palette-element)
      command airline palette show 2>/dev/null | while read -r line _; do
        [[ "$line" == name ]] || printf '%s\n' "$line"
      done
      ;;
    segment) command airline segment show 2>/dev/null | while read -r line _; do printf '%s\n' "$line"; done ;;
    health-contributor) command airline health show 2>/dev/null | awk '{print $1}' | sort -u ;;
    health-key) command airline health show 2>/dev/null | awk '{print $2}' | sort -u ;;
    problem-contributor) command airline problem show --all 2>/dev/null | awk '$1 !~ /^(pane|session):/ {print $1}' | sort -u ;;
    problem-key) command airline problem show --all 2>/dev/null | awk '$1 !~ /^(pane|session):/ {print $2}' | sort -u ;;
    session-target) command tmux list-sessions -F '#{session_name}' 2>/dev/null || true ;;
    pane-target) command tmux list-panes -a -F '#{pane_id}' 2>/dev/null || true ;;
    window-target) command tmux list-windows -a -F '#{window_id}' 2>/dev/null || true ;;
  esac
}

_airline_complete_dynamic () {   # <semantic-type> <prefix>
  local candidate
  COMPREPLY=()
  while IFS= read -r candidate; do
    if [[ "$candidate" == "$2"* ]]; then COMPREPLY+=("$candidate"); fi
  done < <(_airline_dynamic "$1")
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
      -t|--classify|--filter|--probe|--interval) skip=1; continue ;;
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
      -t|--pane|--session|--classify|--filter|--probe|--interval) skip=1 ;;
      --window|-h|-v|--merge-stderr) ;;
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

_airline_runner_complete () {   # <run|watch> <current> <prior-args...>
  local mode="$1" current="$2" previous="" arg placement_seen=""; shift 2
  (( $# == 0 )) || previous="${!#}"
  for arg in "$@"; do
    if [[ "$arg" == -- ]]; then
      [[ "$mode" == run ]] && compopt -o default
      return
    fi
    [[ "$arg" != --pane && "$arg" != --window ]] || placement_seen=1
  done
  case "$previous" in
    --classify) COMPREPLY=( $(compgen -W "$(_airline_dynamic classifier)" -- "$current") ); return ;;
    --filter)   COMPREPLY=( $(compgen -W "$(_airline_dynamic filter)" -- "$current") ); return ;;
    --probe)    COMPREPLY=( $(compgen -W "$(_airline_dynamic probe)" -- "$current") ); return ;;
    --interval) return ;;
  esac
  local options='--interval --probe'
  [[ -n "$placement_seen" ]] || options="--pane --window $options"
  [[ "$previous" != --pane ]] || options="-h -v $options"
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
      if [[ "$path" == 'session init' ]]; then token=session-target
      elif [[ "$path" == 'status set' || "$path" == 'status clear' || "$path" == problem\ * ]]; then token=pane-target
      else token=window-target; fi
      _airline_complete_dynamic "$token" "$current"
      return
      ;;
    --pane)
      _airline_complete_dynamic pane-target "$current"
      return
      ;;
    --session)
      _airline_complete_dynamic session-target "$current"
      return
      ;;
  esac
  if [[ "$path" == health\ * ]]; then
    local offset=0 count
    [[ "${prior[0]:-}" == -t ]] && offset=2
    count=$(( ${#prior[@]} - offset ))
    case "$verb:$count" in
      set:0|clear:0|show:0)
        COMPREPLY=( $(compgen -W "$(_airline_dynamic health-contributor) -t" -- "$current") )
        ;;
      set:1|clear:1|show:1) COMPREPLY=( $(compgen -W "$(_airline_dynamic health-key)" -- "$current") ) ;;
      set:2) COMPREPLY=( $(compgen -W 'ok warn fail' -- "$current") ) ;;
    esac
    return
  fi
  case "$current" in
    -*) COMPREPLY=( $(compgen -W "$(_airline_option_values "$usage")" -- "$current") ); return ;;
  esac
  position="$(_airline_argument_position "${prior[@]}")"
  if [[ "$path" == problem\ * ]]; then
    case "$verb:$position" in
      set:0|close:0|clear:0|resolve:0|show:0)
        token=""
        if (( ${#prior[@]} == 0 )); then token="$(_airline_option_values "$usage" || true)"; fi
        COMPREPLY=( $(compgen -W "$(_airline_dynamic problem-contributor) $token" -- "$current") )
        return ;;
      set:1|close:1|clear:1|resolve:1|show:1)
        COMPREPLY=( $(compgen -W "$(_airline_dynamic problem-key)" -- "$current") ); return ;;
      set:2) COMPREPLY=( $(compgen -W 'ok warn fail' -- "$current") ); return ;;
    esac
  fi
  if [[ "$path" == 'transaction clear' ]]; then
    if (( position == 0 )); then
      COMPREPLY=( $(compgen -W 'global session window' -- "$current") )
      return
    elif (( position == 1 )); then
      if [[ "${prior[0]}" == global ]]; then token=server; else token="$(_airline_dynamic "${prior[0]}")"; fi
      COMPREPLY=( $(compgen -W "$token" -- "$current") )
      return
    elif (( position == 2 )); then
      case "${prior[0]}" in
        global) token=problem ;;
        session) token=config ;;
        window) token='status health' ;;
      esac
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

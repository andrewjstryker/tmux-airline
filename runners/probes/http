#!/usr/bin/env bash
#| summary: Check one or more HTTP endpoints
#| usage: [--expect <regex>] [--timeout <seconds>] [--connect-timeout <seconds>] <endpoint> [<endpoint>...]
#| interval: 5
# Show one polling result per endpoint and report its condition separately. The
# human-readable stdout format is a convention; airline does not interpret it.

_http_probe_parse () {   # Populate caller-local policy and endpoints for validation or execution.
  _http_expect='2[0-9][0-9]'
  _http_timeout=5
  _http_connect_timeout=2
  _http_endpoints=()
  local option value regex rc
  while (( $# )); do
    option="$1"
    # options:begin
    case "$option" in
      --expect) ;; #| <regex> — full status-code match; default 2[0-9][0-9]
      --timeout) ;; #| <seconds> — positive total request budget; default 5
      --connect-timeout) ;; #| <seconds> — positive connection budget; default 2
      -*) printf 'http probe: unknown option: %s\n' "$option" >&2; return 2 ;;
      *) break ;;
    esac
    # options:end
    if (( $# < 2 )); then
      printf 'http probe: %s needs a value\n' "$option" >&2
      return 2
    fi
    value="$2"
    if [[ "$option" == --expect ]]; then
      regex="$value"
      if [[ '' =~ $regex ]]; then
        rc=0
      else
        # A regex condition returns 2 for invalid syntax, 1 for no match.
        # shellcheck disable=SC2319
        rc=$?
      fi
      if [[ -z "$value" ]] || (( rc == 2 )); then
        printf 'http probe: --expect needs a valid nonempty regular expression\n' >&2
        return 2
      fi
      _http_expect="$value"
    else
      if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ || -z "${value//[0.]/}" ]]; then
        printf 'http probe: %s needs positive seconds\n' "$option" >&2
        return 2
      fi
      case "$option" in
        --timeout) _http_timeout="$value" ;;
        --connect-timeout) _http_connect_timeout="$value" ;;
      esac
    fi
    shift 2
  done
  if (( $# == 0 )); then
    printf 'http probe: need at least one endpoint\n' >&2
    return 2
  fi
  for value in "$@"; do
    if [[ -z "$value" || "$value" == -* ]]; then
      printf 'http probe: endpoints must be nonempty; options must precede endpoints\n' >&2
      return 2
    fi
  done
  _http_endpoints=("$@")
}

airline_runner_probe_parse () {
  local _http_expect _http_timeout _http_connect_timeout
  local -a _http_endpoints=()
  _http_probe_parse "$@"
}

airline_runner_probe () {   # <lifecycle-pid> <health> <problem> [<option>...] <endpoint>...
  local _pid="$1" health="$2" problem="$3" endpoint code key byte i LC_ALL=C; shift 3
  local _http_expect _http_timeout _http_connect_timeout regex
  local -a _http_endpoints=()
  _http_probe_parse "$@" || return
  regex="^($_http_expect)$"
  if ! command -v curl >/dev/null 2>&1; then
    "$problem" airline-http curl fail "curl is not installed"
    return
  fi
  # withdraw claim (no-op if there is not a claim) or propogate return value
  "$problem" airline-http curl ok || return

  for endpoint in "${_http_endpoints[@]}"; do
    # Hex-encoded endpoint bytes are stable, collision-free public claim keys.
    key=endpoint-
    for (( i=0; i<${#endpoint}; i++ )); do
      printf -v byte '%02x' "'${endpoint:i:1}"
      key+="$byte"
    done
    code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
      --connect-timeout "$_http_connect_timeout" --max-time "$_http_timeout" -- "$endpoint")" || code=""
    if [[ "$code" =~ ^[1-5][0-9][0-9]$ && "$code" =~ $regex ]]; then
      printf 'ok %s %s\n' "$code" "$endpoint"
      "$health" airline-http "$key" ok || return
    else
      printf 'fail %s %s\n' "${code:-000}" "$endpoint"
      "$health" airline-http "$key" fail "HTTP ${code:-000} from $endpoint" || return
    fi
  done
}

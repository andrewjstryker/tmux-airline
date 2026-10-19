#!/usr/bin/env bats
load ../test_helper/bats-support/load
load ../test_helper/bats-assert/load

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  mkdir "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/nmcli" <<'STUB'
#!/usr/bin/env bash
[[ "${NM_FAIL:-0}" == 0 ]] || exit 1
case "$*" in
  '--colors no -t -f CONNECTIVITY general status') printf '%s\n' "$CONNECTIVITY" ;;
  '--colors no -t -f DEVICE,TYPE,STATE device status') printf '%s\n' "$DEVICES" ;;
  *) exit 2 ;;
esac
STUB
  cat > "$BATS_TEST_TMPDIR/bin/ip" <<'STUB'
#!/usr/bin/env bash
[[ "${IP_FAIL:-0}" == 0 ]] || exit 1
case "$*" in
  '-4 -o route show default') printf '%s\n' "$ROUTES4" ;;
  '-6 -o route show default') printf '%s\n' "$ROUTES6" ;;
  *) exit 2 ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/"*
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  export CONNECTIVITY=full NM_FAIL=0 IP_FAIL=0
  export DEVICES=$'eth0:ethernet:connected\nwlan0:wifi:connected\ntun0:tun:connected'
  export ROUTES4=$'default dev tun0 metric 1\ndefault via 10.0.0.1 dev wlan0 metric 600\ndefault via 10.0.0.1 dev eth0 metric 100'
  export ROUTES6=''
}

@test "network chooses physical default route by metric beneath a VPN" {
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_success
  assert_output 'wired full'
  ROUTES4=$'default dev tun0 metric 1\ndefault dev eth0 metric 600\ndefault dev wlan0 metric 100'
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output 'wireless full'
}

@test "network supports IPv6 and distinguishes limited portal disconnected and unknown" {
  ROUTES4=''
  ROUTES6='default via fe80::1 dev wlan0 proto ra metric 600'
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output 'wireless full'
  for CONNECTIVITY in limited portal; do
    run "$PROJECT_ROOT/layouts/widgets/online"
    assert_output 'wireless limited'
  done
  ROUTES6=''
  CONNECTIVITY=limited
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output 'wired limited'
  CONNECTIVITY=none
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output disconnected
  CONNECTIVITY=unknown
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output unknown
}

@test "network avoids guessing on missing observations unsupported devices and command failures" {
  NM_FAIL=1
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_success
  assert_output unknown
  NM_FAIL=0 IP_FAIL=1
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output unknown
  IP_FAIL=0
  DEVICES='wwan0:gsm:connected'
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output unknown
  DEVICES='eth0:ethernet:disconnected'
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output unknown
  DEVICES='eth0:ethernet:connected'
  ROUTES4=''
  run "$PROJECT_ROOT/layouts/widgets/online"
  assert_output unknown
}

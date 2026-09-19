#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d); trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"; MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOD/bin" "$MOD/run" "$MOD/logs" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cat > "$MOD/config/config.toml" <<'CONFIG'
ipv4 = "10.42.0.10/24"
rpc_portal = "127.0.0.1:15888"
[network_identity]
network_name = "test"
network_secret = "secret"
[flags]
dev_name = "tiernest0"
CONFIG
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
case "$*" in
  "-4 route show table 20110") exit 0 ;;
  "-4 route get 1.1.1.1")
    if [ -n "${TEST_GATEWAY:-}" ]; then via="via $TEST_GATEWAY "; else via=""; fi
    echo "1.1.1.1 ${via}dev ${TEST_DEV:-wlan0} table ${TEST_TABLE:-wlan0} src ${TEST_SRC:-192.168.0.105}"
    ;;
  "link show dev tiernest0") exit 0 ;;
  "-o -4 addr show")
    echo '40: tiernest0 inet 10.42.0.10/24 scope global tiernest0'
    echo '42: tun0 inet 10.42.0.10/24 scope global tun0'
    ;;
  "-4 rule show") exit 0 ;;
  *) exit 0 ;;
esac
MOCK
cat > "$MOCK/dumpsys" <<'MOCK'
#!/bin/sh
if [ "${APP_VPN:-0}" = 1 ]; then
  echo 'NetworkAgentInfo{VPN CONNECTED extra: VPN:com.kkrainbow.easytier sessionId=TauriVpnService InterfaceName: tun0}'
fi
MOCK
cat > "$MOD/bin/easytier-cli" <<'MOCK'
#!/bin/sh
case "${RPC_MODE:-healthy}" in
  healthy) echo '[{"hostname":"local","next_hop_hostname":"Local"}]' ;;
  invalid) echo 'not-json' ;;
  timeout) exit 124 ;;
esac
MOCK
chmod +x "$MOCK"/* "$MOD/bin/easytier-cli"
export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD"
. "$MOD/common.sh"

core_running() { [ "${CORE_UP:-1}" = 1 ]; }
CORE_UP=1; export CORE_UP
[[ "$(find_tun_device)" = tiernest0 ]]
CORE_UP=0; export CORE_UP
! find_tun_device >/dev/null
# With the managed core stopped, the official APP tun0 must be classified as external,
# never as TierNest's own TUN.
[[ "$(external_vpn_state)" == 'tun0=10.42.0.10/24,' ]]

CORE_UP=1; export CORE_UP
TEST_DEV=wlan0 TEST_GATEWAY=192.168.0.1 TEST_SRC=192.168.0.105 TEST_TABLE=wlan0; export TEST_DEV TEST_GATEWAY TEST_SRC TEST_TABLE
[[ "$(underlay_signature)" == 'dev=wlan0|via=192.168.0.1|src=192.168.0.105|table=wlan0' ]]
TEST_DEV=rmnet_data3 TEST_GATEWAY='' TEST_SRC=100.64.0.2 TEST_TABLE=rmnet_data3; export TEST_DEV TEST_GATEWAY TEST_SRC TEST_TABLE
[[ "$(underlay_signature)" == 'dev=rmnet_data3|via=|src=100.64.0.2|table=rmnet_data3' ]]

RPC_MODE=healthy; export RPC_MODE; [[ "$(easytier_rpc_state)" = healthy ]]
RPC_MODE=invalid; export RPC_MODE; [[ "$(easytier_rpc_state)" = invalid ]]
RPC_MODE=timeout; export RPC_MODE; [[ "$(easytier_rpc_state)" = timeout ]]
CORE_UP=0; export CORE_UP; [[ "$(easytier_rpc_state)" = stopped ]]

# Only established TCP and connected UDP count as live. SYN_SENT/CLOSE_WAIT must
# not suppress a recovery restart.
core_pid() { echo 123; }
core_transport_sockets() {
  printf 'tcp|203.0.113.1|443|02|1\n'
  printf 'tcp|203.0.113.2|443|08|2\n'
  printf 'tcp|203.0.113.3|443|01|3\n'
  printf 'udp|203.0.113.4|11010|07|4\n'
}
[[ "$(live_transport_endpoint_count)" = 2 ]]

APP_VPN=1; export APP_VPN
easytier_app_vpn_active
[[ "$(easytier_app_vpn_state)" == *TauriVpnService* ]]
APP_VPN=0; export APP_VPN
! easytier_app_vpn_active

# Reconnect suppression is allowed only for a responsive core with live sockets.
CORE_UP=1; export CORE_UP
overlay_remote_peer_count() { echo 0; }
easytier_rpc_state() { echo healthy; }
live_transport_endpoint_count() { echo 2; }
should_wait_for_transport_reconnect overlay-unreachable
live_transport_endpoint_count() { echo 0; }
! should_wait_for_transport_reconnect overlay-unreachable
easytier_rpc_state() { echo timeout; }
live_transport_endpoint_count() { echo 2; }
! should_wait_for_transport_reconnect overlay-unreachable

echo 'Recovery signal test passed.'

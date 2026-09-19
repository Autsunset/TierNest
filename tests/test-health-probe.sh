#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOD/bin" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
sed -i 's/^ROUTE_MODE=.*/ROUTE_MODE=dedicated/' "$MOD/settings.conf"
cp "$ROOT/module/config/config.toml" "$MOD/config/config.toml"
cat > "$MOCK/ping" <<'MOCK'
#!/bin/sh
target=""
for arg in "$@"; do target=$arg; done
case "${PING_MODE:-healthy}:$target" in
  healthy:192.168.50.1) exit 0 ;;
  proxy:192.168.50.1|overlay:192.168.50.1|offline:192.168.50.1) exit 1 ;;
  proxy:1.1.1.1|overlay:1.1.1.1) exit 0 ;;
  offline:1.1.1.1) exit 1 ;;
  proxy:10.42.0.1) exit 0 ;;
  overlay:10.42.0.1) exit 1 ;;
  *) exit 1 ;;
esac
MOCK
chmod +x "$MOCK/ping"
cat > "$MOD/bin/easytier-cli" <<'MOCK'
#!/bin/sh
case "${ROUTE_LIST_MODE:-local}" in
  local)
    cat <<'JSON'
[
  {"hostname":"Example-Phone-A","next_hop_hostname":"Local"}
]
JSON
    ;;
  remote)
    cat <<'JSON'
[
  {"hostname":"Example-Phone-A","next_hop_hostname":"Local"},
  {"hostname":"PublicRelay","next_hop_hostname":"DIRECT"}
]
JSON
    ;;
  invalid) echo 'not-json'; exit 0 ;;
esac
MOCK
chmod +x "$MOD/bin/easytier-cli"
export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD"
. "$MOD/common.sh"
HEALTH_CHECK_ENABLED=1
HEALTH_PROXY_TARGET=192.168.50.1
HEALTH_EASYTIER_TARGET=10.42.0.1
HEALTH_INTERNET_TARGET=1.1.1.1
find_tun_device() { echo tiernest0; }
PING_MODE=healthy; export PING_MODE; [[ "$(health_probe_state)" == healthy ]]
PING_MODE=proxy; export PING_MODE; [[ "$(health_probe_state)" == proxy-unreachable ]]
PING_MODE=overlay; export PING_MODE; [[ "$(health_probe_state)" == overlay-unreachable ]]
PING_MODE=offline; export PING_MODE; [[ "$(health_probe_state)" == underlying-offline ]]

core_running() { return 0; }
easytier_rpc_state() { echo healthy; }
live_transport_endpoint_count() { echo 2; }
ROUTE_LIST_MODE=local; export ROUTE_LIST_MODE
[[ "$(overlay_remote_peer_count)" == 0 ]]
should_wait_for_transport_reconnect overlay-unreachable
ROUTE_LIST_MODE=remote; export ROUTE_LIST_MODE
[[ "$(overlay_remote_peer_count)" == 1 ]]
! should_wait_for_transport_reconnect overlay-unreachable
ROUTE_LIST_MODE=invalid; export ROUTE_LIST_MODE
[[ "$(overlay_remote_peer_count)" == -1 ]]
! should_wait_for_transport_reconnect proxy-unreachable
live_transport_endpoint_count() { echo 0; }
ROUTE_LIST_MODE=local; export ROUTE_LIST_MODE
! should_wait_for_transport_reconnect overlay-unreachable

echo 'Health probe test passed.'

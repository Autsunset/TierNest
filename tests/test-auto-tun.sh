#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"; MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOD/logs" "$MOD/run" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cat > "$MOD/config/config.toml" <<'CONFIG'
hostname = "Example-Tablet"
ipv4 = "10.42.0.51/24"
[network_identity]
network_name = "test"
network_secret = "secret"
[flags]
dev_name = ""
CONFIG
cat > "$MOCK/ip" <<'MOCKIP'
#!/bin/sh
case "$*" in
  "-4 route show table 20110") exit 0 ;;
  "-o -4 addr show")
    echo '10: wlan0 inet 192.168.0.103/24 scope global wlan0'
    echo '20: tun0 inet 10.8.0.2/32 scope global tun0'
    echo '21: tun1 inet 10.42.0.51/24 scope global tun1'
    echo '22: wg0 inet 10.9.0.2/32 scope global wg0'
    ;;
  "-o -4 addr show dev "*) exit 0 ;;
  "-o link show")
    echo '20: tun0: <UP>'
    echo '21: tun1: <UP>'
    ;;
  "-4 rule show") exit 0 ;;
  *) exit 0 ;;
esac
MOCKIP
chmod +x "$MOCK/ip"
export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD"
. "$MOD/common.sh"
core_running() { return 0; }
[[ "$(find_tun_device)" = tun1 ]]
state=$(external_vpn_state)
[[ "$state" == 'tun0=10.8.0.2/32,wg0=10.9.0.2/32,' ]]
[[ "$state" != *tun1* ]]
echo 'Automatic EasyTier tunX detection test passed.'

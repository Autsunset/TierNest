#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cp "$ROOT/module/config/config.toml" "$MOD/config/config.toml"
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
if [ "$*" = "-o -4 addr show" ]; then
  echo '5: tunl0    inet 192.0.2.1/32 scope global tunl0'
  echo '32: tiernest0    inet 10.42.0.10/24 scope global tiernest0'
  echo '33: tun0    inet 172.19.0.1/30 scope global tun0'
  echo '34: wg0    inet 10.8.0.2/32 scope global wg0'
  echo '35: Meta    inet 198.18.0.1/30 scope global Meta'
fi
MOCK
chmod +x "$MOCK/ip"
PATH="$MOCK:/usr/bin:/bin"
export PATH MODDIR="$MOD"
. "$MOD/common.sh"
state=$(external_vpn_state)
[[ "$state" == 'Meta=198.18.0.1/30,tun0=172.19.0.1/30,wg0=10.8.0.2/32,' ]]
[[ "$state" != *tiernest0* ]]
[[ "$state" != *tunl0* ]]
core_running() { return 0; }
find_tun_device() { echo tun0; }
state=$(external_vpn_state)
[[ "$state" == 'Meta=198.18.0.1/30,wg0=10.8.0.2/32,' ]]
[[ "$state" != *tun0* ]]
echo 'External VPN state test passed.'

#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
STATE="$TMP/state"
mkdir -p "$MOD/config" "$MOD/logs" "$MOD/run" "$MOCK" "$STATE"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cp "$ROOT/module/config/config.toml" "$MOD/config/config.toml"
echo legacy > "$MOD/config/route-strategy.state"
: > "$STATE/wlan0-routes"
cat > "$MOCK/ip" <<'MOCKIP'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}
ARGS="$*"
case "$ARGS" in
  "-4 route show table 20110") exit 0 ;;
  "-4 route show table wlan0") cat "$STATE/wlan0-routes" ;;
  "-4 rule show")
    echo '0: from all lookup local'
    echo '9980: from all lookup 20110'
    echo '16000: from all fwmark 0x10064/0x1ffff iif lo lookup wlan0'
    ;;
  "-o -4 addr show")
    echo '10: wlan0 inet 192.168.0.103/24 brd 192.168.0.255 scope global wlan0'
    echo '14: tiernest0 inet 10.42.0.51/24 brd 10.42.0.255 scope global tiernest0'
    ;;
  "-4 route replace table wlan0 "*)
    cidr=$6; iface=$8
    awk -v c="$cidr" '$1 != c' "$STATE/wlan0-routes" > "$STATE/routes.tmp" || true
    printf '%s dev %s\n' "$cidr" "$iface" >> "$STATE/routes.tmp"
    mv "$STATE/routes.tmp" "$STATE/wlan0-routes"
    ;;
  "-4 route del table wlan0 "*)
    cidr=$6
    awk -v c="$cidr" '$1 != c' "$STATE/wlan0-routes" > "$STATE/routes.tmp" || true
    mv "$STATE/routes.tmp" "$STATE/wlan0-routes"
    ;;
  *) exit 0 ;;
esac
MOCKIP
chmod +x "$MOCK/ip"
export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" TEST_STATE="$STATE"
. "$MOD/common.sh"
cat > "$MOD/run/test-overlay" <<'ROUTES'
10.42.0.0/24
192.168.50.0/24
ROUTES
cat > "$MOD/run/test-local" <<'LOCAL'
192.168.0.0/24|wlan0
LOCAL
sync_android_network_routes tiernest0 "$MOD/run/test-overlay" "$MOD/run/test-local"
grep -q '^wlan0|10.42.0.0/24|tiernest0$' "$ANDROID_ROUTE_SPECS_FILE"
grep -q '^wlan0|192.168.50.0/24|tiernest0$' "$ANDROID_ROUTE_SPECS_FILE"
grep -q '^10.42.0.0/24 dev tiernest0$' "$STATE/wlan0-routes"
grep -q '^192.168.50.0/24 dev tiernest0$' "$STATE/wlan0-routes"
# Simulate netd deleting one route; periodic sync must restore it.
grep -v '^192.168.50.0/24 ' "$STATE/wlan0-routes" > "$STATE/routes.tmp"
mv "$STATE/routes.tmp" "$STATE/wlan0-routes"
sync_android_network_routes tiernest0 "$MOD/run/test-overlay" "$MOD/run/test-local"
grep -q '^192.168.50.0/24 dev tiernest0$' "$STATE/wlan0-routes"
cleanup_android_network_routes
[[ ! -s "$STATE/wlan0-routes" ]]
[[ ! -e "$ANDROID_ROUTE_SPECS_FILE" ]]

echo 'Android app route mirror test passed.'

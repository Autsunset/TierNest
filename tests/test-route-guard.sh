#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
STATE="$TMP/state"
mkdir -p "$MOD/config" "$MOD/bin" "$MOCK" "$STATE"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
sed -i 's/^ROUTE_MODE=.*/ROUTE_MODE=dedicated/' "$MOD/settings.conf"
cp "$ROOT/module/config/config.toml" "$MOD/config/config.toml"
cp "$ROOT/module/module.prop" "$MOD/module.prop"
: > "$MOD/bin/easytier-core"
chmod +x "$MOD/bin/easytier-core"

cat > "$MOCK/getprop" <<'MOCK'
#!/bin/sh
case "$1" in
  ro.product.brand) echo Test ;;
  ro.product.model) echo Device ;;
  ro.build.version.sdk) echo 36 ;;
esac
MOCK

cat > "$MOCK/easytier-cli" <<'MOCK'
#!/bin/sh
cat <<'JSON'
[{"ipv4":"10.0.0.20/24","proxy_cidrs":"172.16.0.0/16,192.168.50.0/24,0.0.0.0/0"}]
JSON
MOCK

cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}
ARGS="$*"
case "$ARGS" in
  "link show dev tiernest0") exit 0 ;;
  "-o -4 addr show dev tiernest0")
    echo "12: tiernest0    inet 10.0.0.20/24 scope global tiernest0"
    ;;
  "-o -4 addr show")
    echo "12: tiernest0    inet 10.0.0.20/24 scope global tiernest0"
    if [ ! -f "$STATE/lan_down" ]; then
      echo "20: wlan0    inet 192.168.50.50/24 brd 192.168.50.255 scope global wlan0"
    fi
    echo "21: tun0    inet 10.8.0.2/32 scope global tun0"
    echo "22: rmnet_data4    inet 198.18.0.2/32 scope global rmnet_data4"
    ;;
  "-o link show")
    echo "5: tunl0: <NOARP,UP,LOWER_UP> mtu 1480"
    echo "6: tun2: <POINTOPOINT,UP,LOWER_UP> mtu 1380"
    ;;
  "-4 route show table main dev tiernest0")
    echo "10.10.0.0/16 dev tiernest0 proto static"
    ;;
  "-4 rule show")
    cat "$STATE/rules" 2>/dev/null || true
    ;;
  "-4 rule add pref 9980 lookup 20110")
    echo "9980: from all lookup 20110" > "$STATE/rules"
    ;;
  "-4 rule del pref 9980")
    : > "$STATE/rules"
    ;;
  "-4 route flush table 20110")
    : > "$STATE/routes"
    ;;
  "-4 route show table 20110")
    sed 's#/32 dev# dev#' "$STATE/routes" 2>/dev/null || true
    ;;
  "-4 route replace table 20110 "*)
    cidr=$6
    iface=$8
    awk -v c="$cidr" '$1 != c' "$STATE/routes" 2>/dev/null > "$STATE/routes.tmp" || true
    printf '%s dev %s\n' "$cidr" "$iface" >> "$STATE/routes.tmp"
    mv "$STATE/routes.tmp" "$STATE/routes"
    ;;
  "-4 route del table 20110 "*)
    cidr=$6
    awk -v c="$cidr" '$1 != c' "$STATE/routes" 2>/dev/null > "$STATE/routes.tmp" || true
    mv "$STATE/routes.tmp" "$STATE/routes"
    ;;
  *)
    echo "unexpected mock ip invocation: $ARGS" >&2
    exit 1
    ;;
esac
MOCK
chmod +x "$MOCK"/*

export PATH="$MOCK:/usr/bin:/bin"
export TEST_STATE="$STATE"
export MODDIR="$MOD"

# shellcheck disable=SC1090
. "$MOD/common.sh"
CLI="$MOCK/easytier-cli"
core_running() { return 0; }

# The bundled placeholder must fail loudly instead of starting an empty network.
! validate_runtime_config
cat > "$MOD/config/config.toml" <<'CONFIG'
instance_name = "test"
ipv4 = "10.0.0.20/24"
dhcp = false
rpc_portal = "127.0.0.1:15888"
[network_identity]
network_name = "test-network"
network_secret = ""
[flags]
dev_name = "tiernest0"
CONFIG
validate_runtime_config
sync_route_guard
sync_count_before=$(read_counter "$ROUTE_SYNC_COUNT_FILE")
sync_route_guard
[[ "$(read_counter "$ROUTE_SYNC_COUNT_FILE")" = "$sync_count_before" ]]
grep -q '198.18.0.2/32 dev rmnet_data4' "$STATE/routes"

grep -q '^9980: from all lookup 20110$' "$STATE/rules"
grep -q '10.0.0.0/24 dev tiernest0' "$STATE/routes"
grep -q '10.10.0.0/16 dev tiernest0' "$STATE/routes"
grep -q '172.16.0.0/16 dev tiernest0' "$STATE/routes"
grep -q '192.168.50.0/24 dev wlan0' "$STATE/routes"
if grep -q '192.168.50.0/24 dev tiernest0' "$STATE/routes"; then
  echo "home LAN overlap must prefer wlan0" >&2
  exit 1
fi
# Leaving home removes the physical subnet and restores the cached EasyTier proxy route.
touch "$STATE/lan_down"
sync_route_guard
grep -q '192.168.50.0/24 dev tiernest0' "$STATE/routes"
# Returning home switches the same destination back to the physical Wi-Fi interface.
rm "$STATE/lan_down"
sync_route_guard
grep -q '192.168.50.0/24 dev wlan0' "$STATE/routes"
if grep -q '192.168.50.0/24 dev tiernest0' "$STATE/routes"; then
  echo "returning home did not restore direct LAN preference" >&2
  exit 1
fi
# Simulate Android/VPN deleting only the proxy route while leaving the overlay route.
grep -v '172.16.0.0/16' "$STATE/routes" > "$STATE/routes.tmp"
mv "$STATE/routes.tmp" "$STATE/routes"
sync_route_guard
grep -q '172.16.0.0/16 dev tiernest0' "$STATE/routes"
if grep -q '0.0.0.0/0' "$STATE/routes"; then
  echo "exit-node route should be filtered by default" >&2
  exit 1
fi

# A hotspot iif rule must not be mistaken for the global TierNest policy rule.
printf '9970: from all iif ap0 lookup 20110
' >> "$STATE/rules"
grep -v '^9980:' "$STATE/rules" > "$STATE/rules.tmp"
mv "$STATE/rules.tmp" "$STATE/rules"
rm "$RULE_PREF_FILE" 2>/dev/null || true
sync_route_guard
grep -q '^9980: from all lookup 20110$' "$STATE/rules"
grep -v '^9970:' "$STATE/rules" > "$STATE/rules.tmp"
mv "$STATE/rules.tmp" "$STATE/rules"

cleanup_route_guard
[[ ! -s "$STATE/rules" ]]
[[ ! -s "$STATE/routes" ]]

# Android's IP-in-IP interface tunl0 must never be mistaken for an EasyTier TUN.
cat > "$MOD/config/config.toml" <<'CONFIG'
dhcp = true
[network_identity]
network_name = "test-network"
network_secret = ""
[flags]
dev_name = ""
CONFIG
[[ "$(find_tun_device)" == "tun2" ]]

echo "Route guard mock test passed."

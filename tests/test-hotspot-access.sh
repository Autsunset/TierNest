#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
STATE="$TMP/state"
SYSROOT="$TMP/sysctl"
mkdir -p "$MOD/config" "$MOD/run" "$MOD/logs" "$MOD/bin" "$MOCK" "$STATE" "$SYSROOT/net/ipv4"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/hotspot.sh" "$MOD/hotspot.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
: > "$MOD/bin/easytier-core"
: > "$MOD/bin/easytier-cli"
chmod +x "$MOD/bin/easytier-core" "$MOD/bin/easytier-cli"
printf 'instance_name = "test"\nipv4 = "10.42.0.10/24"\n[network_identity]\nnetwork_name = "test"\nnetwork_secret = "secret"\n[flags]\ndev_name = "tiernest0"\n' > "$MOD/config/config.toml"
echo 1 > "$SYSROOT/net/ipv4/ip_forward"
printf '10000: from all lookup main\n' > "$STATE/ip-rules"
: > "$STATE/iptables-rules"

cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}
case "$*" in
  "-o -4 addr show")
    echo '31: ap0    inet 192.168.43.1/24 scope global ap0'
    ;;
  "-o -4 addr show dev ap0")
    echo '31: ap0    inet 192.168.43.1/24 scope global ap0'
    ;;
  "link show dev ap0")
    echo '31: ap0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP'
    ;;
  "-4 route show table all default")
    echo 'default via 10.0.0.1 dev rmnet_data0'
    ;;
  "-4 route show table 20110")
    echo '10.42.0.0/24 dev tiernest0'
    echo '192.168.50.0/24 dev tiernest0'
    echo '172.16.50.0/24 dev wlan0'
    ;;
  "-4 rule show")
    cat "$STATE/ip-rules"
    ;;
  -4\ rule\ add\ pref\ *)
    shift 4
    pref=$1
    shift
    echo "$pref: from all $*" >> "$STATE/ip-rules"
    ;;
  -4\ rule\ del\ pref\ *)
    shift 4
    pref=$1
    awk -v p="$pref:" '$1 != p' "$STATE/ip-rules" > "$STATE/ip-rules.tmp"
    mv "$STATE/ip-rules.tmp" "$STATE/ip-rules"
    ;;
  "neigh show dev ap0")
    echo '192.168.43.2 lladdr 02:00:00:00:00:02 REACHABLE'
    echo '192.168.43.3 lladdr 02:00:00:00:00:03 STALE'
    ;;
  *) exit 0 ;;
esac
MOCK

cat > "$MOCK/iptables" <<'MOCK'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}
[ "${1:-}" = -w ] && shift 2
table=filter
if [ "${1:-}" = -t ]; then table=$2; shift 2; fi
op=${1:-}; chain=${2:-}; shift 2 || true
if [ "$op" = -I ] && [ "${1:-}" = 1 ]; then shift; fi
key="$table|$chain|$*"
case "$op" in
  -C) grep -Fqx "$key" "$STATE/iptables-rules" ;;
  -A|-I)
    grep -Fqx "$key" "$STATE/iptables-rules" 2>/dev/null || echo "$key" >> "$STATE/iptables-rules"
    ;;
  -D)
    grep -Fvx "$key" "$STATE/iptables-rules" > "$STATE/iptables-rules.tmp" || true
    mv "$STATE/iptables-rules.tmp" "$STATE/iptables-rules"
    ;;
  -F)
    awk -F'|' -v t="$table" -v c="$chain" '!( $1 == t && $2 == c )' "$STATE/iptables-rules" > "$STATE/iptables-rules.tmp"
    mv "$STATE/iptables-rules.tmp" "$STATE/iptables-rules"
    ;;
  -N|-X) exit 0 ;;
  -S) grep -F "${table}|${chain}|" "$STATE/iptables-rules" || true ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK"/*

export PATH="$MOCK:/usr/bin:/bin" TEST_STATE="$STATE" MODDIR="$MOD" TIERNEST_SYSCTL_ROOT="$SYSROOT"
# shellcheck disable=SC1090
. "$MOD/common.sh"
# shellcheck disable=SC1090
. "$MOD/hotspot.sh"

core_running() { return 0; }
find_tun_device() { echo tiernest0; }
policy_lookup_table() { echo 20110; }
build_desired_routes() {
    cat > "$2" <<'ROUTES'
0.0.0.0/0
10.42.0.0/24
172.16.50.0/24
192.168.50.0/24
ROUTES
}

echo on > "$HOTSPOT_ACCESS_OVERRIDE_FILE"
sync_hotspot_access

# Only active EasyTier routes through tiernest0 are accepted. The default route
# and a physical wlan0 route must never become hotspot forwarding targets.
grep -qx '10.42.0.0/24' "$HOTSPOT_ACCESS_TARGETS_FILE"
grep -qx '192.168.50.0/24' "$HOTSPOT_ACCESS_TARGETS_FILE"
! grep -q '0.0.0.0/0' "$HOTSPOT_ACCESS_TARGETS_FILE"
! grep -q '172.16.50.0/24' "$HOTSPOT_ACCESS_TARGETS_FILE"

# Parent hooks are interface-scoped, not global unqualified jumps.
grep -Fqx 'nat|POSTROUTING|-s 192.168.43.0/24 -o tiernest0 -j TN_HS_OUT_NAT' "$STATE/iptables-rules"
grep -Fqx 'filter|FORWARD|-i ap0 -o tiernest0 -j TN_HS_OUT_FWD' "$STATE/iptables-rules"
grep -Fqx 'filter|FORWARD|-i tiernest0 -o ap0 -j TN_HS_OUT_FWD' "$STATE/iptables-rules"
! grep -Fqx 'nat|POSTROUTING|-j TN_HS_OUT_NAT' "$STATE/iptables-rules"

# NAT and forward accepts are destination-specific. Inbound NEW traffic is
# explicitly dropped after established replies are accepted.
grep -Fqx 'nat|TN_HS_OUT_NAT|-s 192.168.43.0/24 -d 10.42.0.0/24 -o tiernest0 -j MASQUERADE' "$STATE/iptables-rules"
grep -Fqx 'filter|TN_HS_OUT_FWD|-i ap0 -o tiernest0 -s 192.168.43.0/24 -d 192.168.50.0/24 -j ACCEPT' "$STATE/iptables-rules"
grep -Eq '^filter\|TN_HS_OUT_FWD\|-i tiernest0 -o ap0 -d 192\.168\.43\.0/24 -m (conntrack --ctstate|state --state) ESTABLISHED,RELATED -j ACCEPT$' "$STATE/iptables-rules"
grep -Fqx 'filter|TN_HS_OUT_FWD|-i tiernest0 -o ap0 -d 192.168.43.0/24 -j DROP' "$STATE/iptables-rules"

grep -q 'iif ap0 to 10.42.0.0/24 lookup 20110' "$STATE/ip-rules"
grep -q 'iif ap0 to 192.168.50.0/24 lookup 20110' "$STATE/ip-rules"
status=$(print_hotspot_access_status)
grep -q '^active=1$' <<<"$status"
grep -q '^client_count=2$' <<<"$status"
grep -q '^advertises_hotspot_subnet=0$' <<<"$status"
grep -q '^inbound_policy=established-related-only;drop-new$' <<<"$status"

# Deleting one managed rule triggers an idempotent repair without touching the
# unrelated Android rule.
awk '!/10.42.0.0\/24 -o tiernest0 -j MASQUERADE/' "$STATE/iptables-rules" > "$STATE/iptables-rules.tmp"
mv "$STATE/iptables-rules.tmp" "$STATE/iptables-rules"
sync_hotspot_access
grep -Fqx 'nat|TN_HS_OUT_NAT|-s 192.168.43.0/24 -d 10.42.0.0/24 -o tiernest0 -j MASQUERADE' "$STATE/iptables-rules"
grep -q '^10000: from all lookup main$' "$STATE/ip-rules"
[[ "$(cat "$HOTSPOT_ACCESS_REAPPLY_COUNT_FILE")" = 2 ]]

# Disabling removes only TierNest-owned hooks/rules and keeps the preference.
echo off > "$HOTSPOT_ACCESS_OVERRIDE_FILE"
sync_hotspot_access
! grep -q 'TN_HS_OUT_' "$STATE/iptables-rules"
! grep -q 'iif ap0' "$STATE/ip-rules"
grep -q '^10000: from all lookup main$' "$STATE/ip-rules"
[[ "$(cat "$HOTSPOT_ACCESS_OVERRIDE_FILE")" = off ]]

# Privacy guard: advertising the hotspot CIDR via proxy_networks blocks this
# mode instead of silently making hotspot clients reachable from EasyTier.
cat > "$CONFIG_FILE" <<'CONFIG'
instance_name = "test"
ipv4 = "10.42.0.10/24"
proxy_networks = ["192.168.43.0/24"]
[network_identity]
network_name = "test"
network_secret = "secret"
[flags]
dev_name = "tiernest0"
CONFIG
echo on > "$HOTSPOT_ACCESS_OVERRIDE_FILE"
sync_hotspot_access || true
status=$(print_hotspot_access_status)
grep -q '^active=0$' <<<"$status"
grep -q '^status=subnet-advertised$' <<<"$status"
! grep -q 'TN_HS_OUT_' "$STATE/iptables-rules"

# Global forwarding is observed but never changed by TierNest.
printf 'instance_name = "test"\nipv4 = "10.42.0.10/24"\n[network_identity]\nnetwork_name = "test"\nnetwork_secret = "secret"\n[flags]\ndev_name = "tiernest0"\n' > "$CONFIG_FILE"
echo 0 > "$SYSROOT/net/ipv4/ip_forward"
sync_hotspot_access || true
status=$(print_hotspot_access_status)
grep -q '^status=ip-forward-disabled$' <<<"$status"
[[ "$(cat "$SYSROOT/net/ipv4/ip_forward")" = 0 ]]

# Auto-detection deliberately rejects generic wlan interfaces to avoid treating
# a normal Wi-Fi uplink as a hotspot.
hotspot_access_interface_allowed wlan0 && { echo 'wlan0 was incorrectly accepted as hotspot' >&2; exit 1; }
hotspot_access_interface_allowed ap0

echo 'Outbound-only hotspot access test passed.'

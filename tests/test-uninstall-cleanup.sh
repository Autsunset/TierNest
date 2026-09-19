#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/modules/tiernest"
OLD="$TMP/modules/easytier_magisk"
MOCK="$TMP/mockbin"
STATE="$TMP/state"
SYSROOT="$TMP/sysctl"
mkdir -p "$MOD/config" "$MOD/run" "$MOD/logs" "$MOD/bin" "$OLD" "$MOCK" "$STATE" \
  "$SYSROOT/net/ipv4/conf/ap0" "$SYSROOT/net/ipv4/conf/tiernest0"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/hotspot.sh" "$MOD/hotspot.sh"
cp "$ROOT/module/tun_firewall.sh" "$MOD/tun_firewall.sh"
cp "$ROOT/module/uninstall.sh" "$MOD/uninstall.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cp "$ROOT/module/config/config.toml" "$MOD/config/config.toml"
: > "$MOD/bin/easytier-core"; chmod +x "$MOD/bin/easytier-core" "$MOD/uninstall.sh"
printf '9980: from all lookup 20110\n9970: from all iif ap0 lookup 20110\n' > "$STATE/rules"
printf '10.42.0.0/24 dev tiernest0\n192.168.50.0/24 dev tiernest0\n' > "$STATE/routes"
for f in nat_jump fwd_jump nat_rule fwd_out fwd_in; do : > "$STATE/$f"; done
cat > "$MOD/run/hotspot-state" <<'STATEFILE'
ap0|192.168.43.0/24|192.168.43.1|tiernest0
STATEFILE
echo 9970 > "$MOD/run/hotspot-rule-pref"
mkdir -p "$MOD/run/tiernestd.lock" "$MOD/run/network-watch.lock" "$MOD/run/start.lock"
echo 999999 > "$MOD/run/tiernestd.pid"
echo 999998 > "$MOD/run/network-watch.pid"
echo 999997 > "$MOD/run/easytier.pid"
printf 'snapshot\n' > "$MOD/run/transport-endpoints.txt"
printf 'signature\n' > "$MOD/run/transport-endpoints.signature"
printf 'event\n' > "$MOD/run/last-recovery-event"
printf '192.168.50.0/24|wlan0\n' > "$MOD/run/local-route-overrides.txt"
printf '192.168.50.0/24|wlan0\n' > "$MOD/run/routes.expected-specs"
printf 'wlan0|192.168.50.0/24|tiernest0\n' > "$MOD/run/android-route-specs.txt"
printf 'wlan0\n' > "$MOD/run/android-route-tables.txt"
echo 1 > "$SYSROOT/net/ipv4/ip_forward"
echo 0 > "$MOD/run/hotspot-ip-forward-prev"
touch "$STATE/ap_down"
echo 0 > "$SYSROOT/net/ipv4/conf/ap0/rp_filter"
echo 0 > "$SYSROOT/net/ipv4/conf/tiernest0/rp_filter"
printf 'net/ipv4/conf/ap0/rp_filter|2\nnet/ipv4/conf/tiernest0/rp_filter|1\n' > "$MOD/run/hotspot-sysctl-state"
touch "$OLD/disable" "$OLD/.disabled-by-tiernest"

cat > "$MOCK/pgrep" <<'MOCK'
#!/bin/sh
exit 1
MOCK
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}
case "$*" in
  "-4 rule show") cat "$STATE/rules" ;;
  "-4 rule del pref "*) pref=${5}; awk -v p="$pref" '$1 != p ":"' "$STATE/rules" > "$STATE/rules.tmp"; mv "$STATE/rules.tmp" "$STATE/rules" ;;
  "-4 route flush table 20110") : > "$STATE/routes" ;;
  "link show dev ap0") if [ -f "$STATE/ap_down" ]; then echo '33: ap0: <BROADCAST,MULTICAST> mtu 1500'; else echo '33: ap0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500'; fi ;;
  "-o -4 addr show dev ap0") [ -f "$STATE/ap_down" ] || echo '33: ap0 inet 192.168.43.1/24 scope global ap0' ;;
  "-o -4 addr show") exit 0 ;;
  "-4 route show table all default") exit 0 ;;
  *) exit 0 ;;
esac
MOCK
cat > "$MOCK/iptables" <<'MOCK'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}
[ "${1:-}" = "-w" ] && { shift 2; }
args="$*"
flag() { [ -f "$STATE/$1" ]; }
clearflag() { rm "$STATE/$1" 2>/dev/null || true; }
case "$args" in
  "-t nat -C POSTROUTING -j TN_HS_NAT") flag nat_jump ;;
  "-C FORWARD -j TN_HS_FWD") flag fwd_jump ;;
  "-t nat -C TN_HS_NAT "*) flag nat_rule ;;
  "-C TN_HS_FWD -i ap0 -o tiernest0 -j ACCEPT") flag fwd_out ;;
  "-C TN_HS_FWD -i tiernest0 -o ap0 "*) flag fwd_in ;;
  "-t nat -D POSTROUTING -j TN_HS_NAT") clearflag nat_jump ;;
  "-D FORWARD -j TN_HS_FWD") clearflag fwd_jump ;;
  "-t nat -F TN_HS_NAT") clearflag nat_rule ;;
  "-F TN_HS_FWD") clearflag fwd_out; clearflag fwd_in ;;
  "-t nat -X TN_HS_NAT"|"-X TN_HS_FWD") exit 0 ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK"/*

PATH="$MOCK:/usr/bin:/bin" TEST_STATE="$STATE" TIERNEST_MODULES_ROOT="$TMP/modules" TIERNEST_SYSCTL_ROOT="$SYSROOT" \
  /bin/bash "$MOD/uninstall.sh"

[[ ! -s "$STATE/rules" ]]
[[ ! -s "$STATE/routes" ]]
for f in nat_jump fwd_jump nat_rule fwd_out fwd_in; do [[ ! -e "$STATE/$f" ]]; done
[[ "$(cat "$SYSROOT/net/ipv4/conf/ap0/rp_filter")" = 2 ]]
[[ "$(cat "$SYSROOT/net/ipv4/conf/tiernest0/rp_filter")" = 1 ]]
[[ "$(cat "$SYSROOT/net/ipv4/ip_forward")" = 0 ]]
[[ ! -e "$MOD/run/hotspot-ip-forward-prev" ]]
[[ ! -e "$OLD/disable" ]]
[[ ! -e "$OLD/.disabled-by-tiernest" ]]
[[ ! -e "$MOD/run/tiernestd.pid" ]]
[[ ! -e "$MOD/run/network-watch.pid" ]]
[[ ! -e "$MOD/run/tiernestd.lock" ]]
[[ ! -e "$MOD/run/network-watch.lock" ]]
[[ ! -e "$MOD/run/start.lock" ]]
[[ ! -e "$MOD/run/transport-endpoints.txt" ]]
[[ ! -e "$MOD/run/transport-endpoints.signature" ]]
[[ ! -e "$MOD/run/last-recovery-event" ]]
[[ ! -e "$MOD/run/local-route-overrides.txt" ]]
[[ ! -e "$MOD/run/routes.expected-specs" ]]
[[ ! -e "$MOD/run/android-route-specs.txt" ]]
[[ ! -e "$MOD/run/android-route-tables.txt" ]]

echo 'Uninstall cleanup test passed.'

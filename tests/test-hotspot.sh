#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d); trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"; MOCK="$TMP/mockbin"; STATE="$TMP/state"; SYSROOT="$TMP/sysctl"
mkdir -p "$MOD/config" "$MOD/run" "$MOD/logs" "$MOCK" "$STATE" "$SYSROOT/net/ipv4/conf/ap0" "$SYSROOT/net/ipv4/conf/tiernest0"
cp "$ROOT/module/common.sh" "$MOD/common.sh"; cp "$ROOT/module/hotspot.sh" "$MOD/hotspot.sh"; cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
echo 1 > "$SYSROOT/net/ipv4/ip_forward"; echo 0 > "$MOD/run/hotspot-ip-forward-prev"
echo 0 > "$SYSROOT/net/ipv4/conf/ap0/rp_filter"; echo 0 > "$SYSROOT/net/ipv4/conf/tiernest0/rp_filter"
printf 'net/ipv4/conf/ap0/rp_filter|2\nnet/ipv4/conf/tiernest0/rp_filter|1\n' > "$MOD/run/hotspot-sysctl-state"
printf '9970|ap0|10.42.0.0/24|20110\n9969|ap0|192.168.50.0/24|20110\n' > "$MOD/run/hotspot-rule-pref"
echo 'ap0|192.168.43.0/24|192.168.43.1|tiernest0' > "$MOD/run/hotspot-state"; echo on > "$MOD/config/hotspot-forwarding.state"
printf '9970: old\n9969: old\n' > "$STATE/rules"; touch "$STATE/nat_jump" "$STATE/fwd_jump" "$STATE/nat_chain" "$STATE/fwd_chain"
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
STATE=${TEST_STATE:?}
case "$*" in
 "-4 rule del pref 9970") grep -v '^9970:' "$STATE/rules" > "$STATE/rules.tmp"; mv "$STATE/rules.tmp" "$STATE/rules" ;;
 "-4 rule del pref 9969") grep -v '^9969:' "$STATE/rules" > "$STATE/rules.tmp"; mv "$STATE/rules.tmp" "$STATE/rules" ;;
 "-o -4 addr show dev ap0") exit 0 ;;
 *) exit 0 ;;
esac
MOCK
cat > "$MOCK/iptables" <<'MOCK'
#!/bin/sh
STATE=${TEST_STATE:?}; [ "${1:-}" = -w ] && shift 2
case "$*" in
 "-t nat -C POSTROUTING -j TN_HS_NAT") [ -f "$STATE/nat_jump" ] ;;
 "-C FORWARD -j TN_HS_FWD") [ -f "$STATE/fwd_jump" ] ;;
 "-t nat -D POSTROUTING -j TN_HS_NAT") rm "$STATE/nat_jump" ;;
 "-D FORWARD -j TN_HS_FWD") rm "$STATE/fwd_jump" ;;
 "-t nat -F TN_HS_NAT"|"-t nat -X TN_HS_NAT") rm "$STATE/nat_chain" 2>/dev/null || true ;;
 "-F TN_HS_FWD"|"-X TN_HS_FWD") rm "$STATE/fwd_chain" 2>/dev/null || true ;;
 *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK"/*
export PATH="$MOCK:/usr/bin:/bin" TEST_STATE="$STATE" MODDIR="$MOD" TIERNEST_SYSCTL_ROOT="$SYSROOT"
. "$MOD/common.sh"; . "$MOD/hotspot.sh"
legacy_hotspot_artifacts_present
cleanup_hotspot_forwarding
[[ ! -s "$STATE/rules" ]]
[[ ! -e "$STATE/nat_jump" && ! -e "$STATE/fwd_jump" ]]
[[ "$(cat "$SYSROOT/net/ipv4/ip_forward")" = 0 ]]
[[ "$(cat "$SYSROOT/net/ipv4/conf/ap0/rp_filter")" = 2 ]]
[[ "$(cat "$SYSROOT/net/ipv4/conf/tiernest0/rp_filter")" = 1 ]]
! legacy_hotspot_artifacts_present
echo 'Legacy hotspot cleanup test passed.'

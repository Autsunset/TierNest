#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d); trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"; MOCK="$TMP/mockbin"; STATE="$TMP/state"
mkdir -p "$MOD/config" "$MOD/run" "$MOD/logs" "$MOD/bin" "$MOCK" "$STATE"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/hotspot.sh" "$MOD/hotspot.sh"
cp "$ROOT/module/tun_firewall.sh" "$MOD/tun_firewall.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
printf 'ipv4 = "10.42.0.10/24"\n[network_identity]\nnetwork_name="test"\nnetwork_secret="secret"\n[flags]\ndev_name="tiernest0"\n' > "$MOD/config/config.toml"
: > "$STATE/rules"
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
case "$*" in "-4 route show table 20110") exit 0;; *) exit 0;; esac
MOCK
cat > "$MOCK/iptables" <<'MOCK'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}; [ "${1:-}" = -w ] && shift 2
table=filter
if [ "${1:-}" = -t ]; then table=$2; shift 2; fi
op=${1:-}; chain=${2:-}; shift 2 || true
if [ "$op" = -I ] && [ "${1:-}" = 1 ]; then shift; fi
key="$table|$chain|$*"
case "$op" in
 -C) grep -Fqx "$key" "$STATE/rules" ;;
 -A|-I) grep -Fqx "$key" "$STATE/rules" 2>/dev/null || echo "$key" >> "$STATE/rules" ;;
 -D) grep -Fvx "$key" "$STATE/rules" > "$STATE/rules.tmp" || true; mv "$STATE/rules.tmp" "$STATE/rules" ;;
 -F) awk -F'|' -v t="$table" -v c="$chain" '!( $1==t && $2==c )' "$STATE/rules" > "$STATE/rules.tmp"; mv "$STATE/rules.tmp" "$STATE/rules" ;;
 -N|-X) exit 0 ;;
 -L) grep -F "${table}|${chain}|" "$STATE/rules" || true ;;
 *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK"/*
export PATH="$MOCK:/usr/bin:/bin" TEST_STATE="$STATE" MODDIR="$MOD"
. "$MOD/common.sh"
. "$MOD/hotspot.sh"
. "$MOD/tun_firewall.sh"
core_running() { return 0; }
find_tun_device() { echo tiernest0; }
build_desired_routes() { printf '0.0.0.0/0\n10.42.0.0/24\n192.168.50.0/24\n' > "$2"; }
TUN_FIREWALL_GUARD=1
sync_tun_firewall_guard

grep -Fqx 'filter|INPUT|-i tiernest0 -j TN_ET_INPUT' "$STATE/rules"
grep -Fqx 'filter|OUTPUT|-o tiernest0 -j TN_ET_OUTPUT' "$STATE/rules"
grep -Fqx 'filter|TN_ET_INPUT|-i tiernest0 -s 10.42.0.0/24 -j ACCEPT' "$STATE/rules"
grep -Fqx 'filter|TN_ET_INPUT|-i tiernest0 -s 192.168.50.0/24 -j ACCEPT' "$STATE/rules"
grep -Fqx 'filter|TN_ET_OUTPUT|-o tiernest0 -d 192.168.50.0/24 -j ACCEPT' "$STATE/rules"
! grep -q '0.0.0.0/0' "$STATE/rules"
status=$(print_tun_firewall_status)
grep -q '^active=1$' <<<"$status"
grep -q '^target_count=2$' <<<"$status"

# Reconcile a deleted child rule.
grep -Fv 'TN_ET_OUTPUT|-o tiernest0 -d 192.168.50.0/24' "$STATE/rules" > "$STATE/rules.tmp"; mv "$STATE/rules.tmp" "$STATE/rules"
sync_tun_firewall_guard
grep -Fqx 'filter|TN_ET_OUTPUT|-o tiernest0 -d 192.168.50.0/24 -j ACCEPT' "$STATE/rules"

TUN_FIREWALL_GUARD=0
sync_tun_firewall_guard
! grep -q 'TN_ET_' "$STATE/rules"
echo 'TUN firewall guard test passed.'

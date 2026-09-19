#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"; MOCK="$TMP/mockbin"; STATE="$TMP/state"
mkdir -p "$MOD/config" "$MOD/bin" "$MOD/logs" "$MOD/run" "$MOCK" "$STATE"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cat > "$MOD/config/config.toml" <<'CONFIG'
hostname = "Example-Phone-B"
ipv4 = "10.42.0.52/24"
rpc_portal = "127.0.0.1:15888"
[network_identity]
network_name = "test"
network_secret = "secret"
[flags]
dev_name = "tiernest0"
CONFIG
: > "$MOD/bin/easytier-core"; chmod +x "$MOD/bin/easytier-core"
cat > "$MOCK/getprop" <<'MOCKPROP'
#!/bin/sh
case "$1" in
 ro.product.manufacturer) echo Xiaomi ;;
 ro.product.brand) echo Xiaomi ;;
 ro.product.model) echo Mi10 ;;
 ro.build.version.sdk) echo 33 ;;
esac
MOCKPROP
cat > "$MOCK/easytier-cli" <<'MOCKCLI'
#!/bin/sh
printf '[{"ipv4":"10.42.0.1/24","proxy_cidrs":"192.168.50.0/24"}]\n'
MOCKCLI
cat > "$MOCK/ip" <<'MOCKIP'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}; ARGS="$*"
case "$ARGS" in
 "-4 route show table 20110") cat "$STATE/table20110" 2>/dev/null || true ;;
 "-4 route show table 110") exit 0 ;;
 "-4 route show table main dev tiernest0") printf '10.42.0.0/24 dev tiernest0\n192.168.50.0/24 dev tiernest0\n' ;;
 "-4 rule show") cat "$STATE/rules" 2>/dev/null || true ;;
 "-4 rule add from all lookup main") printf '30000: from all lookup main\n' >> "$STATE/rules" ;;
 "-4 rule add pref "*" to "*" lookup main")
   set -- $ARGS; pref=$5; cidr=$7
   printf '%s: from all to %s lookup main\n' "$pref" "$cidr" >> "$STATE/rules"
   ;;
 "-4 rule del pref "*)
   set -- $ARGS; pref=$5
   awk -v p="$pref" '$1 != p ":"' "$STATE/rules" > "$STATE/rules.tmp" || true
   mv "$STATE/rules.tmp" "$STATE/rules"
   ;;
 "-4 route flush table "*) : ;;
 "link show dev tiernest0") exit 0 ;;
 "-o -4 addr show dev tiernest0") echo '14: tiernest0 inet 10.42.0.52/24 scope global tiernest0' ;;
 "-o -4 addr show")
   echo '10: wlan0 inet 192.168.0.104/24 scope global wlan0'
   echo '14: tiernest0 inet 10.42.0.52/24 scope global tiernest0'
   [ -f "$STATE/vpn" ] && echo '20: tun9 inet 10.8.0.2/32 scope global tun9'
   ;;
 "-o link show") echo '14: tiernest0: <UP>' ;;
 *) exit 0 ;;
esac
MOCKIP
chmod +x "$MOCK"/*
: > "$STATE/rules"; : > "$STATE/table20110"
export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" TEST_STATE="$STATE"
. "$MOD/common.sh"
CLI="$MOCK/easytier-cli"
core_running() { return 0; }
find_tun_device() { echo tiernest0; }

sync_route_guard
[[ "$(cat "$ROUTE_MODE_ACTIVE_FILE")" = upstream ]]
grep -q 'from all lookup main' "$STATE/rules"
[[ "$(policy_lookup_table)" = main ]]
if grep -q 'lookup 20110' "$STATE/rules"; then echo 'Xiaomi upstream mode unexpectedly added dedicated rule' >&2; exit 1; fi

# netd/Clash may delete the official rule while the core remains alive; periodic sync repairs it.
: > "$STATE/rules"
sync_route_guard
grep -q 'from all lookup main' "$STATE/rules"

# A VPN change alone keeps the least-invasive upstream mode. A failed route probe can then
# promote the mode to destination-specific main rules without restarting blindly.
touch "$STATE/vpn"
rm "$ROUTE_MODE_RUNTIME_OVERRIDE_FILE" 2>/dev/null || true
sync_route_guard
[[ "$(cat "$ROUTE_MODE_ACTIVE_FILE")" = upstream ]]
echo 0 > "$ROUTE_MODE_LAST_SWITCH_FILE"
try_alternate_route_mode
[[ "$(cat "$ROUTE_MODE_ACTIVE_FILE")" = target-main ]]
grep -q 'to 10.42.0.0/24 lookup main' "$STATE/rules"
grep -q 'to 192.168.50.0/24 lookup main' "$STATE/rules"
if grep -q '^[0-9]*: from all lookup main$' "$STATE/rules"; then echo 'broad main rule remained after route-mode fallback' >&2; exit 1; fi
cleanup_route_guard
[[ ! -s "$STATE/rules" ]]

echo 'Automatic route mode test passed.'

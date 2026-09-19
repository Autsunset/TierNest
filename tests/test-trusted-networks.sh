#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
export MODDIR="$TMP/module" TIERNEST_SYS_NET_ROOT="$TMP/net"
mkdir -p "$MODDIR/config" "$TMP/net/wlan0"
. "$ROOT/module/common.sh"
. "$ROOT/module/service_api.sh"
echo 1 > "$TMP/net/wlan0/carrier"
mock_gateway=192.168.80.1; mock_mac=02:01:02:03:04:05; mock_probe=0
ip() {
    case "$*" in
        '-o -4 addr show') echo '12: wlan0 inet 192.168.80.10/24 scope global wlan0';;
        '-4 route get 10.80.0.1 oif wlan0') echo "10.80.0.1 via $mock_gateway dev wlan0 table wlan0";;
        'neigh show to '* ) [[ "$4" != "$mock_gateway" ]] || echo "$mock_gateway dev wlan0 lladdr $mock_mac REACHABLE";;
    esac
    return 0
}
curl() { [[ "$*" == *'--interface wlan0 --noproxy *'* ]]; return "$mock_probe"; }
log_msg() { echo "$*" >> "$TMP/events"; }
set_description() { :; }
stop_script_tree() { rm -f "$1"; }
cleanup_hotspot_access() { :; }
cleanup_tun_firewall_guard() { :; }
legacy_hotspot_artifacts_present() { return 1; }
cleanup_route_guard() { :; }
stop_core() { rm -f "$TMP/core"; }
core_running() { [[ -f "$TMP/core" ]]; }
start_normal_workers() { workers_blocked && return 1; touch "$TMP/core"; }
ensure_daemon_running() { workers_blocked || touch "$TMP/core"; }
ensure_home_watch_running() { service_user_blocked || echo 123 > "$HOME_WATCH_PID_FILE"; }

# Existing v1.0.4 records are read without a migration write or loss of settings.
printf 'interface=wlan0\ngateway=192.168.80.1\nmac=02:01:02:03:04:05\ntarget=10.80.0.1\nport=80\n' > "$HOME_NETWORK_FILE"
cp "$HOME_NETWORK_FILE" "$TMP/legacy"
home_settings_valid
first_id=$(home_network_check)
[[ "$first_id" = wlan0-192.168.80.1-020102030405 ]]
cmp "$TMP/legacy" "$HOME_NETWORK_FILE"

# Add a portable router, preserving the previous router. Re-learning updates one.
mock_gateway=192.168.0.1; mock_mac=02:06:07:08:09:0a
home_learn_unlocked 10.80.0.1 80 >/dev/null
second_id=$(home_network_check)
[[ "$second_id" = wlan0-192.168.0.1-02060708090a ]]
[[ "$(home_network_records | wc -l)" = 2 ]]
home_learn_unlocked 10.80.0.1 8080 >/dev/null
[[ "$(home_network_records | wc -l)" = 2 ]]
home_network_records | grep -q '^wlan0|192.168.80.1|02:01:02:03:04:05|10.80.0.1|80$'
home_network_records | grep -q '^wlan0|192.168.0.1|02:06:07:08:09:0a|10.80.0.1|8080$'
print_supervision_status > "$TMP/status"
grep -q '^home_network_count=2$' "$TMP/status"
sed -n 's/^home_networks_b64=//p' "$TMP/status" | base64 -d > "$TMP/rows"
cmp "$TMP/rows" <(home_network_records)
cp "$HOME_NETWORK_FILE" "$TMP/two-records"
mock_probe=1
! home_learn_unlocked 10.80.0.1 80 2>/dev/null
cmp "$TMP/two-records" "$HOME_NETWORK_FILE"
mock_probe=0

service_with_lock set_service_mode_unlocked auto
[[ "$(cat "$HOME_PAUSED_FILE")" = "$second_id" && ! -f "$TMP/core" ]]
mock_gateway=192.168.80.1; mock_mac=02:01:02:03:04:05
before=$(wc -l < "$TMP/events")
auto_reconcile_unlocked
[[ "$(cat "$HOME_PAUSED_FILE")" = "$first_id" && ! -f "$TMP/core" ]]
[[ "$(wc -l < "$TMP/events")" = "$before" ]] # Valid router handoff keeps core paused.

# A known but broken NEW router must not inherit another router's grace period.
mock_gateway=192.168.0.1; mock_mac=02:06:07:08:09:0a; mock_probe=1
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]]
mock_probe=0
auto_reconcile_unlocked
mock_probe=1
auto_reconcile_unlocked
[[ -f "$HOME_PAUSED_FILE" && ! -f "$TMP/core" ]]
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]]
mock_probe=0
auto_reconcile_unlocked
mock_mac=02:ff:ff:ff:ff:ff
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]] # Same gateway IP alone is insufficient.

# Delete inactive/active records and preserve the explicit manual-stop override.
mock_gateway=192.168.80.1; mock_mac=02:01:02:03:04:05
auto_reconcile_unlocked
service_with_lock home_forget_unlocked "$second_id" >/dev/null
[[ -f "$HOME_PAUSED_FILE" && ! -f "$TMP/core" ]]
home_save_record wlan0 192.168.0.1 02:06:07:08:09:0a 10.80.0.1 80
service_with_lock home_forget_unlocked "$first_id" >/dev/null
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]]
stop_service
service_with_lock home_forget_unlocked "$second_id" >/dev/null
[[ "$(service_mode)" = manual && -f "$MANUAL_STOP_FILE" && ! -f "$TMP/core" && ! -f "$HOME_WATCH_PID_FILE" ]]
! home_settings_valid
! home_forget_unlocked "$second_id" 2>/dev/null
! home_forget_unlocked 'x;touch BAD' 2>/dev/null

home_save_record wlan0 192.168.80.1 02:01:02:03:04:05 10.80.0.1 80
start_service
service_with_lock set_service_mode_unlocked auto
[[ -f "$HOME_PAUSED_FILE" ]]
service_with_lock home_forget_unlocked "$first_id" >/dev/null
[[ "$(service_mode)" = manual && -f "$TMP/core" && ! -f "$HOME_PAUSED_FILE" && ! -f "$HOME_WATCH_PID_FILE" ]]
echo 'Trusted networks: legacy read, multiple routers, deduplication, handoff, failed proxy, delete and manual override passed.'

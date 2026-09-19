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
printf 'untouched\n' > "$CONFIG_FILE"
mock_gateway=192.168.80.1
mock_mac=02:01:02:03:04:05
mock_probe=0
ip() {
    case "$*" in
        '-o -4 addr show') echo '12: wlan0 inet 192.168.80.10/24 scope global wlan0';;
        '-4 route get 10.80.0.1 oif wlan0') echo "10.80.0.1 via $mock_gateway dev wlan0 table wlan0";;
        'neigh show to 192.168.80.1 dev wlan0') echo "192.168.80.1 dev wlan0 lladdr $mock_mac REACHABLE";;
    esac
}
curl() {
    [[ "$*" == *'--interface wlan0 --noproxy * --connect-timeout 2 --max-time 3'* ]]
    [[ "${*: -1}" = 'http://10.80.0.1:80/' ]]
    return "$mock_probe"
}
log_msg() { echo "$*" >> "$TMP/events"; }
set_description() { :; }
stop_script_tree() { echo "stop $2" >> "$TMP/events"; rm -f "$1"; }
cleanup_hotspot_access() { :; }
cleanup_tun_firewall_guard() { :; }
legacy_hotspot_artifacts_present() { return 1; }
cleanup_route_guard() { rm -f "$TMP/routes"; }
stop_core() { rm -f "$TMP/core"; }
core_running() { [[ -f "$TMP/core" ]]; }
start_normal_workers() { workers_blocked && return 1; touch "$TMP/core" "$TMP/routes"; }
ensure_daemon_running() { workers_blocked || touch "$TMP/core" "$TMP/routes"; }
ensure_home_watch_running() { service_user_blocked || echo 1000 > "$HOME_WATCH_PID_FILE"; }

[[ "$(service_mode)" = manual ]]
! set_service_mode_unlocked auto 2>/dev/null
home_learn_unlocked 10.80.0.1 80 >/dev/null
home_settings_valid
cp "$HOME_NETWORK_FILE" "$TMP/saved-home"
! home_learn_unlocked '10.80.0.1;touch BAD' 80 2>/dev/null
mock_probe=1
! home_learn_unlocked 10.80.0.1 80 2>/dev/null
cmp "$TMP/saved-home" "$HOME_NETWORK_FILE"
mock_probe=0

start_service
[[ -f "$TMP/core" ]]
service_with_lock set_service_mode_unlocked auto
[[ "$(service_mode)" = auto && -f "$HOME_PAUSED_FILE" && ! -f "$TMP/core" && ! -f "$TMP/routes" ]]
[[ -f "$HOME_WATCH_PID_FILE" ]]
before=$(wc -l < "$TMP/events")
auto_reconcile_unlocked
[[ "$(wc -l < "$TMP/events")" = "$before" ]] # No repeated cleanup or logs at home.

mock_probe=1
auto_reconcile_unlocked
[[ -f "$HOME_PAUSED_FILE" && ! -f "$TMP/core" ]]
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]] # Gateway overlay failed.
mock_probe=0
auto_reconcile_unlocked
[[ -f "$HOME_PAUSED_FILE" && ! -f "$TMP/core" ]]
mock_mac=02:09:09:09:09:09
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]] # Same IP, different router.
mock_mac=02:01:02:03:04:05
auto_reconcile_unlocked
echo 0 > "$TMP/net/wlan0/carrier"
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]]
echo 1 > "$TMP/net/wlan0/carrier"
auto_reconcile_unlocked

stop_service
[[ -f "$MANUAL_STOP_FILE" && ! -f "$HOME_PAUSED_FILE" && ! -f "$HOME_WATCH_PID_FILE" && ! -f "$TMP/core" ]]
before=$(wc -l < "$TMP/events")
auto_reconcile_unlocked
boot_service_unlocked
service_with_lock set_service_mode_unlocked manual
service_with_lock set_service_mode_unlocked auto
[[ -f "$MANUAL_STOP_FILE" && ! -f "$TMP/core" && ! -f "$HOME_WATCH_PID_FILE" ]]
[[ "$(cat "$CONFIG_FILE")" = untouched ]]
start_service
[[ -f "$HOME_PAUSED_FILE" && ! -f "$MANUAL_STOP_FILE" ]]
service_with_lock set_service_mode_unlocked manual
[[ ! -f "$HOME_PAUSED_FILE" && ! -f "$HOME_WATCH_PID_FILE" && -f "$TMP/core" ]]
stop_service
for flag in disable remove; do
    rm -f "$MANUAL_STOP_FILE"
    touch "$MODDIR/$flag"
    ! start_service 2>/dev/null
    boot_service_unlocked
    auto_reconcile_unlocked
    [[ ! -f "$TMP/core" && ! -f "$HOME_WATCH_PID_FILE" ]]
    rm -f "$MODDIR/$flag"
done

# Concurrent explicit operations serialize. Stop queued during startup leaves
# the persistent marker, and no later auto tick may resurrect the service.
delayed_start() { rm -f "$MANUAL_STOP_FILE"; touch "$TMP/starting"; sleep 2; touch "$TMP/core"; }
service_with_lock delayed_start &
starter=$!
for _ in $(seq 1 100); do [[ -f "$TMP/starting" ]] && break; sleep 0.05; done
stop_service
wait "$starter"
[[ -f "$MANUAL_STOP_FILE" && ! -f "$TMP/core" ]]
auto_reconcile_unlocked
[[ ! -f "$TMP/core" ]]
[[ ! -d "$RUNDIR/service.lock" ]]

# Real core entry guards must run before validation, exec, or lock acquisition.
for marker in "$MANUAL_STOP_FILE" "$HOME_PAUSED_FILE" "$MODDIR/disable" "$MODDIR/remove"; do
    touch "$marker"
    ! start_core
    [[ ! -d "$START_LOCK" ]]
    rm -f "$marker"
done
echo 'Service mode tests passed: home validation, fallback, manual override, reboot guard, mode inheritance and serialized start/stop.'

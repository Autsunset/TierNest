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
mock_mac=02:01:02:03:04:05
mock_probe=0
mock_supported=0
ip() {
    case "$*" in
        '-4 route get 10.80.0.1 oif wlan0') echo '10.80.0.1 via 192.168.80.1 dev wlan0';;
        'neigh show to 192.168.80.1 dev wlan0') echo "192.168.80.1 lladdr $mock_mac REACHABLE";;
    esac
}
home_probe() { echo probe >> "$TMP/probes"; return "$mock_probe"; }
home_event_supported() { return "$mock_supported"; }
stop_script_tree() { echo stop >> "$TMP/stops"; }
ensure_home_watch_running() { echo start >> "$TMP/starts"; }
stop_normal_workers() { rm -f "$TMP/core"; }
ensure_daemon_running() { touch "$TMP/core"; }
log_msg() { :; }
set_description() { :; }
[[ "$(home_detection_mode)" = poll && "$(home_check_interval)" = 30 ]]
for value in 0 -1 1.5 1e3 ';touch BAD' 2147483648 999999999999999999; do
    ! service_with_lock set_home_detection_unlocked poll "$value" 2>/dev/null
    [[ ! -f "$HOME_DETECTION_FILE" && ! -f "$TMP/stops" ]]
done
for value in 1 30 300 86400 2147483647; do
    service_with_lock set_home_detection_unlocked poll "$value" >/dev/null
    [[ "$(home_check_interval)" = "$value" ]]
done
cp "$HOME_DETECTION_FILE" "$TMP/previous"
mock_supported=1
! service_with_lock set_home_detection_unlocked event 300 2>/dev/null
cmp "$HOME_DETECTION_FILE" "$TMP/previous"
mock_supported=0

home_save_record wlan0 192.168.80.1 02:01:02:03:04:05 10.80.0.1 80
echo auto > "$SERVICE_MODE_FILE"
service_with_lock set_home_detection_unlocked event 300 >/dev/null
[[ -f "$HOME_PAUSED_FILE" && ! -f "$TMP/probes" ]]
mock_probe=1
auto_reconcile_unlocked
[[ -f "$HOME_PAUSED_FILE" && ! -f "$TMP/probes" ]] # Event mode never revalidates remote HTTP.
mock_mac=02:09:09:09:09:09
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]]
mock_mac=02:01:02:03:04:05
auto_reconcile_unlocked
[[ -f "$HOME_PAUSED_FILE" && ! -f "$TMP/core" ]]
echo 0 > "$TMP/net/wlan0/carrier"
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]]
echo 1 > "$TMP/net/wlan0/carrier"
mock_probe=0
service_with_lock set_home_detection_unlocked poll 7 >/dev/null
[[ -f "$TMP/probes" && -f "$HOME_PAUSED_FILE" && "$(home_check_interval)" = 7 ]]
mock_probe=1
auto_reconcile_unlocked
[[ -f "$HOME_PAUSED_FILE" ]]
auto_reconcile_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" ]]

touch "$MANUAL_STOP_FILE"
rm -f "$TMP/starts" "$TMP/core"
service_with_lock set_home_detection_unlocked event 9 >/dev/null
[[ -f "$MANUAL_STOP_FILE" && ! -f "$TMP/starts" && ! -f "$TMP/core" ]]
home_monitor_failed_unlocked
[[ ! -f "$TMP/core" ]]
rm -f "$MANUAL_STOP_FILE"
touch "$HOME_PAUSED_FILE"
home_monitor_failed_unlocked
[[ ! -f "$HOME_PAUSED_FILE" && -f "$TMP/core" && -s "$HOME_WATCH_ERROR_FILE" ]]

# Startup failures restore the exact previous preferences, including comments.
printf '# retained\nmode=poll\ninterval=42\n' > "$HOME_DETECTION_FILE"
cp "$HOME_DETECTION_FILE" "$TMP/previous"
ensure_home_watch_running() { [[ "$(home_detection_mode)" = poll ]]; }
! service_with_lock set_home_detection_unlocked event 60 2>/dev/null
cmp "$HOME_DETECTION_FILE" "$TMP/previous"
[[ "$(stat -c %a "$HOME_DETECTION_FILE")" = 600 ]]
print_supervision_status > "$TMP/status"
grep -q '^home_detection_mode=poll$' "$TMP/status"
grep -q '^home_check_interval=42$' "$TMP/status"
echo 'Automatic detection: defaults, interval bounds, event matching, polling recovery, stop priority and rollback passed.'

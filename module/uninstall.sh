#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/hotspot.sh"
. "$MODDIR/tun_firewall.sh"

process_matches() {
    pid=$1
    needle=$2
    [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] || return 1
    cmdline=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$cmdline" in *"$needle"*) return 0;; esac
    return 1
}

stop_managed_process() {
    pid=$1
    needle=$2
    timeout_seconds=${3:-12}
    process_matches "$pid" "$needle" || return 0
    kill "$pid" 2>/dev/null || true
    waited=0
    while process_matches "$pid" "$needle" && [ "$waited" -lt "$timeout_seconds" ]; do
        sleep 1
        waited=$((waited + 1))
    done
    process_matches "$pid" "$needle" && kill -9 "$pid" 2>/dev/null || true
}

# Prevent the daemon from re-creating routes or processes while uninstall cleanup runs.
touch "$MODDIR/remove" 2>/dev/null || true

stop_script_tree "$HOME_WATCH_PID_FILE" home_watch.sh || true
stop_script_tree "$NETWORK_WATCH_PID_FILE" network_watch.sh || true
stop_script_tree "$DAEMON_PID_FILE" tiernestd.sh || true
rm -f "$HOME_PAUSED_FILE" "$HOME_FAILURES_FILE" "$HOME_WATCH_READY_FILE" "$HOME_WATCH_ERROR_FILE"
rmdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null || true

daemon_pid=""
[ -r "$DAEMON_PID_FILE" ] && daemon_pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
stop_managed_process "$daemon_pid" "$MODDIR/tiernestd.sh" 15

watch_pid=""
[ -r "$NETWORK_WATCH_PID_FILE" ] && watch_pid=$(cat "$NETWORK_WATCH_PID_FILE" 2>/dev/null)
stop_managed_process "$watch_pid" "$MODDIR/network_watch.sh" 6

# Final idempotent cleanup after all writers are stopped.
rmdir "$TUN_FIREWALL_LOCK_DIR" 2>/dev/null || true
cleanup_hotspot_access
cleanup_tun_firewall_guard
cleanup_hotspot_forwarding
stop_core
cleanup_route_guard
restore_hotspot_sysctl_state
restore_hotspot_ip_forward_if_safe

rm "$DAEMON_PID_FILE" "$NETWORK_WATCH_PID_FILE" "$PID_FILE" "$CPU_SAMPLE_FILE"     "$TRANSPORT_ENDPOINTS_FILE" "$TRANSPORT_ENDPOINTS_SIGNATURE_FILE" "$LAST_RECOVERY_EVENT_FILE"     "$LAST_UNDERLAY_CHANGE_FILE" "$LAST_APP_CONFLICT_FILE" "$UNDERLAY_RESTART_COUNT_FILE" "$RPC_RESTART_COUNT_FILE" 2>/dev/null || true
rm "$RECOVERY_PHASE_FILE" "$DAEMON_HEARTBEAT_FILE" 2>/dev/null || true
rmdir "$DAEMON_LOCK_DIR" "$NETWORK_WATCH_LOCK_DIR" "$START_LOCK" "$HOTSPOT_ACCESS_LOCK_DIR" "$TUN_FIREWALL_LOCK_DIR" 2>/dev/null || true

# Restore an old EasyTier module only when TierNest itself disabled it.
MODULES_ROOT=${TIERNEST_MODULES_ROOT:-/data/adb/modules}
OLD_EASYTIER="$MODULES_ROOT/easytier_magisk"
OLD_DISABLE_MARKER="$OLD_EASYTIER/.disabled-by-tiernest"
if [ -f "$OLD_DISABLE_MARKER" ]; then
    rm "$OLD_EASYTIER/disable" "$OLD_DISABLE_MARKER" 2>/dev/null || true
fi

sync

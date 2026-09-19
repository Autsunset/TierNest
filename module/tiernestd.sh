#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/hotspot.sh"
. "$MODDIR/tun_firewall.sh"

workers_blocked && exit 0

daemon_pid_matches() {
    candidate=$1
    [ -n "$candidate" ] && [ -r "/proc/$candidate/cmdline" ] || return 1
    command_line=$(tr '\000' ' ' < "/proc/$candidate/cmdline" 2>/dev/null)
    case "$command_line" in
        *"$MODDIR/tiernestd.sh"*) return 0 ;;
    esac
    return 1
}

if ! mkdir "$DAEMON_LOCK_DIR" 2>/dev/null; then
    # Give a concurrent winner time to publish its identity.
    sleep 1
    existing=""
    [ -r "$DAEMON_PID_FILE" ] && existing=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
    if [ "$existing" != "$$" ] && daemon_pid_matches "$existing"; then
        exit 0
    fi
    rmdir "$DAEMON_LOCK_DIR" 2>/dev/null || exit 0
    mkdir "$DAEMON_LOCK_DIR" 2>/dev/null || exit 0
fi

existing=""
[ -r "$DAEMON_PID_FILE" ] && existing=$(cat "$DAEMON_PID_FILE" 2>/dev/null)
if [ "$existing" != "$$" ] && daemon_pid_matches "$existing"; then
    rmdir "$DAEMON_LOCK_DIR" 2>/dev/null
    exit 0
fi
echo $$ > "$DAEMON_PID_FILE"

cleanup_daemon_files() {
    daemon_exit_code=$?
    log_msg "TierNest daemon exited pid=$$ code=$daemon_exit_code recovery_phase=$(cat "$RECOVERY_PHASE_FILE" 2>/dev/null || echo none)"
    rm "$DAEMON_PID_FILE" 2>/dev/null || true
    rmdir "$DAEMON_LOCK_DIR" 2>/dev/null || true
}

shutdown_daemon() {
    # Explicit stop owns final cleanup after all background writers are gone.
    workers_blocked && exit 0
    log_msg "TierNest daemon received shutdown signal pid=$$"
    watch_pid=$(managed_script_pid "$NETWORK_WATCH_PID_FILE" network_watch.sh 2>/dev/null || true)
    stop_script_tree "$NETWORK_WATCH_PID_FILE" network_watch.sh || true
    cleanup_hotspot_access
    cleanup_tun_firewall_guard
    legacy_hotspot_artifacts_present && cleanup_hotspot_forwarding
    stop_core
    cleanup_route_guard
    rm "$NETWORK_WATCH_PID_FILE" 2>/dev/null || true
    exit 0
}
trap shutdown_daemon TERM INT HUP
trap cleanup_daemon_files EXIT

record_recovery_phase() {
    printf '%s|%s|%s\n' "$(date +%s)" "$restart_reason" "$1" > "$RECOVERY_PHASE_FILE.$$.tmp"
    mv "$RECOVERY_PHASE_FILE.$$.tmp" "$RECOVERY_PHASE_FILE"
    log_msg "Recovery phase reason=$restart_reason phase=$1"
}

restart_easytier_for_reason() {
    restart_reason=$1
    restart_counter_file=$2
    # Recheck after debounce and immediately before any destructive lifecycle step.
    if workers_blocked || easytier_app_vpn_active; then
        return 1
    fi
    restart_started=$(date +%s)
    case "$restart_started" in *[!0-9]*|'') restart_started=0;; esac
    record_recovery_phase capture-before
    capture_transport_endpoints "before-restart-$restart_reason" >/dev/null 2>&1 || true
    log_msg "Restarting EasyTier reason=$restart_reason"
    record_recovery_phase cleanup-firewall
    cleanup_hotspot_access
    cleanup_tun_firewall_guard
    record_recovery_phase stop-core
    stop_core
    record_recovery_phase cleanup-routes
    cleanup_route_guard
    record_recovery_phase start-core
    if workers_blocked; then
        record_recovery_phase cancelled
        return 1
    fi
    if start_core; then
        record_recovery_phase restore-routes
        sleep 2
        sync_route_guard
        sync_tun_firewall_guard || true
        sync_hotspot_access || true
        increment_counter "$restart_counter_file" >/dev/null
        restart_finished=$(date +%s)
        case "$restart_finished" in *[!0-9]*|'') restart_finished=$restart_started;; esac
        restart_duration=$((restart_finished - restart_started))
        [ "$restart_duration" -ge 0 ] || restart_duration=0
        printf '%s|%s|success|%s\n' "$restart_finished" "$restart_reason" "$restart_duration" > "$LAST_RECOVERY_EVENT_FILE"
        capture_transport_endpoints "after-restart-$restart_reason" >/dev/null 2>&1 || true
        record_recovery_phase completed
        log_msg "EasyTier restart completed reason=$restart_reason duration=${restart_duration}s"
        last_route_sync=$restart_finished
        last_recovery_epoch=$last_route_sync
        health_failures=0
        last_core_pid=$(core_pid 2>/dev/null || true)
        return 0
    fi
    restart_finished=$(date +%s)
    case "$restart_finished" in *[!0-9]*|'') restart_finished=$restart_started;; esac
    restart_duration=$((restart_finished - restart_started))
    [ "$restart_duration" -ge 0 ] || restart_duration=0
    printf '%s|%s|failed|%s\n' "$restart_finished" "$restart_reason" "$restart_duration" > "$LAST_RECOVERY_EVENT_FILE"
    capture_transport_endpoints "restart-failed-$restart_reason" >/dev/null 2>&1 || true
    record_recovery_phase failed
    log_msg "ERROR: EasyTier restart failed reason=$restart_reason duration=${restart_duration}s"
    last_route_sync=0
    last_recovery_epoch=$restart_finished
    return 1
}

# Observed changes and successfully recovered changes are separate watermarks.
# Debounce, cooldown and a failed restart must not consume a pending change.
reconcile_underlay_change() {
    current_underlay_signature=$(underlay_signature)
    underlay_change_epoch=$(date +%s)
    case "$underlay_change_epoch" in *[!0-9]*|'') underlay_change_epoch=0;; esac
    if [ "$current_underlay_signature" != "$last_underlay_signature" ]; then
        printf '%s|%s|%s\n' "$underlay_change_epoch" "${last_underlay_signature:-none}" "${current_underlay_signature:-none}" > "$LAST_UNDERLAY_CHANGE_FILE"
        log_msg "Physical underlay changed: ${last_underlay_signature:-none} -> ${current_underlay_signature:-none}"
        last_underlay_signature=$current_underlay_signature
    fi
    if [ "$AUTO_RESTART_ON_UNDERLAY_CHANGE" != 1 ]; then
        recovered_underlay_signature=$current_underlay_signature
        return 0
    fi
    [ "$current_underlay_signature" != none ] || return 0
    [ "$current_underlay_signature" != "$recovered_underlay_signature" ] || return 0
    [ $((underlay_change_epoch - last_underlay_restart)) -ge "$UNDERLAY_RESTART_COOLDOWN" ] || return 0
    log_msg "Waiting ${UNDERLAY_RESTART_DELAY}s for physical underlay routing to settle"
    sleep "$UNDERLAY_RESTART_DELAY"
    stable_underlay_signature=$(underlay_signature)
    if [ "$stable_underlay_signature" != "$current_underlay_signature" ]; then
        log_msg "Physical underlay changed again during debounce; recovery remains pending: $current_underlay_signature -> $stable_underlay_signature"
        return 0
    fi
    # A manual stop/disable or APP VPN during debounce takes precedence over recovery.
    if workers_blocked || easytier_app_vpn_active; then
        return 0
    fi
    # This restart also rebuilds connections for the VPN state present at its
    # start. A later VPN change must remain pending, not be silently consumed.
    underlay_recovery_vpn=$(external_vpn_state)
    if restart_easytier_for_reason underlay-change "$UNDERLAY_RESTART_COUNT_FILE"; then
        recovered_underlay_signature=$stable_underlay_signature
        recovered_external_vpn_state=$underlay_recovery_vpn
        rpc_failures=0
        last_rpc_check=0
    fi
    last_underlay_restart=$(date +%s)
    return 0
}

reconcile_external_vpn_change() {
    current_external_vpn_state=$(external_vpn_state)
    vpn_change_epoch=$(date +%s)
    if [ "$current_external_vpn_state" != "$last_external_vpn_state" ]; then
        printf '%s|%s|%s\n' "$vpn_change_epoch" "${last_external_vpn_state:-none}" "${current_external_vpn_state:-none}" > "$LAST_VPN_CHANGE_FILE"
        log_msg "External VPN state changed: ${last_external_vpn_state:-none} -> ${current_external_vpn_state:-none}"
        last_external_vpn_state=$current_external_vpn_state
    fi
    if [ "$AUTO_RESTART_ON_VPN_CHANGE" != 1 ]; then
        recovered_external_vpn_state=$current_external_vpn_state
        return 0
    fi
    [ "$current_external_vpn_state" != "$recovered_external_vpn_state" ] || return 0
    [ $((vpn_change_epoch - last_vpn_restart)) -ge "$VPN_RESTART_COOLDOWN" ] || return 0
    log_msg "Waiting ${VPN_RESTART_DELAY}s for Android VPN routing to settle"
    sleep "$VPN_RESTART_DELAY"
    stable_external_vpn_state=$(external_vpn_state)
    [ "$stable_external_vpn_state" = "$current_external_vpn_state" ] || return 0
    if workers_blocked || easytier_app_vpn_active; then
        return 0
    fi
    vpn_recovery_underlay=$(underlay_signature)
    if restart_easytier_for_reason external-vpn-change "$VPN_RESTART_COUNT_FILE"; then
        recovered_external_vpn_state=$stable_external_vpn_state
        # Coalesce a physical change during VPN debounce as well.
        recovered_underlay_signature=$vpn_recovery_underlay
        rpc_failures=0
        last_rpc_check=0
    fi
    last_vpn_restart=$(date +%s)
    return 0
}

workers_blocked && exit 0

log_msg "TierNest daemon starting framework=$(framework_name) sdk=$(getprop ro.build.version.sdk 2>/dev/null)"

waited=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$waited" -lt 180 ]; do
    workers_blocked && exit 0
    sleep 2
    waited=$((waited + 2))
done
sleep 3
workers_blocked && exit 0

if ! managed_script_pid "$NETWORK_WATCH_PID_FILE" network_watch.sh >/dev/null 2>&1; then
    # The watcher owns its PID file. Do not replace a surviving watcher's PID
    # with the PID of a duplicate invocation which immediately exits.
    "$MODDIR/network_watch.sh" >> "$MODULE_LOG" 2>&1 &
fi

last_route_sync=0
last_external_vpn_state=$(external_vpn_state)
recovered_external_vpn_state=$last_external_vpn_state
last_vpn_restart=0
last_underlay_signature=$(underlay_signature)
recovered_underlay_signature=$last_underlay_signature
last_underlay_restart=0
last_rpc_check=0
last_rpc_restart=0
rpc_failures=0
last_app_conflict=0
last_health_check=0
last_hotspot_access_check=0
last_transport_wait_log=0
health_failures=0
last_core_pid=""
last_recovery_epoch=$(date +%s)
log_msg "External VPN initial state: ${last_external_vpn_state:-none}"
log_msg "Physical underlay initial state: ${last_underlay_signature:-none}"
legacy_hotspot_artifacts_present && cleanup_hotspot_forwarding

while true; do
    date +%s > "$DAEMON_HEARTBEAT_FILE"
    if workers_blocked; then
        stop_script_tree "$NETWORK_WATCH_PID_FILE" network_watch.sh || true
        cleanup_hotspot_access
        cleanup_tun_firewall_guard
        stop_core
        cleanup_route_guard
        exit 0
    fi

    if easytier_app_vpn_active; then
        conflict_epoch=$(date +%s)
        case "$conflict_epoch" in *[!0-9]*|'') conflict_epoch=0;; esac
        if [ "$last_app_conflict" != 1 ]; then
            app_signal=$(easytier_app_vpn_state 2>/dev/null | tr '
' '  ' | head -c 512)
            printf '%s|active|%s
' "$conflict_epoch" "$app_signal" > "$LAST_APP_CONFLICT_FILE"
            log_msg "EasyTier APP VPN conflict detected; pausing TierNest core instead of treating it as a generic external VPN"
        fi
        last_app_conflict=1
        if core_running; then
            cleanup_hotspot_access
            cleanup_tun_firewall_guard
            stop_core
            cleanup_route_guard
        fi
        set_description "冲突：EasyTier APP VPN 正在运行"
        sleep "$WATCHDOG_INTERVAL"
        continue
    elif [ "$last_app_conflict" = 1 ]; then
        clear_epoch=$(date +%s)
        printf '%s|cleared|none
' "$clear_epoch" > "$LAST_APP_CONFLICT_FILE"
        log_msg "EasyTier APP VPN conflict cleared; TierNest may resume"
        last_app_conflict=0
        last_underlay_signature=$(underlay_signature)
        recovered_underlay_signature=$last_underlay_signature
    fi

    if ! core_running; then
        cleanup_hotspot_access
        cleanup_tun_firewall_guard
        cleanup_route_guard
        start_core || {
            sleep "$WATCHDOG_INTERVAL"
            continue
        }
        last_route_sync=0
        last_hotspot_access_check=0
        last_recovery_epoch=$(date +%s)
        health_failures=0
        rpc_failures=0
        last_rpc_check=0
        last_underlay_signature=$(underlay_signature)
        recovered_underlay_signature=$last_underlay_signature
    fi

    current_core_pid=$(core_pid 2>/dev/null || true)
    if [ -n "$current_core_pid" ] && [ "$current_core_pid" != "$last_core_pid" ]; then
        last_core_pid=$current_core_pid
        last_recovery_epoch=$(date +%s)
        health_failures=0
    fi

    reconcile_underlay_change

    reconcile_external_vpn_change

    now_epoch=$(date +%s)
    case "$now_epoch" in *[!0-9]*|'') now_epoch=0;; esac
    if [ "$RPC_HEALTH_ENABLED" = 1 ]         && { [ "$last_rpc_check" -eq 0 ] || [ $((now_epoch - last_rpc_check)) -ge "$RPC_HEALTH_INTERVAL" ]; }; then
        last_rpc_check=$now_epoch
        rpc_state=$(easytier_rpc_state)
        case "$rpc_state" in
            healthy)
                if [ "$rpc_failures" -gt 0 ]; then log_msg "EasyTier RPC recovered after $rpc_failures failure(s)"; fi
                rpc_failures=0
                ;;
            timeout|invalid)
                rpc_failures=$((rpc_failures + 1))
                log_msg "WARN: EasyTier RPC unhealthy state=$rpc_state count=$rpc_failures/$RPC_FAIL_THRESHOLD endpoints=$(live_transport_endpoint_count)"
                if [ "$rpc_failures" -ge "$RPC_FAIL_THRESHOLD" ]                     && [ $((now_epoch - last_rpc_restart)) -ge "$RPC_RESTART_COOLDOWN" ]; then
                    restart_easytier_for_reason "rpc-$rpc_state" "$RPC_RESTART_COUNT_FILE" || true
                    last_rpc_restart=$(date +%s)
                    rpc_failures=0
                    last_rpc_check=0
                fi
                ;;
            *) rpc_failures=0 ;;
        esac
    fi

    if [ "$last_route_sync" -eq 0 ] || [ $((now_epoch - last_route_sync)) -ge "$ROUTE_SYNC_INTERVAL" ]; then
        sync_route_guard
        sync_tun_firewall_guard || true
        last_route_sync=$now_epoch
    fi

    if [ "$last_hotspot_access_check" -eq 0 ]         || [ $((now_epoch - last_hotspot_access_check)) -ge "$HOTSPOT_ACCESS_CHECK_INTERVAL" ]; then
        sync_hotspot_access || true
        last_hotspot_access_check=$now_epoch
    fi

    if [ "$HEALTH_CHECK_ENABLED" = "1" ] \
        && [ $((now_epoch - last_health_check)) -ge "$HEALTH_CHECK_INTERVAL" ]; then
        last_health_check=$now_epoch
        core_started_at=0
        [ -r "$CORE_STARTED_AT_FILE" ] && core_started_at=$(cat "$CORE_STARTED_AT_FILE" 2>/dev/null)
        case "$core_started_at" in *[!0-9]*|'') core_started_at=0;; esac
        core_age=$((now_epoch - core_started_at))

        if [ "$core_started_at" -gt 0 ] && [ "$core_age" -ge "$HEALTH_STARTUP_GRACE" ]; then
            health_state=$(health_probe_state)
            case "$health_state" in
                healthy)
                    if [ "$health_failures" -gt 0 ]; then
                        log_msg "Health probe recovered after $health_failures failure(s)"
                    fi
                    health_failures=0
                    ;;
                underlying-offline|disabled|unconfigured)
                    health_failures=0
                    ;;
                proxy-unreachable|overlay-unreachable)
                    # First repair policy-table drift. This is cheaper and less disruptive
                    # than restarting the EasyTier core.
                    sync_route_guard
                    sleep 1
                    repaired_state=$(health_probe_state)
                    if [ "$repaired_state" = "healthy" ]; then
                        printf '%s|route-reconcile-%s|success|1\n' "$now_epoch" "$health_state" > "$LAST_RECOVERY_EVENT_FILE"
                        log_msg "Health probe repaired by route reconciliation state=$health_state"
                        health_failures=0
                    else
                        health_state=$repaired_state
                        if [ "$health_state" = "proxy-unreachable" ] && try_alternate_route_mode; then
                            sleep 2
                            switched_state=$(health_probe_state)
                            if [ "$switched_state" = "healthy" ]; then
                                printf '%s|route-mode-switch|success|2\n' "$now_epoch" > "$LAST_RECOVERY_EVENT_FILE"
                                log_msg "Health probe repaired by automatic route-mode switch"
                                health_failures=0
                                health_state=healthy
                            else
                                health_state=$switched_state
                            fi
                        fi
                        if [ "$health_state" != "healthy" ]; then
                            health_failures=$((health_failures + 1))
                            printf '%s|%s|%s\n' "$now_epoch" "$health_state" "$health_failures" > "$LAST_HEALTH_EVENT_FILE"
                            log_msg "WARN: health probe failed state=$health_state count=$health_failures/$HEALTH_FAIL_THRESHOLD"
                            if [ "$health_failures" -ge "$HEALTH_FAIL_THRESHOLD" ] \
                                && [ $((now_epoch - last_recovery_epoch)) -ge "$HEALTH_RESTART_COOLDOWN" ]; then
                                if should_wait_for_transport_reconnect "$health_state"; then
                                    printf '%s|transport-reconnect-wait|suppressed|0\n' "$now_epoch" > "$LAST_RECOVERY_EVENT_FILE"
                                    if [ $((now_epoch - last_transport_wait_log)) -ge 300 ]; then
                                        log_msg "Health restart suppressed: EasyTier has no remote peers; allowing the core to continue reconnecting"
                                        last_transport_wait_log=$now_epoch
                                    fi
                                    health_failures=$HEALTH_FAIL_THRESHOLD
                                else
                                    restart_easytier_for_reason "health-$health_state" "$HEALTH_RESTART_COUNT_FILE"
                                fi
                            fi
                        fi
                    fi
                    ;;
            esac
        fi
    fi

    sleep "$WATCHDOG_INTERVAL"
done

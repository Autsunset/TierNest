#!/system/bin/sh

# Module disk usage changes slowly. Cache it for five minutes, invalidate on
# version change or clock rollback, and publish atomically for multiple WebViews.
module_size_kb_cached() (
    size_now=$1
    size_cache="$RUNDIR/module-size.cache"
    size_version=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null || true)
    size_epoch=0; size_kb=0; size_cached_version=""
    if [ -r "$size_cache" ]; then
        IFS='|' read -r size_epoch size_cached_version size_kb < "$size_cache" || true
        case "$size_epoch:$size_kb" in *[!0-9:]*|:*|*:) size_epoch=0; size_kb=0;; esac
        if [ "$size_epoch" -gt 0 ] && [ "$size_now" -ge "$size_epoch" ] \
            && [ $((size_now - size_epoch)) -lt 300 ] && [ "$size_cached_version" = "$size_version" ]; then
            echo "$size_kb"
            exit 0
        fi
    fi
    size_kb=$(du -sk "$MODDIR" 2>/dev/null | awk '{print $1; exit}')
    case "$size_kb" in *[!0-9]*|'') echo 0; exit 0;; esac
    size_tmp=$(mktemp "$RUNDIR/.module-size.XXXXXX") || { echo "$size_kb"; exit 0; }
    printf '%s|%s|%s\n' "$size_now" "$size_version" "$size_kb" > "$size_tmp"
    mv "$size_tmp" "$size_cache" 2>/dev/null || rm "$size_tmp" 2>/dev/null
    echo "$size_kb"
)

print_metrics() {
    pid=$(overview_sample pid)
    dev=$(overview_sample tun)
    now_epoch=$(date +%s)
    case "$now_epoch" in *[!0-9]*|'') now_epoch=0;; esac

    cpu_percent=0.0
    rss_kb=0
    vm_kb=0
    threads=0
    fd_count=0
    runtime_seconds=0

    if [ -n "$pid" ] && [ -r "/proc/$pid/status" ] && [ -r "/proc/$pid/stat" ]; then
        rss_kb=$(awk '/^VmRSS:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null)
        vm_kb=$(awk '/^VmSize:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null)
        threads=$(awk '/^Threads:/ {print $2; exit}' "/proc/$pid/status" 2>/dev/null)
        fd_count=$(ls -1 "/proc/$pid/fd" 2>/dev/null | wc -l)
        for value_name in rss_kb vm_kb threads fd_count; do
            eval value=\$$value_name
            case "$value" in *[!0-9]*|'') eval "$value_name=0";; esac
        done

        started_at=0
        [ -r "$CORE_STARTED_AT_FILE" ] && started_at=$(cat "$CORE_STARTED_AT_FILE" 2>/dev/null)
        case "$started_at" in *[!0-9]*|'') started_at=0;; esac
        if [ "$started_at" -gt 0 ] && [ "$now_epoch" -ge "$started_at" ]; then
            runtime_seconds=$((now_epoch - started_at))
        fi

        proc_ticks=$(awk '{print $14 + $15}' "/proc/$pid/stat" 2>/dev/null)
        total_ticks=$(awk '/^cpu / {sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum; exit}' /proc/stat 2>/dev/null)
        cpu_count=$(grep -c '^processor[[:space:]]*:' /proc/cpuinfo 2>/dev/null || true)
        case "$proc_ticks" in *[!0-9]*|'') proc_ticks=0;; esac
        case "$total_ticks" in *[!0-9]*|'') total_ticks=0;; esac
        case "$cpu_count" in *[!0-9]*|'') cpu_count=1;; esac
        [ "$cpu_count" -gt 0 ] || cpu_count=1

        if [ -r "$CPU_SAMPLE_FILE" ]; then
            read old_pid old_proc old_total < "$CPU_SAMPLE_FILE"
            case "$old_proc" in *[!0-9]*|'') old_proc=0;; esac
            case "$old_total" in *[!0-9]*|'') old_total=0;; esac
            if [ "$old_pid" = "$pid" ] && [ "$total_ticks" -gt "$old_total" ] && [ "$proc_ticks" -ge "$old_proc" ]; then
                cpu_percent=$(awk -v dp="$((proc_ticks - old_proc))" -v dt="$((total_ticks - old_total))" -v n="$cpu_count" 'BEGIN { if (dt > 0) printf "%.1f", (dp / dt) * 100 * n; else print "0.0" }')
            fi
        fi
        printf '%s %s %s\n' "$pid" "$proc_ticks" "$total_ticks" > "$CPU_SAMPLE_FILE"
    else
        rm -f "$CPU_SAMPLE_FILE" 2>/dev/null
    fi

    rx_bytes=0
    tx_bytes=0
    if [ -n "$dev" ] && [ -r "/sys/class/net/$dev/statistics/rx_bytes" ]; then
        rx_bytes=$(cat "/sys/class/net/$dev/statistics/rx_bytes" 2>/dev/null)
        tx_bytes=$(cat "/sys/class/net/$dev/statistics/tx_bytes" 2>/dev/null)
    fi
    case "$rx_bytes" in *[!0-9]*|'') rx_bytes=0;; esac
    case "$tx_bytes" in *[!0-9]*|'') tx_bytes=0;; esac

    module_log_bytes=0
    core_log_bytes=0
    network_log_bytes=0
    transport_log_bytes=0
    hotspot_log_bytes=0
    [ -f "$MODULE_LOG" ] && module_log_bytes=$(wc -c < "$MODULE_LOG" 2>/dev/null)
    [ -f "$CORE_LOG" ] && core_log_bytes=$(wc -c < "$CORE_LOG" 2>/dev/null)
    [ -f "$NETWORK_LOG" ] && network_log_bytes=$(wc -c < "$NETWORK_LOG" 2>/dev/null)
    [ -f "$TRANSPORT_LOG" ] && transport_log_bytes=$(wc -c < "$TRANSPORT_LOG" 2>/dev/null)
    [ -f "$HOTSPOT_LOG" ] && hotspot_log_bytes=$(wc -c < "$HOTSPOT_LOG" 2>/dev/null)
    case "$module_log_bytes" in *[!0-9]*|'') module_log_bytes=0;; esac
    case "$core_log_bytes" in *[!0-9]*|'') core_log_bytes=0;; esac
    case "$network_log_bytes" in *[!0-9]*|'') network_log_bytes=0;; esac
    case "$transport_log_bytes" in *[!0-9]*|'') transport_log_bytes=0;; esac
    case "$hotspot_log_bytes" in *[!0-9]*|'') hotspot_log_bytes=0;; esac
    log_total_bytes=$((module_log_bytes + core_log_bytes + network_log_bytes + transport_log_bytes + hotspot_log_bytes))

    module_kb=$(module_size_kb_cached "$now_epoch")
    case "$module_kb" in *[!0-9]*|'') module_kb=0;; esac

    route_count=$(ip -4 route show table "$ROUTE_TABLE" 2>/dev/null | grep -c . || true)
    case "$route_count" in *[!0-9]*|'') route_count=0;; esac

    last_vpn_change_epoch=0
    last_vpn_before=none
    last_vpn_after=none
    if [ -r "$LAST_VPN_CHANGE_FILE" ]; then
        IFS='|' read last_vpn_change_epoch last_vpn_before last_vpn_after < "$LAST_VPN_CHANGE_FILE"
    fi
    case "$last_vpn_change_epoch" in *[!0-9]*|'') last_vpn_change_epoch=0;; esac

    echo "cpu_percent=$cpu_percent"
    echo "rss_kb=$rss_kb"
    echo "vm_kb=$vm_kb"
    echo "threads=$threads"
    echo "fd_count=$fd_count"
    echo "runtime_seconds=$runtime_seconds"
    echo "tun_rx_bytes=$rx_bytes"
    echo "tun_tx_bytes=$tx_bytes"
    echo "module_log_bytes=$module_log_bytes"
    echo "core_log_bytes=$core_log_bytes"
    echo "network_log_bytes=$network_log_bytes"
    echo "transport_log_bytes=$transport_log_bytes"
    echo "hotspot_log_bytes=$hotspot_log_bytes"
    echo "log_total_bytes=$log_total_bytes"
    echo "module_size_bytes=$((module_kb * 1024))"
    echo "vpn_restart_count=$(read_counter "$VPN_RESTART_COUNT_FILE")"
    echo "underlay_restart_count=$(read_counter "$UNDERLAY_RESTART_COUNT_FILE")"
    echo "rpc_restart_count=$(read_counter "$RPC_RESTART_COUNT_FILE")"
    echo "health_restart_count=$(read_counter "$HEALTH_RESTART_COUNT_FILE")"
    echo "route_sync_count=$(read_counter "$ROUTE_SYNC_COUNT_FILE")"
    echo "route_count=$route_count"
    echo "route_strategy=$(route_strategy_effective)"
    echo "route_mode_active=$(route_mode_active)"
    if android_network_table_mirroring_enabled; then echo "android_table_mirroring=1"; else echo "android_table_mirroring=0"; fi
    hotspot_access_enabled=$HOTSPOT_CLIENT_ACCESS_ENABLED
    if [ -r "$HOTSPOT_ACCESS_OVERRIDE_FILE" ]; then
        case "$(cat "$HOTSPOT_ACCESS_OVERRIDE_FILE" 2>/dev/null)" in on) hotspot_access_enabled=1;; off) hotspot_access_enabled=0;; esac
    fi
    hotspot_access_target_count=$(grep -c . "$HOTSPOT_ACCESS_TARGETS_FILE" 2>/dev/null || true)
    case "$hotspot_access_target_count" in *[!0-9]*|'') hotspot_access_target_count=0;; esac
    if [ -r "$HOTSPOT_ACCESS_STATE_FILE" ]; then hotspot_access_active=1; else hotspot_access_active=0; fi
    echo "hotspot_access_enabled=$hotspot_access_enabled"
    echo "hotspot_access_active=$hotspot_access_active"
    echo "hotspot_access_target_count=$hotspot_access_target_count"
    echo "hotspot_access_reapply_count=$(read_counter "$HOTSPOT_ACCESS_REAPPLY_COUNT_FILE")"
    local_override_count=$(grep -c . "$LOCAL_ROUTE_OVERRIDES_FILE" 2>/dev/null || true)
    case "$local_override_count" in *[!0-9]*|'') local_override_count=0;; esac
    echo "local_route_override_count=$local_override_count"
    android_route_count=$(grep -c . "$ANDROID_ROUTE_SPECS_FILE" 2>/dev/null || true)
    case "$android_route_count" in *[!0-9]*|'') android_route_count=0;; esac
    android_table_count=$(grep -c . "$ANDROID_ROUTE_TABLES_FILE" 2>/dev/null || true)
    case "$android_table_count" in *[!0-9]*|'') android_table_count=0;; esac
    echo "android_app_route_count=$android_route_count"
    echo "android_app_table_count=$android_table_count"
    echo "last_vpn_change_epoch=$last_vpn_change_epoch"
    echo "last_vpn_before=$last_vpn_before"
    echo "last_vpn_after=$last_vpn_after"
    last_recovery_epoch=0
    last_recovery_reason=none
    last_recovery_status=none
    last_recovery_duration=0
    if [ -r "$LAST_RECOVERY_EVENT_FILE" ]; then
        IFS='|' read last_recovery_epoch last_recovery_reason last_recovery_status last_recovery_duration < "$LAST_RECOVERY_EVENT_FILE"
    fi
    case "$last_recovery_epoch" in *[!0-9]*|'') last_recovery_epoch=0;; esac
    case "$last_recovery_duration" in *[!0-9]*|'') last_recovery_duration=0;; esac
    endpoint_count=$(grep -c '^active ' "$TRANSPORT_ENDPOINTS_FILE" 2>/dev/null || true)
    case "$endpoint_count" in *[!0-9]*|'') endpoint_count=0;; esac
    echo "last_recovery_epoch=$last_recovery_epoch"
    echo "last_recovery_reason=${last_recovery_reason:-none}"
    echo "last_recovery_status=${last_recovery_status:-none}"
    echo "last_recovery_duration=$last_recovery_duration"
    echo "transport_endpoint_count=$endpoint_count"
    echo "live_transport_endpoint_count=$(overview_sample endpoints)"
    echo "underlay=$(overview_sample underlay)"
    echo "rpc_state=$(overview_sample rpc)"
    echo "last_underlay_change=$(cat "$LAST_UNDERLAY_CHANGE_FILE" 2>/dev/null || echo none)"
    echo "easytier_app_vpn=$(overview_sample app)"
    last_health_event_epoch=0
    last_health_event_state=none
    last_health_event_failures=0
    if [ -r "$LAST_HEALTH_EVENT_FILE" ]; then
        IFS='|' read last_health_event_epoch last_health_event_state last_health_event_failures < "$LAST_HEALTH_EVENT_FILE"
    fi
    echo "last_health_event_epoch=${last_health_event_epoch:-0}"
    echo "last_health_event_state=${last_health_event_state:-none}"
    echo "last_health_event_failures=${last_health_event_failures:-0}"
}

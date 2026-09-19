#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/hotspot.sh"
. "$MODDIR/tun_firewall.sh"
. "$MODDIR/metrics.sh"
. "$MODDIR/config_api.sh"
. "$MODDIR/service_api.sh"

command=${1:-status}

print_status() {
    pid=$(overview_sample pid)
    dev=$(overview_sample tun)
    active_mode=$(route_mode_active)
    case "$active_mode" in
        upstream) pref=$(find_upstream_main_rule_pref 2>/dev/null || true); active_table=main ;;
        target-main) pref=$(head -n 1 "$TARGET_MAIN_RULES_FILE" 2>/dev/null | cut -d'|' -f1); active_table=main ;;
        *) pref=$(find_existing_rule_pref 2>/dev/null || true); active_table=$ROUTE_TABLE ;;
    esac
    if [ -n "$pid" ]; then state=running; else state=stopped; fi
    echo "state=$state"
    print_supervision_status
    echo "pid=$pid"
    echo "tun=$dev"
    echo "framework=$(framework_name)"
    vpn_state=$(overview_sample vpn)
    [ -n "$vpn_state" ] || vpn_state=none
    echo "route_guard=$ROUTE_GUARD"
    echo "route_strategy=$(route_strategy_effective)"
    echo "route_strategy_default=$ROUTE_STRATEGY_DEFAULT"
    echo "route_mode_config=$(route_mode_config_effective)"
    echo "route_mode_active=$active_mode"
    echo "requested_route_table=$REQUESTED_ROUTE_TABLE"
    echo "route_table=$active_table"
    echo "rule_priority=$pref"
    local_override_count=$(grep -c . "$LOCAL_ROUTE_OVERRIDES_FILE" 2>/dev/null || true)
    case "$local_override_count" in *[!0-9]*|'') local_override_count=0;; esac
    echo "local_route_override_count=$local_override_count"
    android_route_count=$(grep -c . "$ANDROID_ROUTE_SPECS_FILE" 2>/dev/null || true)
    case "$android_route_count" in *[!0-9]*|'') android_route_count=0;; esac
    android_table_count=$(grep -c . "$ANDROID_ROUTE_TABLES_FILE" 2>/dev/null || true)
    case "$android_table_count" in *[!0-9]*|'') android_table_count=0;; esac
    echo "android_app_route_count=$android_route_count"
    echo "android_app_table_count=$android_table_count"
    echo "external_vpn=$vpn_state"
    echo "easytier_app_vpn=$(overview_sample app)"
    echo "auto_restart_on_vpn_change=$AUTO_RESTART_ON_VPN_CHANGE"
    echo "auto_restart_on_underlay_change=$AUTO_RESTART_ON_UNDERLAY_CHANGE"
    echo "underlay=$(overview_sample underlay)"
    echo "rpc_health_enabled=$RPC_HEALTH_ENABLED"
    echo "rpc_state=$(overview_sample rpc)"
    echo "live_transport_endpoint_count=$(overview_sample endpoints)"
    echo "last_underlay_change=$(cat "$LAST_UNDERLAY_CHANGE_FILE" 2>/dev/null || echo none)"
    echo "last_easytier_app_conflict=$(cat "$LAST_APP_CONFLICT_FILE" 2>/dev/null || echo none)"
    echo "health_check_enabled=$HEALTH_CHECK_ENABLED"
    echo "transport_observer_enabled=$TRANSPORT_OBSERVER_ENABLED"
    echo "health_easytier_target=$HEALTH_EASYTIER_TARGET"
    echo "health_proxy_target=$HEALTH_PROXY_TARGET"
    echo "network_name=$(get_toml_string network_name)"
    echo "virtual_ipv4=$(get_toml_string ipv4)"
    configured_dev=$(get_toml_string dev_name 2>/dev/null)
    [ -n "$configured_dev" ] || configured_dev=auto-tunX
    echo "config_dev_name=$configured_dev"
    echo "config_enable_kcp_proxy=$(get_toml_bool enable_kcp_proxy false)"
    echo "config_use_smoltcp=$(get_toml_bool use_smoltcp false)"
    echo "tcp_compatibility=$(tcp_compatibility_state)"
    echo "health_tcp_target=$HEALTH_TCP_TARGET"
    echo "health_tcp_port=$HEALTH_TCP_PORT"
    if [ -r "$COMMAND_ARGS" ]; then echo "config_mode=command_args"; else echo "config_mode=toml"; fi
    echo "module_version=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null)"
    transport_count=$(grep -c '^active ' "$TRANSPORT_ENDPOINTS_FILE" 2>/dev/null || true)
    case "$transport_count" in *[!0-9]*|'') transport_count=0;; esac
    echo "transport_endpoint_count=$transport_count"
    echo "last_recovery_event=$(cat "$LAST_RECOVERY_EVENT_FILE" 2>/dev/null || echo none)"
    echo "transport_log=$TRANSPORT_LOG"
    echo "core_log=$CORE_LOG"
    echo "module_log=$MODULE_LOG"
    print_hotspot_access_status | sed 's/^/hotspot_access_/'
    print_tun_firewall_status | sed 's/^/tun_firewall_/'
}

switch_route_strategy_unlocked() {
    next_strategy=$1
    case "$next_strategy" in official|legacy) ;; *) echo "无效路由策略：$next_strategy" >&2; return 2;; esac
    tmp="$CONFIG_DIR/.route-strategy.$$.tmp"
    printf '%s
' "$next_strategy" > "$tmp" || return 1
    chmod 0600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$ROUTE_STRATEGY_FILE" || return 1
    rm "$ROUTE_MODE_RUNTIME_OVERRIDE_FILE" "$ROUTE_MODE_LAST_SWITCH_FILE" 2>/dev/null || true
    if service_user_blocked; then
        echo "strategy=$next_strategy"
        echo 'restarted=0'
        return 0
    fi
    if restart_service_unlocked; then
        echo "strategy=$(route_strategy_effective)"
        echo "route_mode=$(route_mode_active)"
        if android_network_table_mirroring_enabled; then echo "android_table_mirroring=1"; else echo "android_table_mirroring=0"; fi
        echo "restarted=1"
        return 0
    fi
    echo "切换后 EasyTier 启动失败" >&2
    return 1
}

# One bridge call, one set of expensive probes, two namespaced sections.
print_overview() (
    OVERVIEW_SAMPLE_READY=0
    OVERVIEW_PID=$(overview_sample pid)
    OVERVIEW_TUN=$(overview_sample tun)
    OVERVIEW_VPN=$(overview_sample vpn)
    OVERVIEW_APP=$(overview_sample app)
    OVERVIEW_UNDERLAY=$(overview_sample underlay)
    OVERVIEW_RPC=$(overview_sample rpc)
    OVERVIEW_ENDPOINTS=$(overview_sample endpoints)
    OVERVIEW_SAMPLE_READY=1
    echo 'schema=1'
    echo "sampled_at=$(date +%s)"
    (print_status) | sed 's/^/status./'
    (print_metrics) | sed 's/^/metrics./'
)

print_topology_json() {
    pid=$(core_pid 2>/dev/null || true)
    [ -n "$pid" ] || { echo '[]'; return 0; }
    portal=$(get_rpc_portal)
    if command -v timeout >/dev/null 2>&1; then
        output=$(timeout 8 "$CLI" --rpc-portal "$portal" -o json route list 2>/dev/null || true)
    else
        output=$("$CLI" --rpc-portal "$portal" -o json route list 2>/dev/null || true)
    fi
    trimmed=$(printf '%s' "$output" | sed -e 's/^[[:space:]]*//' | head -c 1)
    if [ "$trimmed" = "[" ]; then
        printf '%s
' "$output"
    else
        echo '[]'
    fi
}

print_topology_locations_b64() {
    [ -r "$NODE_LOCATIONS_FILE" ] || { echo; return 0; }
    base64 "$NODE_LOCATIONS_FILE" 2>/dev/null | tr -d '
'
    echo
}

export_logs() {
    stamp=$(date +%Y%m%d-%H%M%S)
    export_dir=${TIERNEST_EXPORT_DIR:-/sdcard/Download}
    [ -d "$export_dir" ] || export_dir=/data/local/tmp
    output="$export_dir/TierNest-diagnostics-$stamp.txt"
    tmp_output="$output.$$.tmp"
    diagnostic_file=$(sh "$MODDIR/diagnose.sh" 2>/dev/null || true)
    {
        echo "TierNest shareable diagnostics"
        echo "exported=$(now)"
        echo "Sensitive fields are redacted; the full easytier.log is intentionally excluded."
        echo
        if [ -n "$diagnostic_file" ] && [ -r "$diagnostic_file" ]; then
            cat "$diagnostic_file"
        else
            echo "Structured diagnostic generation failed."
        fi
        echo
        echo "================ complete network-watch.log ================"
        cat "$NETWORK_LOG" 2>/dev/null
        echo
        echo "================ complete transport.log ================"
        cat "$TRANSPORT_LOG" 2>/dev/null
        echo
        echo "================ complete tiernest.log ================"
        cat "$MODULE_LOG" 2>/dev/null
        echo
        echo "================ complete hotspot.log ================"
        cat "$HOTSPOT_LOG" 2>/dev/null
    } 2>&1 | redact_sensitive > "$tmp_output"
    mv "$tmp_output" "$output"
    chmod 0644 "$output" 2>/dev/null
    echo "$output"
}

hotspot_access_command_unlocked() {
    case "$1" in
        enable)
            echo on > "$HOTSPOT_ACCESS_OVERRIDE_FILE"
            chmod 0600 "$HOTSPOT_ACCESS_OVERRIDE_FILE" 2>/dev/null || true
            workers_blocked || sync_hotspot_access || true
            ;;
        disable)
            echo off > "$HOTSPOT_ACCESS_OVERRIDE_FILE"
            chmod 0600 "$HOTSPOT_ACCESS_OVERRIDE_FILE" 2>/dev/null || true
            cleanup_hotspot_access
            hotspot_access_clear_error
            ;;
        reapply)
            cleanup_hotspot_access
            workers_blocked || sync_hotspot_access || true
            ;;
    esac
    print_hotspot_access_status
}

sync_service_routes_unlocked() {
    workers_blocked || sync_route_guard
    print_status
}

case "$command" in
    start)
        if start_service; then
            echo "TierNest 已按所选模式启动。"
        else
            echo "TierNest 启动失败，请查看 $CORE_LOG" >&2
            exit 1
        fi
        ;;
    stop)
        stop_service || exit 1
        echo "TierNest 已停止。"
        ;;
    restart)
        restart_service || exit 1
        echo "TierNest 已按所选模式重启。"
        ;;
    toggle)
        if [ ! -f "$MANUAL_STOP_FILE" ] && { core_running || [ -f "$HOME_PAUSED_FILE" ]; }; then
            stop_service || exit 1
            echo "TierNest 已停止。再次点击操作按钮即可启动。"
        elif start_service; then
            echo "TierNest 已按所选模式启动。日志：$CORE_LOG"
        else
            echo "TierNest 启动失败，请查看 $CORE_LOG" >&2
            exit 1
        fi
        ;;
    service-mode-manual|service-mode-auto)
        service_with_lock set_service_mode_unlocked "${command##*-}"
        ;;
    home-forget)
        service_with_lock home_forget_unlocked "${2:-}"
        ;;
    home-learn)
        service_with_lock home_learn_unlocked "${2:-}" "${3:-80}"
        ;;
    home-detection-save)
        service_with_lock set_home_detection_unlocked "${2:-}" "${3:-}"
        ;;
    status)
        print_status
        ;;
    sync-routes)
        service_with_lock sync_service_routes_unlocked
        ;;
    diagnose)
        exec "$MODDIR/diagnose.sh"
        ;;
    export-log)
        export_logs
        ;;
    overview)
        print_overview
        ;;
    metrics)
        print_metrics
        ;;
    topology-json)
        print_topology_json
        ;;
    topology-locations-b64)
        print_topology_locations_b64
        ;;
    topology-locations-save-b64)
        save_topology_locations_b64 "${2:-}"
        ;;
    config-read-b64)
        config_read_b64
        ;;
    config-validate-b64)
        config_validate_b64 "${2:-}"
        ;;
    config-save-b64)
        config_save_b64 "${2:-}"
        ;;
    config-backup)
        create_config_backup
        ;;
    config-migrate-backups)
        migrate_config_backups
        ;;
    route-strategy-status)
        echo "strategy=$(route_strategy_effective)"
        echo "strategy_default=$ROUTE_STRATEGY_DEFAULT"
        echo "route_mode=$(route_mode_active)"
        if android_network_table_mirroring_enabled; then echo "android_table_mirroring=1"; else echo "android_table_mirroring=0"; fi
        ;;
    route-strategy-official)
        service_with_lock switch_route_strategy_unlocked official
        ;;
    route-strategy-legacy)
        service_with_lock switch_route_strategy_unlocked legacy
        ;;
    hotspot-access-status)
        print_hotspot_access_status
        ;;
    hotspot-access-enable)
        service_with_lock hotspot_access_command_unlocked enable
        ;;
    hotspot-access-disable)
        service_with_lock hotspot_access_command_unlocked disable
        ;;
    hotspot-access-reapply)
        service_with_lock hotspot_access_command_unlocked reapply
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|toggle|service-mode-manual|service-mode-auto|home-learn IP [PORT]|home-forget ID|home-detection-save {poll|event} SECONDS|status|overview|metrics|sync-routes|diagnose|export-log|config-read-b64|config-validate-b64 PAYLOAD|config-save-b64 PAYLOAD|config-backup|config-migrate-backups|topology-json|topology-locations-b64|topology-locations-save-b64 PAYLOAD|route-strategy-status|route-strategy-official|route-strategy-legacy|hotspot-access-status|hotspot-access-enable|hotspot-access-disable|hotspot-access-reapply}" >&2
        exit 2
        ;;
esac

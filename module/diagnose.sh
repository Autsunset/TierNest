#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/hotspot.sh"
. "$MODDIR/tun_firewall.sh"

stamp=$(date +%Y%m%d-%H%M%S)
OUT="$LOGDIR/diagnostics-$stamp.txt"
TMP_OUT="$LOGDIR/.diagnostics-$stamp.$$.tmp"

pid=$(core_pid 2>/dev/null || true)
dev=$(find_tun_device 2>/dev/null || true)
portal=$(get_rpc_portal)
capture_transport_endpoints diagnose "$pid" >/dev/null 2>&1 || true

{
    echo "TierNest structured diagnostics"
    echo "schema=3"
    echo "generated=$(now)"
    echo "framework=$(framework_name)"
    echo "android_release=$(getprop ro.build.version.release 2>/dev/null)"
    echo "android_sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
    echo "device=$(getprop ro.product.manufacturer 2>/dev/null) $(getprop ro.product.model 2>/dev/null)"
    echo "kernel=$(uname -a)"
    echo "module_version=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null)"
    echo "core_pid=${pid:-stopped}"
    echo "tun=${dev:-not-found}"
    echo "config_mode=$([ -r "$COMMAND_ARGS" ] && echo command_args || echo toml)"
    echo "network_name=$(get_toml_string network_name)"
    echo "virtual_ipv4=$(get_toml_string ipv4)"
    configured_dev=$(get_toml_string dev_name 2>/dev/null)
    [ -n "$configured_dev" ] || configured_dev=auto-tunX
    echo "config_dev_name=$configured_dev"
    echo "config_enable_kcp_proxy=$(get_toml_bool enable_kcp_proxy false)"
    echo "config_use_smoltcp=$(get_toml_bool use_smoltcp false)"
    echo "tcp_compatibility=$(tcp_compatibility_state)"
    diagnostic_mode=$(route_mode_active)
    case "$diagnostic_mode" in
        upstream) diagnostic_table=main; diagnostic_pref=$(find_upstream_main_rule_pref 2>/dev/null || true) ;;
        target-main) diagnostic_table=main; diagnostic_pref=$(head -n 1 "$TARGET_MAIN_RULES_FILE" 2>/dev/null | cut -d'|' -f1) ;;
        *) diagnostic_table=$ROUTE_TABLE; diagnostic_pref=$(find_existing_rule_pref 2>/dev/null || true) ;;
    esac
    echo "route_strategy=$(route_strategy_effective)"
    echo "route_strategy_default=$ROUTE_STRATEGY_DEFAULT"
    echo "route_mode_config=$(route_mode_config_effective)"
    echo "route_mode_active=$diagnostic_mode"
    if android_network_table_mirroring_enabled; then echo "android_table_mirroring=1"; else echo "android_table_mirroring=0"; fi
    echo "requested_route_table=$REQUESTED_ROUTE_TABLE"
    echo "route_table=$diagnostic_table"
    echo "route_rule_priority=$diagnostic_pref"
    echo "external_vpn=$(external_vpn_state 2>/dev/null || echo none)"
    echo "physical_underlay=$(underlay_signature)"
    echo "rpc_state=$(easytier_rpc_state)"
    echo "live_transport_endpoint_count=$(live_transport_endpoint_count)"
    echo "easytier_app_vpn=$(easytier_app_vpn_active && echo active || echo inactive)"
    echo

    echo "== Runtime counters and recovery =="
    print_supervision_status
    echo "vpn_restart_count=$(read_counter "$VPN_RESTART_COUNT_FILE")"
    echo "underlay_restart_count=$(read_counter "$UNDERLAY_RESTART_COUNT_FILE")"
    echo "rpc_restart_count=$(read_counter "$RPC_RESTART_COUNT_FILE")"
    echo "health_restart_count=$(read_counter "$HEALTH_RESTART_COUNT_FILE")"
    echo "route_sync_count=$(read_counter "$ROUTE_SYNC_COUNT_FILE")"
    echo "last_vpn_change=$(cat "$LAST_VPN_CHANGE_FILE" 2>/dev/null || echo none)"
    echo "last_underlay_change=$(cat "$LAST_UNDERLAY_CHANGE_FILE" 2>/dev/null || echo none)"
    echo "last_easytier_app_conflict=$(cat "$LAST_APP_CONFLICT_FILE" 2>/dev/null || echo none)"
    echo "last_health_event=$(cat "$LAST_HEALTH_EVENT_FILE" 2>/dev/null || echo none)"
    echo "last_recovery_event=$(cat "$LAST_RECOVERY_EVENT_FILE" 2>/dev/null || echo none)"
    echo

    echo "== TCP compatibility =="
    echo "dev_name=${configured_dev:-auto-tunX}"
    echo "enable_kcp_proxy=$(get_toml_bool enable_kcp_proxy false)"
    echo "use_smoltcp=$(get_toml_bool use_smoltcp false)"
    echo "state=$(tcp_compatibility_state)"
    echo "remote_peer_count=$(overlay_remote_peer_count)"
    case "$(tcp_compatibility_state)" in
        recommended) echo "note=KCP sender disabled; recommended stable Android mode" ;;
        kcp-smoltcp) echo "note=KCP enabled through the user-space TCP stack; compatible but adds overhead" ;;
        kcp-kernel-risk) echo "warning=KCP uses the kernel TCP path; some Android ROMs may show Ping OK but HTTP/SSH timeout" ;;
        *) echo "note=command_args mode; inspect startup arguments" ;;
    esac
    tcp_probe_result tcp_health "$HEALTH_TCP_TARGET" "$HEALTH_TCP_PORT"
    echo

    echo "== Binary identity =="
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 "$CORE" --version 2>&1 || true
        timeout 5 "$CLI" --version 2>&1 || true
    else
        "$CORE" --version 2>&1 || true
        "$CLI" --version 2>&1 || true
    fi
    if command -v file >/dev/null 2>&1; then
        file "$CORE" 2>/dev/null || true
        file "$CLI" 2>/dev/null || true
    fi
    echo

    echo "== Managed process =="
    if [ -n "$pid" ]; then
        echo "pid_matches_core=$(pid_matches_core "$pid" && echo yes || echo no)"
        if [ -r "$PROC_ROOT/$pid/cmdline" ]; then
            tr '\000' ' ' < "$PROC_ROOT/$pid/cmdline" 2>/dev/null
            echo
        fi
        [ -r "$PROC_ROOT/$pid/status" ] && sed -n '1,24p' "$PROC_ROOT/$pid/status" 2>/dev/null
    else
        echo "EasyTier core is not running"
    fi
    echo

    echo "== Configured peer authorities =="
    configured_peer_uris | while IFS= read -r uri; do
        [ -n "$uri" ] && sanitize_endpoint_uri "$uri"
    done
    echo

    echo "== EasyTier transport endpoints =="
    cat "$TRANSPORT_ENDPOINTS_FILE" 2>/dev/null || echo "Transport endpoint snapshot unavailable"
    echo

    echo "== IPv4 rules =="
    ip -4 rule show 2>/dev/null
    echo
    echo "== TierNest table $ROUTE_TABLE =="
    ip -4 route show table "$ROUTE_TABLE" 2>/dev/null
    echo
    echo "== Local direct-route overrides =="
    cat "$LOCAL_ROUTE_OVERRIDES_FILE" 2>/dev/null || echo "none"
    echo
    echo "== Android app route mirrors =="
    cat "$ANDROID_ROUTE_SPECS_FILE" 2>/dev/null || echo "none"
    if [ -r "$ANDROID_ROUTE_TABLES_FILE" ]; then
        while IFS= read -r android_table; do
            [ -n "$android_table" ] || continue
            echo "-- table $android_table --"
            ip -4 route show table "$android_table" 2>/dev/null || true
        done < "$ANDROID_ROUTE_TABLES_FILE"
    fi
    echo
    echo "== Route decisions =="
    diagnostic_targets | while IFS='|' read -r label target; do
        [ -n "$target" ] || continue
        echo "-- $label $target --"
        ip -4 route get "$target" 2>&1
    done
    echo

    echo "== TUN firewall guard =="
    print_tun_firewall_status
    echo "-- $TUN_FW_INPUT_CHAIN counters --"
    run_iptables -L "$TUN_FW_INPUT_CHAIN" -n -v 2>/dev/null || true
    echo "-- $TUN_FW_OUTPUT_CHAIN counters --"
    run_iptables -L "$TUN_FW_OUTPUT_CHAIN" -n -v 2>/dev/null || true
    echo

    echo "== Outbound-only hotspot client access =="
    print_hotspot_access_status
    echo "-- managed policy rules --"
    cat "$HOTSPOT_ACCESS_RULES_FILE" 2>/dev/null || echo "none"
    echo "-- managed target CIDRs --"
    cat "$HOTSPOT_ACCESS_TARGETS_FILE" 2>/dev/null || echo "none"
    if resolve_iptables_bin; then
        echo "-- $HOTSPOT_ACCESS_NAT_CHAIN --"
        run_iptables -t nat -S "$HOTSPOT_ACCESS_NAT_CHAIN" 2>/dev/null || true
        echo "-- $HOTSPOT_ACCESS_FWD_CHAIN --"
        run_iptables -S "$HOTSPOT_ACCESS_FWD_CHAIN" 2>/dev/null || true
    fi
    echo

    echo "== TUN =="
    echo "detected=${dev:-none}"
    if [ -n "$dev" ]; then
        ip -d addr show dev "$dev" 2>/dev/null
        ip -4 route show table main dev "$dev" 2>/dev/null
        rp_file="$SYSCTL_ROOT/net/ipv4/conf/$dev/rp_filter"
        [ -r "$rp_file" ] && echo "rp_filter=$(cat "$rp_file" 2>/dev/null)"
    fi
    [ -r "$SYSCTL_ROOT/net/ipv4/ip_forward" ] && echo "ip_forward=$(cat "$SYSCTL_ROOT/net/ipv4/ip_forward" 2>/dev/null)"
    echo

    echo "== Connectivity probes =="
    diagnostic_targets | while IFS='|' read -r label target; do
        [ -n "$target" ] || continue
        if ping -c 1 -W 2 "$target" >/dev/null 2>&1; then
            echo "$label=OK target=$target"
        else
            echo "$label=FAIL target=$target"
        fi
        if [ "$label" = "easytier" ] && [ -n "$dev" ]; then
            if ping -I "$dev" -c 1 -W 2 "$target" >/dev/null 2>&1; then
                echo "${label}_forced_tun=OK iface=$dev target=$target"
            else
                echo "${label}_forced_tun=FAIL iface=$dev target=$target"
            fi
        fi
    done
    echo

    echo "== EasyTier node =="
    if [ -x "$CLI" ] && [ -n "$pid" ]; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 6 "$CLI" --rpc-portal "$portal" node 2>&1
        else
            "$CLI" --rpc-portal "$portal" node 2>&1
        fi
    else
        echo "EasyTier core is not running"
    fi
    echo
    echo "== EasyTier routes =="
    if [ -x "$CLI" ] && [ -n "$pid" ]; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 6 "$CLI" --rpc-portal "$portal" route list 2>&1
        else
            "$CLI" --rpc-portal "$portal" route list 2>&1
        fi
    fi
    echo

    echo "== TierNest log tail =="
    tail -n 180 "$MODULE_LOG" 2>/dev/null
    echo
    echo "== Network watcher tail =="
    tail -n 220 "$NETWORK_LOG" 2>/dev/null
    echo
    echo "== Transport history tail =="
    tail -n 160 "$TRANSPORT_LOG" 2>/dev/null
    echo
    echo "== Hotspot outbound-access tail =="
    tail -n 160 "$HOTSPOT_LOG" 2>/dev/null
    echo
    echo "== EasyTier important events =="
    grep -Ei 'warn|error|panic|fail|disconnect|closed|timeout|route' "$CORE_LOG" 2>/dev/null | tail -n 160
} 2>&1 | redact_sensitive > "$TMP_OUT"

mv "$TMP_OUT" "$OUT"
chmod 600 "$OUT" 2>/dev/null

# Keep only the newest five private diagnostic reports.
kept=0
ls -1t "$LOGDIR"/diagnostics-*.txt 2>/dev/null | while IFS= read -r old; do
    kept=$((kept + 1))
    [ "$kept" -le 5 ] || rm "$old" 2>/dev/null || true
done

echo "$OUT"

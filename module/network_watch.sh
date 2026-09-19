#!/system/bin/sh

MODDIR=${0%/*}
. "$MODDIR/common.sh"

workers_blocked && exit 0

watch_pid_matches() {
    candidate=$1
    [ -n "$candidate" ] && [ -r "/proc/$candidate/cmdline" ] || return 1
    command_line=$(tr '\000' ' ' < "/proc/$candidate/cmdline" 2>/dev/null)
    case "$command_line" in
        *"$MODDIR/network_watch.sh"*) return 0 ;;
    esac
    return 1
}

if ! mkdir "$NETWORK_WATCH_LOCK_DIR" 2>/dev/null; then
    # Give a concurrent winner time to publish its identity.
    sleep 1
    existing=""
    [ -r "$NETWORK_WATCH_PID_FILE" ] && existing=$(cat "$NETWORK_WATCH_PID_FILE" 2>/dev/null)
    if [ "$existing" != "$$" ] && watch_pid_matches "$existing"; then
        exit 0
    fi
    rmdir "$NETWORK_WATCH_LOCK_DIR" 2>/dev/null || exit 0
    mkdir "$NETWORK_WATCH_LOCK_DIR" 2>/dev/null || exit 0
fi

existing=""
[ -r "$NETWORK_WATCH_PID_FILE" ] && existing=$(cat "$NETWORK_WATCH_PID_FILE" 2>/dev/null)
if [ "$existing" != "$$" ] && watch_pid_matches "$existing"; then
    rmdir "$NETWORK_WATCH_LOCK_DIR" 2>/dev/null
    exit 0
fi
echo $$ > "$NETWORK_WATCH_PID_FILE"

cleanup_watch_files() {
    rm "$NETWORK_WATCH_PID_FILE" 2>/dev/null || true
    rmdir "$NETWORK_WATCH_LOCK_DIR" 2>/dev/null || true
}

finish_watch() {
    exit 0
}
trap finish_watch TERM INT HUP
trap cleanup_watch_files EXIT

ping_result() {
    label=$1
    target=$2
    if ping -c 1 -W 2 "$target" >/dev/null 2>&1; then
        echo "$label=OK target=$target"
    else
        echo "$label=FAIL target=$target"
    fi
}

ping_interface_result() {
    label=$1
    iface=$2
    target=$3
    if [ -n "$iface" ] && ping -I "$iface" -c 1 -W 2 "$target" >/dev/null 2>&1; then
        echo "$label=OK iface=$iface target=$target"
    else
        echo "$label=FAIL iface=${iface:-none} target=$target"
    fi
}

compact_vpn_state() {
    if command -v dumpsys >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            timeout 5 dumpsys connectivity 2>/dev/null
        else
            dumpsys connectivity 2>/dev/null
        fi | grep -Ei 'TRANSPORT_VPN|VpnNetworkAgent|VPN.*CONNECTED|type: VPN' | head -n 80
    fi
}

network_signature() {
    {
        echo "underlay=$(underlay_signature)"
        echo "app_vpn=$(easytier_app_vpn_active && echo active || echo inactive)"
        ip -4 rule show 2>/dev/null
        ip -4 route show table "$ROUTE_TABLE" 2>/dev/null
        diagnostic_targets | while IFS='|' read -r label target; do
            [ -n "$target" ] || continue
            echo "target=$label:$target"
            ip -4 route get "$target" 2>/dev/null
        done
        ip -o link show 2>/dev/null
    } | cksum 2>/dev/null | awk '{print $1":"$2}'
}

write_snapshot() {
    reason=$1
    rotate_log "$NETWORK_LOG" 4194304
    dev=$(find_tun_device 2>/dev/null)
    pid=$(core_pid 2>/dev/null)
    portal=$(get_rpc_portal)
    capture_transport_endpoints "$reason" "$pid" >/dev/null 2>&1 || true
    {
        echo
        echo "================================================================"
        echo "TierNest automatic network snapshot"
        echo "time=$(now)"
        echo "reason=$reason"
        echo "module_version=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null)"
        echo "android_release=$(getprop ro.build.version.release 2>/dev/null)"
        echo "android_sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
        echo "framework=$(framework_name)"
        echo "core_pid=${pid:-stopped}"
        echo "tun=${dev:-not-found}"
        echo "config_hostname=$(get_toml_string hostname)"
        echo "config_ipv4=$(get_toml_string ipv4)"
        echo "config_network=$(get_toml_string network_name)"
        configured_dev=$(get_toml_string dev_name 2>/dev/null)
        [ -n "$configured_dev" ] || configured_dev=auto-tunX
        echo "config_dev_name=$configured_dev"
        echo "config_enable_kcp_proxy=$(get_toml_bool enable_kcp_proxy false)"
        echo "config_use_smoltcp=$(get_toml_bool use_smoltcp false)"
        echo "tcp_compatibility=$(tcp_compatibility_state)"
        echo "route_table=$ROUTE_TABLE"
        echo "underlay=$(underlay_signature)"
        echo "rpc_state=$(easytier_rpc_state)"
        echo "live_transport_endpoint_count=$(live_transport_endpoint_count)"
        echo "easytier_app_vpn=$(easytier_app_vpn_active && echo active || echo inactive)"
        print_supervision_status
        echo
        echo "== IPv4 policy rules =="
        ip -4 rule show 2>&1
        echo
        echo "== TierNest route table =="
        ip -4 route show table "$ROUTE_TABLE" 2>&1
        echo
        echo "== Route decisions =="
        diagnostic_targets | while IFS='|' read -r label target; do
            [ -n "$target" ] || continue
            echo "-- $label $target --"
            ip -4 route get "$target" 2>&1
        done
        echo
        echo "== IPv4 addresses =="
        ip -o -4 addr show 2>&1
        echo
        echo "== Link interfaces =="
        ip -o link show 2>&1
        echo
        echo "== TUN details =="
        if [ -n "$dev" ]; then
            ip -d addr show dev "$dev" 2>&1
            ip -4 route show table main dev "$dev" 2>&1
        else
            echo "EasyTier TUN not found"
        fi
        echo
        echo "== Android VPN signals =="
        compact_vpn_state
        echo
        echo "== Connectivity probes =="
        diagnostic_targets | while IFS='|' read -r label target; do
            [ -n "$target" ] || continue
            ping_result "$label" "$target"
            [ "$label" = "easytier" ] && ping_interface_result "${label}_forced_tun" "$dev" "$target"
        done
        tcp_probe_result tcp_health "$HEALTH_TCP_TARGET" "$HEALTH_TCP_PORT"
        echo
        echo "== EasyTier transport endpoints =="
        cat "$TRANSPORT_ENDPOINTS_FILE" 2>/dev/null || echo "Transport endpoint snapshot unavailable"
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
        echo "================================================================"
    } >> "$NETWORK_LOG" 2>&1
}

last_signature=""
last_snapshot=0
sleep 5
workers_blocked && exit 0
write_snapshot startup
last_signature=$(network_signature)
last_snapshot=$(date +%s)

while true; do
    workers_blocked && exit 0
    sleep "$NETWORK_WATCH_INTERVAL"
    workers_blocked && exit 0
    ensure_daemon_running || true
    signature=$(network_signature)
    now_epoch=$(date +%s)
    case "$now_epoch" in *[!0-9]*|'') now_epoch=0;; esac
    case "$last_snapshot" in *[!0-9]*|'') last_snapshot=0;; esac

    if [ "$signature" != "$last_signature" ]; then
        write_snapshot network-state-changed
        last_signature=$signature
        last_snapshot=$now_epoch
    elif [ $((now_epoch - last_snapshot)) -ge "$NETWORK_SNAPSHOT_INTERVAL" ]; then
        write_snapshot "periodic-${NETWORK_SNAPSHOT_INTERVAL}s"
        last_snapshot=$now_epoch
    fi
done

#!/system/bin/sh

# Call mutations through service_with_lock. The lock also serializes the home
# monitor with WebUI actions; a manual stop always survives later auto checks.
service_with_lock() { runtime_with_lock "$RUNDIR/service.lock" 45 "$@"; }

stop_normal_workers() (
    # The caller publishes a stop/pause marker before terminating writers.
    stop_script_tree "$NETWORK_WATCH_PID_FILE" network_watch.sh || exit 1
    stop_script_tree "$DAEMON_PID_FILE" tiernestd.sh || exit 1
    # A worker killed during firewall sync may leave this ownerless lock behind.
    # All control writers hold the service lock, and normal workers are now gone.
    rmdir "$TUN_FIREWALL_LOCK_DIR" 2>/dev/null || true
    cleanup_hotspot_access
    cleanup_tun_firewall_guard
    legacy_hotspot_artifacts_present && cleanup_hotspot_forwarding
    stop_core
    cleanup_route_guard
    rm -f "$DAEMON_HEARTBEAT_FILE" "$RECOVERY_PHASE_FILE"
    rm -f "$START_LOCK/pid"
    rmdir "$DAEMON_LOCK_DIR" "$NETWORK_WATCH_LOCK_DIR" "$START_LOCK" 2>/dev/null || true
    ! core_running
)

start_normal_workers() (
    workers_blocked && exit 1
    start_core || exit 1
    workers_blocked && exit 1
    sync_route_guard
    sync_tun_firewall_guard || true
    sync_hotspot_access || true
    ensure_daemon_running
)

home_ipv4_valid() (
    case "$1" in *[!0-9.]*|'') exit 1;; esac
    normalize_ipv4_cidr "$1/32" >/dev/null 2>&1
)

home_record_valid() (
    [ "$#" = 5 ] || exit 1
    case "$1" in wlan[0-9]*) ;; *) exit 1;; esac
    case "$1" in *[!a-zA-Z0-9_]*) exit 1;; esac
    home_ipv4_valid "$2" || exit 1
    home_ipv4_valid "$4" || exit 1
    printf '%s\n' "$3" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || exit 1
    case "$5" in *[!0-9]*|'') exit 1;; esac
    [ "$5" -ge 1 ] && [ "$5" -le 65535 ]
)

home_settings_valid() (
    while IFS='|' read -r hi hg hm ht hp extra; do
        [ -z "$extra" ] && home_record_valid "$hi" "$hg" "$hm" "$ht" "$hp" && exit 0
    done <<RECORDS
$(home_network_records)
RECORDS
    exit 1
)

home_route_gateway() (
    # Force the physical interface, bypassing the phone's own overlay and VPN.
    ip -4 route get "$2" oif "$1" 2>/dev/null | awk -v iface="$1" '
        $1 != "local" && $1 != "unreachable" {
            via=""; dev=""; for(i=1;i<NF;i++) { if($i=="via") via=$(i+1); if($i=="dev") dev=$(i+1) }
            if(dev==iface && via!="") { print via; exit }
        }'
)

home_gateway_mac() {
    ip neigh show to "$2" dev "$1" 2>/dev/null | awk '
        !/FAILED|INCOMPLETE/ { for(i=1;i<NF;i++) if($i=="lladdr") { print tolower($(i+1)); exit } }'
}

home_probe() {
    # Any HTTP response proves connectivity; redirects are deliberately not followed.
    command -v curl >/dev/null 2>&1 || return 1
    curl --interface "$1" --noproxy '*' --connect-timeout 2 --max-time 3 \
        -s -o /dev/null "http://$2:$3/" >/dev/null 2>&1
}

home_event_supported() {
    [ -x "$HOME_EVENT_BIN" ] && "$HOME_EVENT_BIN" --check >/dev/null 2>&1
}

# Print the matching network ID. 0 = verified proxy; 1 = no known network;
# 2 = known gateway but failed probe. A different failed gateway resumes at once.
home_network_check() (
    failed_id=''
    while IFS='|' read -r hi hg hm ht hp extra; do
        [ -z "$extra" ] && home_record_valid "$hi" "$hg" "$hm" "$ht" "$hp" || continue
        [ "$(cat "${TIERNEST_SYS_NET_ROOT:-/sys/class/net}/$hi/carrier" 2>/dev/null)" = 1 ] || continue
        [ "$(home_route_gateway "$hi" "$ht")" = "$hg" ] || continue
        observed_mac=$(home_gateway_mac "$hi" "$hg")
        if [ "$(home_detection_mode)" = event ]; then
            # Resolve an empty neighbor cache only after a network event. This
            # identifies the router; it does not probe the remote overlay.
            if [ -z "$observed_mac" ]; then
                ping -I "$hi" -c 1 -W 1 "$hg" >/dev/null 2>&1 || true
                observed_mac=$(home_gateway_mac "$hi" "$hg")
            fi
            [ "$observed_mac" = "$hm" ] || continue
            home_network_id "$hi" "$hg" "$hm"
            exit 0
        fi
        [ -z "$observed_mac" ] || [ "$observed_mac" = "$hm" ] || continue
        matched_id=$(home_network_id "$hi" "$hg" "$hm")
        if ! home_probe "$hi" "$ht" "$hp"; then failed_id=$matched_id; continue; fi
        [ "$(home_gateway_mac "$hi" "$hg")" = "$hm" ] || continue
        printf '%s\n' "$matched_id"
        exit 0
    done <<RECORDS
$(home_network_records)
RECORDS
    if [ -n "$failed_id" ]; then printf '%s\n' "$failed_id"; exit 2; fi
    exit 1
)

# Save a complete, serialized list. Only an explicitly saved/deleted record is
# changed; connecting to a new network never overwrites another saved router.
home_save_record() (
    new_id=$(home_network_id "$1" "$2" "$3")
    old_records=$(home_network_records)
    umask 077
    {
        echo '# TierNest trusted proxy networks v2'
        printf '%s\n' "$old_records" | awk -F '|' -v id="$new_id" '
            NF {mac=$3; gsub(/:/,"",mac); if($1 "-" $2 "-" mac != id) print "network=" $0}'
        printf 'network=%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5"
    } > "$HOME_NETWORK_FILE.tmp" || exit 1
    mv "$HOME_NETWORK_FILE.tmp" "$HOME_NETWORK_FILE"
)

home_forget_unlocked() (
    forget_id=$1
    case "$forget_id" in *[!a-zA-Z0-9_.-]*|'') exit 2;; esac
    old_records=$(home_network_records)
    kept_records=$(printf '%s\n' "$old_records" | awk -F '|' -v id="$forget_id" '
        NF {mac=$3; gsub(/:/,"",mac); if($1 "-" $2 "-" mac != id) print}')
    [ "$kept_records" != "$old_records" ] || { echo '该网络记录已不存在，请刷新后重试。' >&2; exit 1; }
    umask 077
    {
        echo '# TierNest trusted proxy networks v2'
        printf '%s\n' "$kept_records" | awk 'NF {print "network=" $0}'
    } > "$HOME_NETWORK_FILE.tmp" || exit 1
    mv "$HOME_NETWORK_FILE.tmp" "$HOME_NETWORK_FILE" || exit 1
    rm -f "$HOME_FAILURES_FILE"
    if ! home_settings_valid; then
        # No automatic detection is needed after removing the last record.
        set_service_mode_unlocked manual || exit 1
    elif [ "$(service_mode)" = auto ] && ! service_user_blocked; then
        auto_reconcile_unlocked || exit 1
    fi
    echo '已移除此网络。'
)

home_learn_unlocked() (
    ht=$1; hp=${2:-80}
    home_ipv4_valid "$ht" || { echo '请填写经当前路由器可访问的虚拟 IPv4 地址。' >&2; exit 2; }
    case "$hp" in *[!0-9]*|'') exit 2;; esac
    [ "$hp" -ge 1 ] && [ "$hp" -le 65535 ] || exit 2
    for hi in $(ip -o -4 addr show 2>/dev/null | awk '$2 ~ /^wlan[0-9]+$/ {print $2}' | sort -u); do
        [ "$(cat "${TIERNEST_SYS_NET_ROOT:-/sys/class/net}/$hi/carrier" 2>/dev/null)" = 1 ] || continue
        hg=$(home_route_gateway "$hi" "$ht")
        home_ipv4_valid "$hg" || continue
        home_probe "$hi" "$ht" "$hp" || continue
        hm=$(home_gateway_mac "$hi" "$hg")
        printf '%s\n' "$hm" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' || continue
        home_save_record "$hi" "$hg" "$hm" "$ht" "$hp" || exit 1
        rm -f "$HOME_FAILURES_FILE"
        echo '已保存当前可代理的 Wi-Fi，其他网络记录已保留。'
        if [ "$(service_mode)" = auto ] && ! service_user_blocked; then auto_reconcile_unlocked; fi
        exit $?
    done
    echo '无法验证此网络：请连接路由器或随身 Wi-Fi，并填写经它可访问的虚拟 IP 和 HTTP 端口。已有记录未修改。' >&2
    exit 1
)

auto_reconcile_unlocked() (
    service_user_blocked && exit 0
    [ "$(service_mode)" = auto ] || exit 0
    home_result=0
    home_match=$(home_network_check) || home_result=$?
    if [ "$home_result" = 0 ]; then
        rm -f "$HOME_FAILURES_FILE"
        if [ ! -f "$HOME_PAUSED_FILE" ]; then
            printf '%s\n' "$home_match" > "$HOME_PAUSED_FILE" || exit 1
            stop_normal_workers || { rm -f "$HOME_PAUSED_FILE"; exit 1; }
            log_msg "Trusted network matched ($(home_detection_mode)); core and normal monitoring paused"
            set_description '已连接可信网络 | 手机核心待机'
        elif [ "$(cat "$HOME_PAUSED_FILE" 2>/dev/null)" != "$home_match" ]; then
            printf '%s\n' "$home_match" > "$HOME_PAUSED_FILE" || exit 1
        fi
    else
        # A changed Wi-Fi/gateway resumes immediately. Two failed probes on the
        # same gateway avoid a transient packet loss toggling the core.
        if [ "$home_result" = 2 ] && [ -f "$HOME_PAUSED_FILE" ] \
            && [ "$(cat "$HOME_PAUSED_FILE" 2>/dev/null)" = "$home_match" ]; then
            failures=$(cat "$HOME_FAILURES_FILE" 2>/dev/null || true)
            case "$failures" in *[!0-9]*|'') failures=0;; esac
            failures=$((failures + 1))
            echo "$failures" > "$HOME_FAILURES_FILE"
            [ "$failures" -ge 2 ] || exit 0
        fi
        if [ -f "$HOME_PAUSED_FILE" ]; then
            rm -f "$HOME_PAUSED_FILE" "$HOME_FAILURES_FILE"
            log_msg 'Trusted router proxy unavailable or left; resuming normal service'
        fi
        workers_blocked || ensure_daemon_running
    fi
)

ensure_home_watch_running() (
    service_user_blocked && exit 0
    [ "$(service_mode)" = auto ] || exit 0
    if managed_script_pid "$HOME_WATCH_PID_FILE" home_watch.sh >/dev/null; then exit 0; fi
    rm -f "$HOME_WATCH_READY_FILE"
    launch_detached "$MODDIR/home_watch.sh" >> "$MODULE_LOG" 2>&1 </dev/null &
    wait_for_script_start "$HOME_WATCH_PID_FILE" home_watch.sh || exit 1
    for ready_attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
        ready_pid=$(managed_script_pid "$HOME_WATCH_PID_FILE" home_watch.sh) || exit 1
        [ "$(cat "$HOME_WATCH_READY_FILE" 2>/dev/null)" = "$ready_pid" ] && exit 0
        sleep 0.1
    done
    exit 1
)

home_monitor_failed_unlocked() {
    echo '自动检测未运行，请重新应用设置或切换定时检测。' > "$HOME_WATCH_ERROR_FILE"
    service_user_blocked && return 0
    [ "$(service_mode)" = auto ] || return 0
    rm -f "$HOME_PAUSED_FILE" "$HOME_FAILURES_FILE"
    log_msg 'Automatic network monitor unavailable; resuming the core instead of leaving it paused'
    workers_blocked || ensure_daemon_running
}

set_home_detection_unlocked() (
    detection=$1; interval=$2
    case "$detection" in poll|event) ;; *) echo '未知的检测方式。' >&2; exit 2;; esac
    home_interval_valid "$interval" || { echo '检测间隔须为正整数秒（最大 2147483647）。' >&2; exit 2; }
    if [ "$detection" = event ] && ! home_event_supported; then
        echo '此设备无法启用 Wi-Fi 事件监听，请使用定时检测。' >&2
        exit 1
    fi
    umask 077
    previous="$RUNDIR/.home-detection.previous"
    rm -f "$previous"
    if [ -f "$HOME_DETECTION_FILE" ]; then cp -p "$HOME_DETECTION_FILE" "$previous" || exit 1; fi
    printf 'mode=%s\ninterval=%s\n' "$detection" "$interval" > "$HOME_DETECTION_FILE.tmp" || exit 1
    stop_script_tree "$HOME_WATCH_PID_FILE" home_watch.sh || { rm -f "$HOME_DETECTION_FILE.tmp" "$previous"; exit 1; }
    rmdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null || true
    if ! mv "$HOME_DETECTION_FILE.tmp" "$HOME_DETECTION_FILE"; then
        ensure_home_watch_running || true
        rm -f "$previous"
        exit 1
    fi
    rm -f "$HOME_WATCH_ERROR_FILE" "$HOME_FAILURES_FILE"
    if [ "$(service_mode)" = auto ] && ! service_user_blocked; then
        if ! ensure_home_watch_running; then
            stop_script_tree "$HOME_WATCH_PID_FILE" home_watch.sh || true
            rmdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null || true
            if [ -f "$previous" ]; then mv "$previous" "$HOME_DETECTION_FILE"; else rm -f "$HOME_DETECTION_FILE"; fi
            ensure_home_watch_running || home_monitor_failed_unlocked
            echo '检测设置未应用，已恢复原设置，请查看日志。' >&2
            exit 1
        fi
        auto_reconcile_unlocked || exit 1
    fi
    rm -f "$previous"
    echo '自动检测设置已保存。'
)

start_service_unlocked() {
    [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] || { echo '模块已禁用或待卸载。' >&2; return 1; }
    rm -f "$MANUAL_STOP_FILE"
    if [ "$(service_mode)" = auto ]; then
        ensure_home_watch_running || { home_monitor_failed_unlocked; return 1; }
        auto_reconcile_unlocked || return 1
        [ -f "$HOME_PAUSED_FILE" ] && return 0
    else
        rm -f "$HOME_PAUSED_FILE"
    fi
    start_normal_workers
}

stop_service_unlocked() {
    touch "$MANUAL_STOP_FILE" || return 1
    stop_script_tree "$HOME_WATCH_PID_FILE" home_watch.sh || return 1
    stop_normal_workers || return 1
    rm -f "$HOME_PAUSED_FILE" "$HOME_FAILURES_FILE" "$HOME_WATCH_READY_FILE" "$HOME_WATCH_ERROR_FILE"
    rmdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null || true
    set_description '已手动停止 | 全部后台已关闭'
}

restart_service_unlocked() { stop_service_unlocked && start_service_unlocked; }
start_service() { service_with_lock start_service_unlocked; }
stop_service() { service_with_lock stop_service_unlocked; }
restart_service() { service_with_lock restart_service_unlocked; }

set_service_mode_unlocked() (
    case "$1" in manual|auto) ;; *) exit 2;; esac
    if [ "$1" = auto ]; then
        home_settings_valid || { echo '请先验证并保存一个可代理的 Wi-Fi。' >&2; exit 1; }
        command -v curl >/dev/null 2>&1 || { echo '系统缺少 curl，无法验证路由器代理。' >&2; exit 1; }
        if [ "$(home_detection_mode)" = event ]; then
            home_event_supported || { echo '此设备无法启用 Wi-Fi 事件监听，请切换定时检测。' >&2; exit 1; }
        fi
    fi
    umask 077
    printf '%s\n' "$1" > "$SERVICE_MODE_FILE.tmp" && mv "$SERVICE_MODE_FILE.tmp" "$SERVICE_MODE_FILE" || exit 1
    if [ "$1" = manual ]; then
        stop_script_tree "$HOME_WATCH_PID_FILE" home_watch.sh || exit 1
        rmdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null || true
        rm -f "$HOME_PAUSED_FILE" "$HOME_FAILURES_FILE" "$HOME_WATCH_READY_FILE" "$HOME_WATCH_ERROR_FILE"
    fi
    # Selecting a mode never cancels a prior explicit stop.
    service_user_blocked && exit 0
    start_service_unlocked
)

boot_service_unlocked() {
    service_user_blocked && return 0
    if [ "$(service_mode)" = auto ]; then
        # Recheck the physical network after every reboot; run/ is persistent.
        managed_script_pid "$HOME_WATCH_PID_FILE" home_watch.sh >/dev/null && return 0
        rm -f "$HOME_PAUSED_FILE" "$HOME_FAILURES_FILE"
        ensure_home_watch_running || { home_monitor_failed_unlocked; return 1; }
    else
        rm -f "$HOME_PAUSED_FILE"
        ensure_daemon_running boot
    fi
}

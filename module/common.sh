#!/system/bin/sh

# Shared runtime helpers for TierNest.
MODDIR=${MODDIR:-${0%/*}}
BINDIR="$MODDIR/bin"
CONFIG_DIR="$MODDIR/config"
CONFIG_FILE="$CONFIG_DIR/config.toml"
NODE_LOCATIONS_FILE="$CONFIG_DIR/node-locations.conf"
COMMAND_ARGS="$CONFIG_DIR/command_args"
SETTINGS_FILE="$MODDIR/settings.conf"
CORE="$BINDIR/easytier-core"
CLI="$BINDIR/easytier-cli"
RUNDIR="$MODDIR/run"
LOGDIR="$MODDIR/logs"
CORE_LOG="$LOGDIR/easytier.log"
MODULE_LOG="$LOGDIR/tiernest.log"
NETWORK_LOG="$LOGDIR/network-watch.log"
HOTSPOT_LOG="$LOGDIR/hotspot.log"
TRANSPORT_LOG="$LOGDIR/transport.log"
PID_FILE="$RUNDIR/easytier.pid"
DAEMON_PID_FILE="$RUNDIR/tiernestd.pid"
NETWORK_WATCH_PID_FILE="$RUNDIR/network-watch.pid"
DAEMON_LOCK_DIR="$RUNDIR/tiernestd.lock"
NETWORK_WATCH_LOCK_DIR="$RUNDIR/network-watch.lock"
MANUAL_STOP_FILE="$CONFIG_DIR/manual_stop"
SERVICE_MODE_FILE="$CONFIG_DIR/service-mode.state"
HOME_NETWORK_FILE="$CONFIG_DIR/home-network.conf"
HOME_DETECTION_FILE="$CONFIG_DIR/home-detection.conf"
HOME_EVENT_BIN="$BINDIR/tiernest-netwatch"
HOME_WATCH_READY_FILE="$RUNDIR/home-watch.ready"
HOME_WATCH_ERROR_FILE="$RUNDIR/home-watch.error"
HOME_PAUSED_FILE="$RUNDIR/home-paused"
HOME_FAILURES_FILE="$RUNDIR/home-probe-failures"
HOME_WATCH_PID_FILE="$RUNDIR/home-watch.pid"
HOME_WATCH_LOCK_DIR="$RUNDIR/home-watch.lock"
APPLIED_ROUTES_FILE="$RUNDIR/applied-routes.txt"
DISCOVERED_ROUTES_FILE="$RUNDIR/discovered-routes.txt"
ROUTE_DISCOVERY_STAMP_FILE="$RUNDIR/route-discovery-stamp"
RULE_PREF_FILE="$RUNDIR/rule-pref"
ROUTE_TABLE_SELECTION_FILE="$RUNDIR/route-table-selection"
ROUTE_MODE_ACTIVE_FILE="$RUNDIR/route-mode-active"
ROUTE_STRATEGY_FILE="$CONFIG_DIR/route-strategy.state"
ROUTE_MODE_RUNTIME_OVERRIDE_FILE="$RUNDIR/route-mode-runtime-override"
ROUTE_MODE_LAST_SWITCH_FILE="$RUNDIR/route-mode-last-switch"
UPSTREAM_MAIN_RULE_FILE="$RUNDIR/upstream-main-rule-pref"
TARGET_MAIN_RULES_FILE="$RUNDIR/target-main-rules.txt"
START_LOCK="$RUNDIR/start.lock"
CORE_STARTED_AT_FILE="$RUNDIR/core-started-at"
VPN_RESTART_COUNT_FILE="$RUNDIR/vpn-restart-count"
UNDERLAY_RESTART_COUNT_FILE="$RUNDIR/underlay-restart-count"
RPC_RESTART_COUNT_FILE="$RUNDIR/rpc-restart-count"
LAST_UNDERLAY_CHANGE_FILE="$RUNDIR/last-underlay-change"
LAST_APP_CONFLICT_FILE="$RUNDIR/last-easytier-app-conflict"
ROUTE_SYNC_COUNT_FILE="$RUNDIR/route-sync-count"
LAST_VPN_CHANGE_FILE="$RUNDIR/last-vpn-change"
CPU_SAMPLE_FILE="$RUNDIR/cpu-sample"
HEALTH_RESTART_COUNT_FILE="$RUNDIR/health-restart-count"
LAST_HEALTH_EVENT_FILE="$RUNDIR/last-health-event"
LAST_RECOVERY_EVENT_FILE="$RUNDIR/last-recovery-event"
RECOVERY_PHASE_FILE="$RUNDIR/recovery-phase"
DAEMON_HEARTBEAT_FILE="$RUNDIR/daemon-heartbeat"
TRANSPORT_ENDPOINTS_FILE="$RUNDIR/transport-endpoints.txt"
TRANSPORT_ENDPOINTS_SIGNATURE_FILE="$RUNDIR/transport-endpoints.signature"
LOCAL_ROUTE_OVERRIDES_FILE="$RUNDIR/local-route-overrides.txt"
EXPECTED_ROUTE_SPECS_FILE="$RUNDIR/routes.expected-specs"
ANDROID_ROUTE_SPECS_FILE="$RUNDIR/android-route-specs.txt"
ANDROID_ROUTE_TABLES_FILE="$RUNDIR/android-route-tables.txt"
PROC_ROOT=${TIERNEST_PROC_ROOT:-/proc}
HOTSPOT_OVERRIDE_FILE="$CONFIG_DIR/hotspot-forwarding.state"
HOTSPOT_STATE_FILE="$RUNDIR/hotspot-state"
HOTSPOT_RULE_PREF_FILE="$RUNDIR/hotspot-rule-pref"
HOTSPOT_REAPPLY_COUNT_FILE="$RUNDIR/hotspot-reapply-count"
HOTSPOT_LAST_APPLY_FILE="$RUNDIR/hotspot-last-apply"
HOTSPOT_CONFLICT_FILE="$RUNDIR/hotspot-conflict"
HOTSPOT_SYSCTL_STATE_FILE="$RUNDIR/hotspot-sysctl-state"
HOTSPOT_IP_FORWARD_PREV_FILE="$RUNDIR/hotspot-ip-forward-prev"
HOTSPOT_ACCESS_OVERRIDE_FILE="$CONFIG_DIR/hotspot-client-access.state"
HOTSPOT_ACCESS_STATE_FILE="$RUNDIR/hotspot-access-state"
HOTSPOT_ACCESS_RULES_FILE="$RUNDIR/hotspot-access-rules.txt"
HOTSPOT_ACCESS_HOOKS_FILE="$RUNDIR/hotspot-access-hooks.txt"
HOTSPOT_ACCESS_TARGETS_FILE="$RUNDIR/hotspot-access-targets.txt"
HOTSPOT_ACCESS_LAST_APPLY_FILE="$RUNDIR/hotspot-access-last-apply"
HOTSPOT_ACCESS_REAPPLY_COUNT_FILE="$RUNDIR/hotspot-access-reapply-count"
HOTSPOT_ACCESS_ERROR_FILE="$RUNDIR/hotspot-access-error"
HOTSPOT_ACCESS_LOCK_DIR="$RUNDIR/hotspot-access.lock"
TUN_FIREWALL_STATE_FILE="$RUNDIR/tun-firewall-state"
TUN_FIREWALL_TARGETS_FILE="$RUNDIR/tun-firewall-targets.txt"
TUN_FIREWALL_ERROR_FILE="$RUNDIR/tun-firewall-error"
TUN_FIREWALL_LOCK_DIR="$RUNDIR/tun-firewall.lock"
SYSCTL_ROOT=${TIERNEST_SYSCTL_ROOT:-/proc/sys}

ROUTE_GUARD=1
ROUTE_STRATEGY_DEFAULT=official
ROUTE_MODE=auto
ROUTE_AUTO_SWITCH_ENABLED=1
ROUTE_AUTO_SWITCH_COOLDOWN=60
ROUTE_TABLE=20110
ROUTE_TABLE_FALLBACK=110
ROUTE_RULE_PRIORITY=9980
ROUTE_SYNC_INTERVAL=30
ROUTE_DISCOVERY_INTERVAL=60
WATCHDOG_INTERVAL=8
ALLOW_EXIT_ROUTES=0
PREFER_DIRECT_LOCAL_SUBNETS=1
SYNC_ANDROID_NETWORK_TABLES=0
MIGRATE_OLD_EASYTIER_CONFIG=1
DISABLE_OLD_EASYTIER_MODULE=1
AUTO_RESTART_ON_VPN_CHANGE=1
VPN_RESTART_DELAY=4
VPN_RESTART_COOLDOWN=20
AUTO_RESTART_ON_UNDERLAY_CHANGE=1
UNDERLAY_RESTART_DELAY=4
UNDERLAY_RESTART_COOLDOWN=30
RPC_HEALTH_ENABLED=1
RPC_HEALTH_INTERVAL=15
RPC_FAIL_THRESHOLD=2
RPC_RESTART_COOLDOWN=60
NETWORK_SNAPSHOT_INTERVAL=300
NETWORK_WATCH_INTERVAL=10
TRANSPORT_OBSERVER_ENABLED=1
TRANSPORT_ENDPOINT_LIMIT=64
HEALTH_CHECK_ENABLED=0
HEALTH_CHECK_INTERVAL=20
HEALTH_FAIL_THRESHOLD=2
HEALTH_STARTUP_GRACE=45
HEALTH_RESTART_COOLDOWN=90
HEALTH_EASYTIER_TARGET=
HEALTH_PROXY_TARGET=
HEALTH_TCP_TARGET=
HEALTH_TCP_PORT=80
HEALTH_INTERNET_TARGET=1.1.1.1
HOTSPOT_CLIENT_ACCESS_ENABLED=0
HOTSPOT_ACCESS_CHECK_INTERVAL=30
HOTSPOT_ACCESS_RULE_PRIORITY=9800
HOTSPOT_ACCESS_RULE_PRIORITY_MIN=9700
HOTSPOT_ACCESS_INTERFACE=auto
HOTSPOT_ACCESS_CIDR=auto
HOTSPOT_ACCESS_INCLUDE_USB=0
HOTSPOT_ACCESS_MAX_TARGETS=96
TUN_FIREWALL_GUARD=0

[ -r "$SETTINGS_FILE" ] && . "$SETTINGS_FILE"

case "$ROUTE_STRATEGY_DEFAULT" in official|legacy) ;; *) ROUTE_STRATEGY_DEFAULT=official;; esac
case "$ROUTE_MODE" in auto|upstream|target-main|dedicated) ;; *) ROUTE_MODE=auto;; esac
case "$ROUTE_AUTO_SWITCH_ENABLED" in 0|1) ;; *) ROUTE_AUTO_SWITCH_ENABLED=1;; esac
case "$ROUTE_AUTO_SWITCH_COOLDOWN" in *[!0-9]*|'') ROUTE_AUTO_SWITCH_COOLDOWN=60;; esac
case "$ROUTE_TABLE" in *[!0-9]*|'') ROUTE_TABLE=20110;; esac
case "$ROUTE_TABLE_FALLBACK" in *[!0-9]*|'') ROUTE_TABLE_FALLBACK=110;; esac
[ "$ROUTE_TABLE_FALLBACK" -ge 1 ] 2>/dev/null || ROUTE_TABLE_FALLBACK=110
[ "$ROUTE_TABLE_FALLBACK" -le 252 ] 2>/dev/null || ROUTE_TABLE_FALLBACK=110
case "$ROUTE_RULE_PRIORITY" in *[!0-9]*|'') ROUTE_RULE_PRIORITY=9980;; esac
case "$ROUTE_SYNC_INTERVAL" in *[!0-9]*|'') ROUTE_SYNC_INTERVAL=30;; esac
case "$ROUTE_DISCOVERY_INTERVAL" in *[!0-9]*|'') ROUTE_DISCOVERY_INTERVAL=60;; esac
case "$WATCHDOG_INTERVAL" in *[!0-9]*|'') WATCHDOG_INTERVAL=8;; esac
case "$VPN_RESTART_DELAY" in *[!0-9]*|'') VPN_RESTART_DELAY=4;; esac
case "$VPN_RESTART_COOLDOWN" in *[!0-9]*|'') VPN_RESTART_COOLDOWN=20;; esac
case "$AUTO_RESTART_ON_UNDERLAY_CHANGE" in 0|1) ;; *) AUTO_RESTART_ON_UNDERLAY_CHANGE=1;; esac
case "$UNDERLAY_RESTART_DELAY" in *[!0-9]*|'') UNDERLAY_RESTART_DELAY=4;; esac
case "$UNDERLAY_RESTART_COOLDOWN" in *[!0-9]*|'') UNDERLAY_RESTART_COOLDOWN=30;; esac
case "$RPC_HEALTH_ENABLED" in 0|1) ;; *) RPC_HEALTH_ENABLED=1;; esac
case "$RPC_HEALTH_INTERVAL" in *[!0-9]*|'') RPC_HEALTH_INTERVAL=15;; esac
case "$RPC_FAIL_THRESHOLD" in *[!0-9]*|'') RPC_FAIL_THRESHOLD=2;; esac
case "$RPC_RESTART_COOLDOWN" in *[!0-9]*|'') RPC_RESTART_COOLDOWN=60;; esac
case "$NETWORK_SNAPSHOT_INTERVAL" in *[!0-9]*|'') NETWORK_SNAPSHOT_INTERVAL=300;; esac
case "$NETWORK_WATCH_INTERVAL" in *[!0-9]*|'') NETWORK_WATCH_INTERVAL=10;; esac
case "$TRANSPORT_ENDPOINT_LIMIT" in *[!0-9]*|'') TRANSPORT_ENDPOINT_LIMIT=64;; esac
[ "$TRANSPORT_ENDPOINT_LIMIT" -gt 0 ] 2>/dev/null || TRANSPORT_ENDPOINT_LIMIT=64
[ "$TRANSPORT_ENDPOINT_LIMIT" -le 256 ] 2>/dev/null || TRANSPORT_ENDPOINT_LIMIT=256
case "$TRANSPORT_OBSERVER_ENABLED" in 0|1) ;; *) TRANSPORT_OBSERVER_ENABLED=1;; esac
case "$PREFER_DIRECT_LOCAL_SUBNETS" in 0|1) ;; *) PREFER_DIRECT_LOCAL_SUBNETS=1;; esac
case "$SYNC_ANDROID_NETWORK_TABLES" in 0|1) ;; *) SYNC_ANDROID_NETWORK_TABLES=0;; esac
case "$HEALTH_CHECK_INTERVAL" in *[!0-9]*|'') HEALTH_CHECK_INTERVAL=20;; esac
case "$HEALTH_FAIL_THRESHOLD" in *[!0-9]*|'') HEALTH_FAIL_THRESHOLD=2;; esac
case "$HEALTH_STARTUP_GRACE" in *[!0-9]*|'') HEALTH_STARTUP_GRACE=45;; esac
case "$HEALTH_RESTART_COOLDOWN" in *[!0-9]*|'') HEALTH_RESTART_COOLDOWN=90;; esac
case "$HEALTH_TCP_PORT" in *[!0-9]*|'') HEALTH_TCP_PORT=80;; esac
[ "$HEALTH_TCP_PORT" -ge 1 ] 2>/dev/null || HEALTH_TCP_PORT=80
[ "$HEALTH_TCP_PORT" -le 65535 ] 2>/dev/null || HEALTH_TCP_PORT=80
case "$HOTSPOT_CLIENT_ACCESS_ENABLED" in 0|1) ;; *) HOTSPOT_CLIENT_ACCESS_ENABLED=0;; esac
case "$HOTSPOT_ACCESS_CHECK_INTERVAL" in *[!0-9]*|'') HOTSPOT_ACCESS_CHECK_INTERVAL=30;; esac
[ "$HOTSPOT_ACCESS_CHECK_INTERVAL" -ge 15 ] 2>/dev/null || HOTSPOT_ACCESS_CHECK_INTERVAL=15
case "$HOTSPOT_ACCESS_RULE_PRIORITY" in *[!0-9]*|'') HOTSPOT_ACCESS_RULE_PRIORITY=9800;; esac
case "$HOTSPOT_ACCESS_RULE_PRIORITY_MIN" in *[!0-9]*|'') HOTSPOT_ACCESS_RULE_PRIORITY_MIN=9700;; esac
[ "$HOTSPOT_ACCESS_RULE_PRIORITY_MIN" -le "$HOTSPOT_ACCESS_RULE_PRIORITY" ] 2>/dev/null || HOTSPOT_ACCESS_RULE_PRIORITY_MIN=9700
case "$HOTSPOT_ACCESS_INCLUDE_USB" in 0|1) ;; *) HOTSPOT_ACCESS_INCLUDE_USB=0;; esac
case "$HOTSPOT_ACCESS_MAX_TARGETS" in *[!0-9]*|'') HOTSPOT_ACCESS_MAX_TARGETS=96;; esac
case "$TUN_FIREWALL_GUARD" in 0|1) ;; *) TUN_FIREWALL_GUARD=0;; esac
[ "$HOTSPOT_ACCESS_MAX_TARGETS" -ge 1 ] 2>/dev/null || HOTSPOT_ACCESS_MAX_TARGETS=96
[ "$HOTSPOT_ACCESS_MAX_TARGETS" -le 128 ] 2>/dev/null || HOTSPOT_ACCESS_MAX_TARGETS=128

mkdir -p "$RUNDIR" "$LOGDIR" "$CONFIG_DIR" 2>/dev/null

now() {
    date '+%Y-%m-%d %H:%M:%S'
}

rotate_log() {
    file=$1
    max_bytes=${2:-1048576}
    [ -f "$file" ] || return 0
    size=$(wc -c < "$file" 2>/dev/null)
    case "$size" in *[!0-9]*|'') size=0;; esac
    if [ "$size" -gt "$max_bytes" ]; then
        mv "$file" "$file.1" 2>/dev/null
        : > "$file"
    fi
}

log_msg() {
    rotate_log "$MODULE_LOG" 1048576
    printf '%s %s\n' "$(now)" "$*" >> "$MODULE_LOG"
}


route_table_supported() {
    candidate=$1
    ip -4 route show table "$candidate" >/dev/null 2>&1
}

resolve_route_table() {
    requested=$1
    fallback=$2
    cached_requested=""
    cached_selected=""
    if [ -r "$ROUTE_TABLE_SELECTION_FILE" ]; then
        IFS='|' read cached_requested cached_selected < "$ROUTE_TABLE_SELECTION_FILE"
        if [ "$cached_requested" = "$requested" ] \
            && [ -n "$cached_selected" ] \
            && route_table_supported "$cached_selected"; then
            echo "$cached_selected"
            return 0
        fi
    fi

    if route_table_supported "$requested"; then
        selected=$requested
    else
        selected=""
        used_tables=$(ip -4 rule show 2>/dev/null | sed -n 's/.*lookup[[:space:]]\+\([0-9][0-9]*\).*/\1/p')
        candidate=$fallback
        while [ "$candidate" -le 252 ]; do
            if route_table_supported "$candidate" \
                && ! printf '%s\n' "$used_tables" | grep -qx "$candidate"; then
                selected=$candidate
                break
            fi
            candidate=$((candidate + 1))
        done
        [ -n "$selected" ] || selected=$fallback
        log_msg "Route table $requested unsupported by system ip tool; using fallback table=$selected"
    fi
    printf '%s|%s\n' "$requested" "$selected" > "$ROUTE_TABLE_SELECTION_FILE"
    echo "$selected"
}

REQUESTED_ROUTE_TABLE=$ROUTE_TABLE
ROUTE_TABLE=$(resolve_route_table "$REQUESTED_ROUTE_TABLE" "$ROUTE_TABLE_FALLBACK")


redact_sensitive() {
    sed -E \
        -e 's/(network_secret[[:space:]]*=[[:space:]]*)"[^"]*"/\1"<redacted>"/g' \
        -e "s/(network_secret[[:space:]]*=[[:space:]]*)'[^']*'/\\1'<redacted>'/g" \
        -e 's/("network_secret"[[:space:]]*:[[:space:]]*)"[^"]*"/\1"<redacted>"/g' \
        -e 's/(--network-secret(=|[[:space:]]+))[^[:space:]]+/\1<redacted>/g' \
        -e 's#(://)[^/@[:space:]]+@#\1<redacted>@#g'
}

is_ipv4_literal() {
    value=$1
    awk -v ip="$value" 'BEGIN {
        count=split(ip, part, ".")
        if (count != 4) exit 1
        for (i=1; i<=4; i++) {
            if (part[i] !~ /^[0-9]+$/ || part[i] < 0 || part[i] > 255) exit 1
        }
        exit 0
    }'
}

first_host_for_cidr() (
    normalized=$(normalize_ipv4_cidr "$1" 2>/dev/null) || exit 1
    awk -v cidr="$normalized" 'BEGIN {
        split(cidr, pair, "/")
        split(pair[1], octet, ".")
        prefix=pair[2] + 0
        value=octet[1]*16777216 + octet[2]*65536 + octet[3]*256 + octet[4]
        if (prefix < 31) value += 1
        a=int(value/16777216)%256
        b=int(value/65536)%256
        c=int(value/256)%256
        d=value%256
        printf "%d.%d.%d.%d\n", a, b, c, d
    }'
)

diagnostic_targets() {
    overlay=$HEALTH_EASYTIER_TARGET
    if ! is_ipv4_literal "$overlay" 2>/dev/null; then
        overlay=$(configured_ipv4_cidr 2>/dev/null)
        [ -n "$overlay" ] && overlay=$(first_host_for_cidr "$overlay" 2>/dev/null)
    fi
    if is_ipv4_literal "$overlay" 2>/dev/null; then
        echo "easytier|$overlay"
    fi

    if is_ipv4_literal "$HEALTH_PROXY_TARGET" 2>/dev/null \
        && [ "$HEALTH_PROXY_TARGET" != "$overlay" ]; then
        echo "proxy|$HEALTH_PROXY_TARGET"
    fi

    internet=$HEALTH_INTERNET_TARGET
    is_ipv4_literal "$internet" 2>/dev/null || internet=1.1.1.1
    if [ "$internet" != "$overlay" ] && [ "$internet" != "$HEALTH_PROXY_TARGET" ]; then
        echo "internet|$internet"
    fi
}

configured_peer_uris() {
    [ -r "$CONFIG_FILE" ] || return 0
    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*\[\[peer\]\][[:space:]]*$/ { in_peer=1; next }
        /^[[:space:]]*\[/ { in_peer=0 }
        in_peer && /^[[:space:]]*uri[[:space:]]*=/ {
            line=$0
            sub(/^[^=]*=[[:space:]]*/, "", line)
            sub(/[[:space:]]*#.*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (line ~ /^".*"$/) {
                sub(/^"/, "", line)
                sub(/"$/, "", line)
            }
            if (line != "") print line
        }
    ' "$CONFIG_FILE"
}

sanitize_endpoint_uri() {
    printf '%s\n' "$1" | sed -E \
        -e 's#(://)[^/@]+@#\1<redacted>@#' \
        -e 's#^([A-Za-z][A-Za-z0-9+.-]*://[^/?#]+).*#\1#'
}

core_transport_sockets() {
    transport_pid=$1
    proc_dir="$PROC_ROOT/$transport_pid"
    [ -d "$proc_dir/fd" ] || return 1

    inode_file="$RUNDIR/socket-inodes.$$.tmp"
    : > "$inode_file"
    for fd in "$proc_dir"/fd/*; do
        [ -L "$fd" ] || continue
        link=$(readlink "$fd" 2>/dev/null)
        case "$link" in
            socket:\[*\])
                inode=${link#socket:[}
                inode=${inode%]}
                case "$inode" in *[!0-9]*|'') ;; *) echo "$inode" >> "$inode_file" ;; esac
                ;;
        esac
    done
    sort -u "$inode_file" > "$inode_file.sorted" 2>/dev/null
    mv "$inode_file.sorted" "$inode_file" 2>/dev/null
    [ -s "$inode_file" ] || { rm "$inode_file" 2>/dev/null; return 1; }

    for protocol in tcp udp; do
        table="$proc_dir/net/$protocol"
        [ -r "$table" ] || continue
        awk -v proto="$protocol" '
            function h2d(hex,    i, digit, value) {
                hex=toupper(hex)
                value=0
                for (i=1; i<=length(hex); i++) {
                    digit=index("0123456789ABCDEF", substr(hex, i, 1)) - 1
                    if (digit < 0) return -1
                    value=value*16 + digit
                }
                return value
            }
            function ipv4(hex) {
                return h2d(substr(hex,7,2)) "." h2d(substr(hex,5,2)) "." h2d(substr(hex,3,2)) "." h2d(substr(hex,1,2))
            }
            NR==FNR { wanted[$1]=1; next }
            FNR>1 {
                inode=$10
                if (!(inode in wanted)) next
                split($3, remote, ":")
                if (remote[1] == "00000000" || remote[2] == "0000") next
                address=ipv4(remote[1])
                if (address ~ /^127\./ || address == "0.0.0.0") next
                port=h2d(remote[2])
                if (port <= 0) next
                print proto "|" address "|" port "|" $4 "|" inode
            }
        ' "$inode_file" "$table"
    done | sort -u

    rm "$inode_file" 2>/dev/null
}

capture_transport_endpoints() (
    reason=${1:-manual}
    transport_pid=${2:-}
    [ -n "$transport_pid" ] || transport_pid=$(core_pid 2>/dev/null || true)
    data_file="$RUNDIR/transport-endpoints.$$.data"
    output_file="$RUNDIR/transport-endpoints.$$.tmp"
    : > "$data_file"

    echo "schema=1" >> "$data_file"
    echo "ipv4_only=1" >> "$data_file"
    echo "endpoint_limit=$TRANSPORT_ENDPOINT_LIMIT" >> "$data_file"
    if [ "$TRANSPORT_OBSERVER_ENABLED" != "1" ]; then
        echo "status=disabled" >> "$data_file"
        transport_pid=""
    elif [ -n "$transport_pid" ] && [ -d "$PROC_ROOT/$transport_pid" ]; then
        echo "status=running" >> "$data_file"
        echo "pid=$transport_pid" >> "$data_file"
    else
        echo "status=stopped" >> "$data_file"
        transport_pid=""
    fi

    if [ "$TRANSPORT_OBSERVER_ENABLED" = "1" ]; then
        configured_peer_uris | while IFS= read -r uri; do
            [ -n "$uri" ] || continue
            echo "configured_peer=$(sanitize_endpoint_uri "$uri")"
        done >> "$data_file"
    fi

    if [ -n "$transport_pid" ]; then
        core_transport_sockets "$transport_pid" 2>/dev/null | head -n "$TRANSPORT_ENDPOINT_LIMIT" | while IFS='|' read -r protocol address port socket_state inode; do
            [ -n "$address" ] || continue
            route=$(ip -4 route get "$address" 2>/dev/null | head -n 1 | tr '\r\n' '  ')
            echo "active protocol=$protocol remote=$address:$port state=$socket_state inode=$inode route=${route:-unknown}"
        done >> "$data_file"
    fi

    signature=$(cksum < "$data_file" 2>/dev/null | awk '{print $1":"$2}')
    old_signature=""
    [ -r "$TRANSPORT_ENDPOINTS_SIGNATURE_FILE" ] && old_signature=$(cat "$TRANSPORT_ENDPOINTS_SIGNATURE_FILE" 2>/dev/null)
    {
        echo "TierNest transport endpoint snapshot"
        echo "observed_at=$(now)"
        echo "reason=$reason"
        echo "external_vpn=$(external_vpn_state 2>/dev/null || true)"
        cat "$data_file"
    } | redact_sensitive > "$output_file"
    mv "$output_file" "$TRANSPORT_ENDPOINTS_FILE"
    chmod 600 "$TRANSPORT_ENDPOINTS_FILE" 2>/dev/null
    echo "$signature" > "$TRANSPORT_ENDPOINTS_SIGNATURE_FILE"

    if [ "$signature" != "$old_signature" ]; then
        rotate_log "$TRANSPORT_LOG" 2097152
        {
            echo
            echo "================================================================"
            cat "$TRANSPORT_ENDPOINTS_FILE"
        } >> "$TRANSPORT_LOG"
    fi
    rm "$data_file" 2>/dev/null
)

read_counter() {
    file=$1
    value=0
    [ -r "$file" ] && value=$(cat "$file" 2>/dev/null)
    case "$value" in *[!0-9]*|'') value=0;; esac
    echo "$value"
}

increment_counter() {
    file=$1
    value=$(read_counter "$file")
    value=$((value + 1))
    echo "$value" > "$file"
    echo "$value"
}

framework_name() {
    if [ "${KSU:-}" = "true" ] || [ -d /data/adb/ksu ]; then
        echo "KernelSU"
    elif [ "${APATCH:-}" = "true" ] || [ -d /data/adb/ap ]; then
        echo "APatch"
    elif [ -d /data/adb/magisk ]; then
        echo "Magisk"
    else
        echo "Root"
    fi
}

set_description() {
    message=$(printf '%s' "$*" | tr '\r\n' '  ' | sed 's/[|&]/ /g')
    [ -f "$MODDIR/module.prop" ] || return 0
    current=$(grep '^description=' "$MODDIR/module.prop" 2>/dev/null)
    next="description=[状态] $message"
    [ "$current" = "$next" ] && return 0
    sed -i "s#^description=.*#$next#" "$MODDIR/module.prop" 2>/dev/null
}

get_toml_string() {
    key=$1
    [ -r "$CONFIG_FILE" ] || return 1
    awk -v wanted="$key" '
        /^[[:space:]]*#/ { next }
        {
            line=$0
            sub(/[[:space:]]*#.*/, "", line)
            if (line ~ "^[[:space:]]*" wanted "[[:space:]]*=") {
                sub(/^[^=]*=[[:space:]]*/, "", line)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                if (line ~ /^\".*\"$/) {
                    sub(/^\"/, "", line)
                    sub(/\"$/, "", line)
                }
                print line
                exit
            }
        }
    ' "$CONFIG_FILE"
}

get_toml_bool() (
    key=$1
    default=${2:-false}
    value=$(get_toml_string "$key" 2>/dev/null | tr '[:upper:]' '[:lower:]')
    case "$value" in
        true|1|yes|on) echo true ;;
        false|0|no|off) echo false ;;
        *) echo "$default" ;;
    esac
)

tcp_compatibility_state() (
    [ -r "$COMMAND_ARGS" ] && { echo command-args; exit 0; }
    kcp=$(get_toml_bool enable_kcp_proxy false)
    smoltcp=$(get_toml_bool use_smoltcp false)
    if [ "$kcp" != "true" ]; then
        echo recommended
    elif [ "$smoltcp" = "true" ]; then
        echo kcp-smoltcp
    else
        echo kcp-kernel-risk
    fi
)

log_tcp_compatibility() {
    [ -r "$COMMAND_ARGS" ] && {
        log_msg "EasyTier TCP compatibility config_mode=command_args"
        return 0
    }
    configured_dev=$(get_toml_string dev_name 2>/dev/null)
    [ -n "$configured_dev" ] || configured_dev=auto-tunX
    kcp=$(get_toml_bool enable_kcp_proxy false)
    smoltcp=$(get_toml_bool use_smoltcp false)
    compatibility=$(tcp_compatibility_state)
    log_msg "EasyTier TCP config dev_name=$configured_dev kcp_proxy=$kcp smoltcp=$smoltcp compatibility=$compatibility"
    if [ "$compatibility" = "kcp-kernel-risk" ]; then
        log_msg "WARN: KCP kernel TCP path may cause Ping/ICMP to work while HTTP/SSH TCP times out on some Android ROMs; disable KCP or enable smoltcp"
    fi
}

tcp_probe_once() (
    target=$1
    port=$2
    [ -n "$target" ] || exit 2
    case "$port" in *[!0-9]*|'') exit 2;; esac
    [ "$port" -ge 1 ] 2>/dev/null || exit 2
    [ "$port" -le 65535 ] 2>/dev/null || exit 2
    if command -v nc >/dev/null 2>&1; then
        nc -w 3 "$target" "$port" </dev/null >/dev/null 2>&1
    elif command -v busybox >/dev/null 2>&1; then
        busybox nc -w 3 "$target" "$port" </dev/null >/dev/null 2>&1
    else
        exit 2
    fi
)

tcp_probe_result() {
    label=$1
    target=$2
    port=$3
    [ -n "$target" ] || return 0
    tcp_probe_once "$target" "$port"
    result=$?
    case "$result" in
        0) echo "$label=OK target=$target port=$port" ;;
        2) echo "$label=UNAVAILABLE target=$target port=$port" ;;
        *) echo "$label=FAIL target=$target port=$port" ;;
    esac
}

get_hostname_arg() {
    brand=$(getprop ro.product.brand 2>/dev/null | tr ' ' '-')
    model=$(getprop ro.product.model 2>/dev/null | tr ' ' '-')
    [ -n "$brand" ] || brand=Android
    [ -n "$model" ] || model=Device
    printf '%s-%s' "$brand" "$model"
}

pid_matches_core() {
    pid=$1
    [ -n "$pid" ] && [ -r "/proc/$pid/cmdline" ] || return 1
    cmdline=$(tr '\000' ' ' < "/proc/$pid/cmdline" 2>/dev/null)
    case "$cmdline" in
        "$CORE"|"$CORE "*) return 0 ;;
    esac
    return 1
}

core_pid() {
    if [ -r "$PID_FILE" ]; then
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if pid_matches_core "$pid"; then
            echo "$pid"
            return 0
        fi
    fi

    for pid in $(pgrep -f "$CORE" 2>/dev/null); do
        if pid_matches_core "$pid"; then
            echo "$pid" > "$PID_FILE"
            echo "$pid"
            return 0
        fi
    done
    rm "$PID_FILE" 2>/dev/null
    return 1
}

core_running() {
    core_pid >/dev/null 2>&1
}

managed_script_pid() (
    script_pid=$(cat "$1" 2>/dev/null) || exit 1
    case "$script_pid" in *[!0-9]*|'') exit 1;; esac
    [ -r "$PROC_ROOT/$script_pid/cmdline" ] || exit 1
    tr '\000' '\n' < "$PROC_ROOT/$script_pid/cmdline" 2>/dev/null | grep -Fqx "$MODDIR/$2" || exit 1
    printf '%s\n' "$script_pid"
)

runtime_with_lock() (
    umask 077
    runtime_lock=$1
    runtime_limit=$2
    shift 2
    runtime_wait=0
    while ! mkdir "$runtime_lock" 2>/dev/null; do
        runtime_owner=$(cat "$runtime_lock/pid" 2>/dev/null || true)
        case "$runtime_owner" in *[!0-9]*|'') runtime_owner=0;; esac
        if [ "$runtime_owner" -gt 0 ] && ! kill -0 "$runtime_owner" 2>/dev/null; then
            # Pin the old directory before re-checking and atomically moving it away.
            # A missing owner is NOT stale: another writer may still be publishing it.
            if mkdir "$runtime_lock/reaping" 2>/dev/null; then
                runtime_owner_now=$(cat "$runtime_lock/pid" 2>/dev/null || true)
                if [ "$runtime_owner_now" = "$runtime_owner" ] && ! kill -0 "$runtime_owner" 2>/dev/null; then
                    runtime_stale=$(mktemp -d "$RUNDIR/runtime-stale.XXXXXX") || { rmdir "$runtime_lock/reaping" 2>/dev/null; exit 1; }
                    if mv "$runtime_lock" "$runtime_stale/lock" 2>/dev/null; then
                        rm "$runtime_stale/lock/pid" 2>/dev/null || true
                        rmdir "$runtime_stale/lock/reaping" "$runtime_stale/lock" "$runtime_stale" 2>/dev/null || true
                        continue
                    fi
                    rmdir "$runtime_stale" 2>/dev/null || true
                fi
                rmdir "$runtime_lock/reaping" 2>/dev/null || true
            fi
        fi
        runtime_wait=$((runtime_wait + 1))
        if [ "$runtime_wait" -ge "$runtime_limit" ]; then
            echo "服务操作仍在进行，请稍后重试" >&2
            exit 1
        fi
        sleep 1
    done
    trap 'rm -f "$runtime_lock/pid"; rmdir "$runtime_lock" 2>/dev/null || true' 0
    trap 'exit 1' HUP INT TERM
    runtime_owner_pid=$$
    # $$ is the parent PID in POSIX subshells; /proc/self is opened by read itself.
    if [ -r /proc/self/stat ]; then read -r runtime_owner_pid runtime_proc_rest < /proc/self/stat; fi
    printf '%s\n' "$runtime_owner_pid" > "$runtime_lock/pid" || exit 1
    "$@"
)

service_mode() {
    case "$(cat "$SERVICE_MODE_FILE" 2>/dev/null)" in auto) echo auto;; *) echo manual;; esac
}

home_detection_mode() {
    case "$(sed -n 's/^mode=//p' "$HOME_DETECTION_FILE" 2>/dev/null | head -n 1)" in
        event) echo event;; *) echo poll;;
    esac
}

home_interval_valid() {
    case "$1" in ''|*[!0-9]*|0*) return 1;; esac
    [ "${#1}" -le 10 ] && [ "$1" -le 2147483647 ]
}

home_check_interval() (
    interval=$(sed -n 's/^interval=//p' "$HOME_DETECTION_FILE" 2>/dev/null | head -n 1)
    if home_interval_valid "$interval"; then printf '%s\n' "$interval"; else echo 30; fi
)

# A root bridge/ADB shell can send SIGHUP to its process group on exit. Start
# long-lived workers in their own session so closing the caller cannot stop them.
launch_detached() {
    # Always invoke this function with '&'. An additional '( ... )' body leaves
    # an mksh wrapper attached to the caller's tty; it forwards HUP to the worker
    # even after setsid, so exec must replace the background shell itself.
    if command -v setsid >/dev/null 2>&1; then
        exec setsid "$@"
    else
        exec nohup "$@"
    fi
}

wait_for_script_start() (
    ready_wait=0
    until managed_script_pid "$1" "$2" >/dev/null 2>&1; do
        [ "$ready_wait" -lt 30 ] || return 1
        sleep 0.1
        ready_wait=$((ready_wait + 1))
    done
)

service_user_blocked() {
    [ -f "$MANUAL_STOP_FILE" ] || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]
}

workers_blocked() {
    service_user_blocked || [ -f "$HOME_PAUSED_FILE" ]
}

process_start_token() {
    sed 's/^.*) //' "$PROC_ROOT/$1/stat" 2>/dev/null | awk '{print $20}'
}

stop_script_tree() (
    # Exact argv identity protects other modules from stale/recycled PID files.
    stop_file=$1; stop_script=$2
    candidates="$(cat "$stop_file" 2>/dev/null || true) $(pgrep -f "$stop_script" 2>/dev/null || true)"
    for root_pid in $(printf '%s\n' $candidates | sort -un); do
        case "$root_pid" in *[!0-9]*|''|0|1) continue;; esac
        tr '\000' '\n' 2>/dev/null < "$PROC_ROOT/$root_pid/cmdline" | grep -Fqx "$MODDIR/$stop_script" || continue
        tree_file="$RUNDIR/.stop-tree-$root_pid-$$"
        : > "$tree_file" || exit 1
        # Freeze parents before enumerating their children, preventing new probes
        # or sleepers escaping shutdown. The core receives its own graceful stop.
        freeze_tree() (
            fp=$1
            [ "$fp" = "$root_pid" ] || { pid_matches_core "$fp" && exit 0; }
            token=$(process_start_token "$fp")
            [ -n "$token" ] || exit 0
            printf '%s %s\n' "$fp" "$token" >> "$tree_file"
            kill -STOP "$fp" 2>/dev/null || exit 0
            for child in $(ps -A -o PID,PPID 2>/dev/null | awk -v parent="$fp" '$2==parent {print $1}'); do
                freeze_tree "$child"
            done
        )
        thaw_tree() {
            while read -r tp tt; do
                [ "$(process_start_token "$tp")" = "$tt" ] && kill -CONT "$tp" 2>/dev/null || true
            done < "$tree_file"
        }
        trap 'thaw_tree; rm -f "$tree_file"' EXIT
        trap 'exit 1' HUP INT TERM
        freeze_tree "$root_pid"
        while read -r tp tt; do
            [ "$(process_start_token "$tp")" = "$tt" ] && kill -TERM "$tp" 2>/dev/null || true
        done < "$tree_file"
        thaw_tree
        sleep 1
        while read -r tp tt; do
            [ "$(process_start_token "$tp")" = "$tt" ] && kill -KILL "$tp" 2>/dev/null || true
        done < "$tree_file"
        tree_alive() (
            while read -r ap at; do
                [ "$(process_start_token "$ap")" = "$at" ] || continue
                # /proc cmdline has size zero even for a live process; read it.
                [ -n "$(tr '\000' ' ' 2>/dev/null < "$PROC_ROOT/$ap/cmdline")" ] && exit 0
            done < "$tree_file"
            exit 1
        )
        if tree_alive; then
            sleep 1
            if tree_alive; then
                echo "无法完全停止 $stop_script，请查看日志。" >&2
                exit 1
            fi
        fi
        rm -f "$tree_file"
        trap - EXIT HUP INT TERM
    done
    rm -f "$stop_file"
)

ensure_daemon_running() (
    # The independent network watcher can survive an unexpected daemon exit.
    # Never counteract an explicit stop, disabled module, or official APP VPN.
    workers_blocked && exit 0
    managed_script_pid "$DAEMON_PID_FILE" tiernestd.sh >/dev/null && exit 0
    [ -x "$MODDIR/tiernestd.sh" ] || exit 1
    # Boot keeps the supervisor available to resume when the official APP exits.
    [ "${1:-}" = boot ] || { easytier_app_vpn_active && exit 0; }
    log_msg "TierNest daemon missing; scheduling supervisor restart"
    launch_detached "$MODDIR/tiernestd.sh" >> "$MODULE_LOG" 2>&1 </dev/null &
    # Wait for its own PID publication so the caller cannot exit before setsid.
    wait_for_script_start "$DAEMON_PID_FILE" tiernestd.sh
)

# Read v1.0.4's single key/value record and v1.0.5's network= rows without
# rewriting either on boot/status reads. Upgrade inheritance stays byte-for-byte.
home_network_records() {
    [ -r "$HOME_NETWORK_FILE" ] || return 0
    awk '
        /^network=/ {print substr($0,9); rows=1; next}
        /^(interface|gateway|mac|target|port)=/ {
            key=$0; sub(/=.*/, "", key)
            value=substr($0,index($0,"=")+1)
            if (!(key in legacy)) legacy[key]=value
        }
        END {
            if (!rows && legacy["interface"]!="" && legacy["gateway"]!="" &&
                legacy["mac"]!="" && legacy["target"]!="" && legacy["port"]!="")
                print legacy["interface"] "|" legacy["gateway"] "|" legacy["mac"] "|" legacy["target"] "|" legacy["port"]
        }' "$HOME_NETWORK_FILE"
}

home_network_id() { printf '%s-%s-%s\n' "$1" "$2" "$3" | tr -d ':'; }

print_supervision_status() (
    echo "service_mode=$(service_mode)"
    echo "home_detection_mode=$(home_detection_mode)"
    echo "home_check_interval=$(home_check_interval)"
    echo "home_watch_error=$(cat "$HOME_WATCH_ERROR_FILE" 2>/dev/null || true)"
    home_records=$(home_network_records)
    if [ -n "$home_records" ]; then echo 'home_configured=1'; else echo 'home_configured=0'; fi
    echo "home_network_count=$(printf '%s\n' "$home_records" | awk 'NF{n++} END{print n+0}')"
    echo "home_networks_b64=$(printf '%s\n' "$home_records" | base64 | tr -d '\r\n')"
    echo "home_active_id=$(cat "$HOME_PAUSED_FILE" 2>/dev/null || true)"
    if [ -f "$HOME_PAUSED_FILE" ]; then echo 'home_paused=1'; else echo 'home_paused=0'; fi
    echo "home_watch_pid=$(managed_script_pid "$HOME_WATCH_PID_FILE" home_watch.sh 2>/dev/null || echo stopped)"
    # Retain first-record fields for older status readers.
    printf '%s\n' "$home_records" | awk -F '|' 'NF==5 {print "home_gateway=" $2; print "home_target=" $4; print "home_port=" $5; exit}'
    for marker in manual_stop disable remove; do
        case "$marker" in manual_stop) marker_path=$MANUAL_STOP_FILE;; *) marker_path="$MODDIR/$marker";; esac
        if [ -f "$marker_path" ]; then echo "$marker=1"; else echo "$marker=0"; fi
    done
    daemon_pid=$(managed_script_pid "$DAEMON_PID_FILE" tiernestd.sh 2>/dev/null || true)
    echo "daemon_pid=${daemon_pid:-stopped}"
    echo "network_watch_pid=$(managed_script_pid "$NETWORK_WATCH_PID_FILE" network_watch.sh 2>/dev/null || echo stopped)"
    echo "daemon_heartbeat=$(cat "$DAEMON_HEARTBEAT_FILE" 2>/dev/null || echo none)"
    echo "recovery_phase=$(cat "$RECOVERY_PHASE_FILE" 2>/dev/null || echo none)"
    if [ -n "$daemon_pid" ]; then
        echo "daemon_wait_channel=$(cat "$PROC_ROOT/$daemon_pid/wchan" 2>/dev/null || echo unknown)"
        for child_pid in $(cat "$PROC_ROOT/$daemon_pid/task/$daemon_pid/children" 2>/dev/null); do
            case "$child_pid" in *[!0-9]*|'') continue;; esac
            printf 'daemon_child=%s name=%s wait=%s\n' "$child_pid" \
                "$(cat "$PROC_ROOT/$child_pid/comm" 2>/dev/null)" "$(cat "$PROC_ROOT/$child_pid/wchan" 2>/dev/null)"
        done
    fi
)

ensure_tun_device() {
    [ -c /dev/net/tun ] && return 0
    if [ -c /dev/tun ]; then
        mkdir -p /dev/net 2>/dev/null
        [ -e /dev/net/tun ] || ln -s /dev/tun /dev/net/tun 2>/dev/null
    fi
    [ -c /dev/net/tun ] || log_msg "WARN: /dev/net/tun is unavailable"
}

validate_runtime_config() {
    # command_args is intentionally free-form; only validate the bundled TOML template.
    [ -r "$COMMAND_ARGS" ] && return 0

    network_name=$(get_toml_string network_name)
    network_secret=$(get_toml_string network_secret)
    configured_ip=$(get_toml_string ipv4)
    dhcp_enabled=$(get_toml_string dhcp)
    peer_count=$(grep -c '^[[:space:]]*\[\[peer\]\][[:space:]]*$' "$CONFIG_FILE" 2>/dev/null || true)
    case "$peer_count" in *[!0-9]*|'') peer_count=0;; esac

    if [ "$network_name" = "default" ] \
        && [ -z "$network_secret" ] \
        && [ -z "$configured_ip" ] \
        && [ "$dhcp_enabled" != "true" ] \
        && [ "$peer_count" -eq 0 ]; then
        log_msg "ERROR: bundled example config is still active; copy the private config.toml before starting"
        set_description "未配置：请覆盖 config.toml"
        return 1
    fi
    return 0
}

start_core_unlocked() {
    workers_blocked && return 1
    core_running && return 0
    [ -x "$CORE" ] || {
        log_msg "ERROR: missing executable $CORE"
        set_description "启动失败：缺少核心程序"
        return 1
    }
    [ -r "$CONFIG_FILE" ] || [ -r "$COMMAND_ARGS" ] || {
        log_msg "ERROR: no config.toml or command_args"
        set_description "启动失败：缺少配置"
        return 1
    }
    validate_runtime_config || return 1
    if easytier_app_vpn_active; then
        log_msg "ERROR: EasyTier APP VPN is active; stop com.kkrainbow.easytier before starting TierNest"
        set_description "冲突：请关闭 EasyTier APP VPN"
        return 1
    fi

    ensure_tun_device
    log_tcp_compatibility
    rotate_log "$CORE_LOG" 2097152
    host=$(get_hostname_arg)
    ulimit -n 65535 2>/dev/null
    workers_blocked && return 1

    if [ -r "$COMMAND_ARGS" ]; then
        args=$(tr '\r\n' '  ' < "$COMMAND_ARGS")
        # command_args intentionally uses whitespace-delimited arguments; shell quotes are unsupported.
        set -- $args
        case " $args " in
            *" --hostname "*|*" --hostname="*) ;;
            *) set -- "$@" --hostname "$host" ;;
        esac
        TZ=Asia/Shanghai launch_detached "$CORE" "$@" >> "$CORE_LOG" 2>&1 </dev/null &
        mode="参数模式"
    else
        if grep -q '^[[:space:]]*hostname[[:space:]]*=' "$CONFIG_FILE"; then
            TZ=Asia/Shanghai launch_detached "$CORE" -c "$CONFIG_FILE" >> "$CORE_LOG" 2>&1 </dev/null &
        else
            TZ=Asia/Shanghai launch_detached "$CORE" -c "$CONFIG_FILE" --hostname "$host" >> "$CORE_LOG" 2>&1 </dev/null &
        fi
        mode="配置模式"
    fi

    pid=$!
    echo "$pid" > "$PID_FILE"
    sleep 3
    if workers_blocked; then stop_core; return 1; fi
    # setsid may fork when the caller is already a process-group leader. Resolve
    # the actual executable instead of assuming the launcher PID is the core.
    pid=$(core_pid 2>/dev/null || true)
    if [ -n "$pid" ]; then
        date +%s > "$CORE_STARTED_AT_FILE" 2>/dev/null
        rm "$CPU_SAMPLE_FILE" 2>/dev/null
        log_msg "EasyTier started pid=$pid mode=$mode"
        set_description "运行中（$mode） | $(framework_name)"
        return 0
    fi

    rm "$PID_FILE" 2>/dev/null
    log_msg "ERROR: EasyTier exited during startup; inspect $CORE_LOG"
    set_description "启动失败：请查看日志"
    return 1
}

start_core() {
    workers_blocked && return 1
    core_running && return 0
    runtime_with_lock "$START_LOCK" 15 start_core_unlocked
}

stop_core() {
    pid=$(core_pid 2>/dev/null) || return 0
    log_msg "Stopping EasyTier pid=$pid"
    kill "$pid" 2>/dev/null
    count=0
    while pid_matches_core "$pid" && [ "$count" -lt 10 ]; do
        sleep 1
        count=$((count + 1))
    done
    if pid_matches_core "$pid"; then
        kill -9 "$pid" 2>/dev/null
        sleep 1
    fi
    rm "$PID_FILE" "$CORE_STARTED_AT_FILE" "$CPU_SAMPLE_FILE" 2>/dev/null
}

configured_ipv4_cidr() {
    value=$(get_toml_string ipv4)
    case "$value" in
        *.*.*.*/*) echo "$value"; return 0 ;;
    esac

    [ -r "$COMMAND_ARGS" ] || return 1
    args=$(tr '\r\n' '  ' < "$COMMAND_ARGS")
    value=$(printf '%s\n' "$args" | sed -n 's/.*--ipv4[= ][[:space:]]*\([^[:space:]]*\).*/\1/p')
    [ -n "$value" ] || value=$(printf '%s\n' "$args" | sed -n -e 's/^-i[[:space:]][[:space:]]*\([^[:space:]]*\).*/\1/p' -e 's/.*[[:space:]]-i[[:space:]][[:space:]]*\([^[:space:]]*\).*/\1/p')
    case "$value" in
        *.*.*.*/*) echo "$value"; return 0 ;;
    esac
    return 1
}

find_tun_device() {
    # Never identify another process' tunX by IP/name after the managed core has
    # stopped. This prevents the official EasyTier APP VPN from being mistaken
    # for TierNest's TUN during failed restarts or route cleanup.
    core_running || return 1
    configured=$(get_toml_string dev_name)
    if [ -n "$configured" ] && ip link show dev "$configured" >/dev/null 2>&1; then
        echo "$configured"
        return 0
    fi

    logged=$(sed -n 's/.*tun device ready dev="\([^"]*\)".*/\1/p' "$CORE_LOG" 2>/dev/null | tail -n 1)
    if [ -n "$logged" ] && ip link show dev "$logged" >/dev/null 2>&1; then
        echo "$logged"
        return 0
    fi

    local_cidr=$(configured_ipv4_cidr 2>/dev/null)
    local_ip=${local_cidr%/*}
    if [ -n "$local_ip" ]; then
        found=$(ip -o -4 addr show 2>/dev/null | awk -v addr="$local_ip" '$4 ~ ("^" addr "/") {print $2; exit}' | cut -d@ -f1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    fi

    found=$(ip -o link show 2>/dev/null | awk -F': ' '
        {
            name=$2
            sub(/@.*/, "", name)
            if (name ~ /^tiernest[0-9]*$/ || name ~ /^tun[0-9]+$/ || name ~ /^tap[0-9]+$/ || name ~ /^vgate[0-9]+$/) {
                print name
                exit
            }
        }
    ')
    [ -n "$found" ] && echo "$found"
}

ping_target_once() {
    target=$1
    iface=${2:-}
    [ -n "$target" ] || return 1
    if [ -n "$iface" ]; then
        ping -I "$iface" -c 1 -W 2 "$target" >/dev/null 2>&1
    else
        ping -c 1 -W 2 "$target" >/dev/null 2>&1
    fi
}

health_probe_state() {
    [ "$HEALTH_CHECK_ENABLED" = "1" ] || { echo disabled; return 0; }
    [ -n "$HEALTH_PROXY_TARGET" ] || { echo unconfigured; return 0; }
    dev=$(find_tun_device 2>/dev/null)
    if ping_target_once "$HEALTH_PROXY_TARGET"; then
        echo healthy
        return 0
    fi
    # A forced TUN success proves that EasyTier data-plane connectivity exists even when
    # the current Wi-Fi blocks public ICMP such as 1.1.1.1. Treat this as a routing failure.
    if [ -n "$HEALTH_EASYTIER_TARGET" ] && ping_target_once "$HEALTH_EASYTIER_TARGET" "$dev"; then
        echo proxy-unreachable
        return 0
    fi
    if ! ping_target_once "$HEALTH_INTERNET_TARGET"; then
        echo underlying-offline
    else
        echo overlay-unreachable
    fi
}

easytier_app_vpn_state() (
    if command -v dumpsys >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            output=$(timeout 5 dumpsys connectivity 2>/dev/null || true)
        else
            output=$(dumpsys connectivity 2>/dev/null || true)
        fi
        printf '%s\n' "$output" | grep -Eiq 'VPN:[^[:space:]]*easytier|VPN:com\.kkrainbow\.easytier|sessionId=TauriVpnService' || exit 1
        printf '%s\n' "$output" | grep -Ei 'VPN:[^[:space:]]*easytier|VPN:com\.kkrainbow\.easytier|sessionId=TauriVpnService' | head -n 1
        exit 0
    fi
    exit 1
)

easytier_app_vpn_active() {
    easytier_app_vpn_state >/dev/null 2>&1
}

physical_route_signature() {
    awk '
        {
            dev=""; via=""; src=""; table="main"
            for (i=1; i<=NF; i++) {
                if ($i == "dev" && i < NF) dev=$(i+1)
                else if ($i == "via" && i < NF) via=$(i+1)
                else if ($i == "src" && i < NF) src=$(i+1)
                else if ($i == "table" && i < NF) table=$(i+1)
            }
            if (dev ~ /^(wlan|rmnet|v4-rmnet|ccmni|pdp|usb|rndis|eth|bond|br|bt-pan|bnep)/)
                print "dev=" dev "|via=" via "|src=" src "|table=" table
        }
    '
}

underlay_signature() (
    route=$(ip -4 route get "$HEALTH_INTERNET_TARGET" 2>/dev/null | head -n 1)
    physical=$(printf '%s\n' "$route" | physical_route_signature)
    if [ -n "$physical" ]; then
        printf '%s\n' "$physical"
        exit 0
    fi
    # A VPN can own route-get while Android's default physical network remains
    # unchanged. Resolve that network's table, then explicitly query its device.
    # Do not select an arbitrary connected cellular/IMS or Wi-Fi interface.
    tables=$(ip -4 rule show 2>/dev/null | awk '
        /from all/ && /fwmark 0x0\/0xffff / && /iif lo/ && !/uidrange| oif | to / {
            for (i=1; i<NF; i++) if ($i == "lookup") print $(i+1)
        }
    ')
    for underlay_table in $tables; do
        underlay_dev=$(ip -4 route show table "$underlay_table" 2>/dev/null | awk '
            $1 == "default" { for (i=1; i<NF; i++) if ($i == "dev") {print $(i+1); exit} }
        ')
        [ -n "$underlay_dev" ] || continue
        # Validate before asking route-get to bind to the device.
        [ -n "$(printf 'dev %s\n' "$underlay_dev" | physical_route_signature)" ] || continue
        physical=$(ip -4 route get "$HEALTH_INTERNET_TARGET" oif "$underlay_dev" 2>/dev/null | head -n 1 | physical_route_signature)
        if [ -n "$physical" ]; then
            printf '%s\n' "$physical"
            exit 0
        fi
    done
    echo none
)

# UI-only snapshot values. Recovery code always calls the original live probes.
overview_sample() {
    if [ "${OVERVIEW_SAMPLE_READY:-0}" = 1 ]; then
        case "$1" in
            pid) printf '%s\n' "$OVERVIEW_PID" ;;
            tun) printf '%s\n' "$OVERVIEW_TUN" ;;
            vpn) printf '%s\n' "$OVERVIEW_VPN" ;;
            app) printf '%s\n' "$OVERVIEW_APP" ;;
            underlay) printf '%s\n' "$OVERVIEW_UNDERLAY" ;;
            rpc) printf '%s\n' "$OVERVIEW_RPC" ;;
            endpoints) printf '%s\n' "$OVERVIEW_ENDPOINTS" ;;
            *) return 1 ;;
        esac
        return 0
    fi
    case "$1" in
        pid) core_pid 2>/dev/null || true ;;
        tun) find_tun_device 2>/dev/null || true ;;
        vpn) external_vpn_state 2>/dev/null || true ;;
        app) if easytier_app_vpn_active; then echo active; else echo inactive; fi ;;
        underlay) underlay_signature ;;
        rpc) easytier_rpc_state ;;
        endpoints) live_transport_endpoint_count ;;
        *) return 1 ;;
    esac
}

easytier_rpc_state() (
    core_running || { echo stopped; exit 0; }
    [ -x "$CLI" ] || { echo unavailable; exit 0; }
    portal=$(get_rpc_portal)
    if command -v timeout >/dev/null 2>&1; then
        output=$(timeout 5 "$CLI" --rpc-portal "$portal" -o json route list 2>/dev/null) || {
            echo timeout
            exit 0
        }
    else
        output=$("$CLI" --rpc-portal "$portal" -o json route list 2>/dev/null) || {
            echo timeout
            exit 0
        }
    fi
    case "$output" in
        *'"next_hop_hostname"'*) echo healthy ;;
        *) echo invalid ;;
    esac
)

live_transport_endpoint_count() (
    transport_pid=$(core_pid 2>/dev/null || true)
    [ -n "$transport_pid" ] || { echo 0; exit 0; }
    # /proc/net state 01 is TCP ESTABLISHED. UDP remote endpoints commonly use
    # state 07. SYN_SENT (02) and CLOSE_WAIT (08) are attempts/stale sockets and
    # must not suppress recovery as if a working transport still existed.
    count=$(core_transport_sockets "$transport_pid" 2>/dev/null         | awk -F'|' '$1 == "tcp" && $4 == "01" {n++} $1 == "udp" && $4 == "07" {n++} END {print n+0}')
    case "$count" in *[!0-9]*|'') count=0;; esac
    echo "$count"
)

external_vpn_state() {
    easytier_dev=""
    if core_running; then easytier_dev=$(find_tun_device 2>/dev/null || true); fi
    ip -o -4 addr show 2>/dev/null | awk -v easytier="$easytier_dev" '
        {
            name=$2
            sub(/@.*/, "", name)
            if (name == easytier) next
            if (name ~ /^tun[0-9]+$/ || name ~ /^tap[0-9]+$/ || name ~ /^wg[0-9]+$/ || name ~ /^ppp[0-9]+$/ || name == "Meta") {
                print name "=" $4
            }
        }
    ' | sort | tr '\n' ','
}

normalize_ipv4_cidr() (
    cidr=$1
    case "$cidr" in
        */*) ip=${cidr%/*}; prefix=${cidr#*/} ;;
        *) ip=$cidr; prefix=32 ;;
    esac
    old_ifs=$IFS
    IFS=.
    set -- $ip
    IFS=$old_ifs
    [ "$#" -eq 4 ] || exit 1
    for octet in "$@"; do
        case "$octet" in *[!0-9]*|'') exit 1;; esac
        [ "$octet" -le 255 ] || exit 1
    done
    case "$prefix" in *[!0-9]*|'') exit 1;; esac
    [ "$prefix" -le 32 ] || exit 1

    address=$(( ($1 << 24) | ($2 << 16) | ($3 << 8) | $4 ))
    if [ "$prefix" -eq 0 ]; then
        network=0
    else
        mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
        network=$(( address & mask ))
    fi
    printf '%d.%d.%d.%d/%d\n' \
        $(( (network >> 24) & 255 )) \
        $(( (network >> 16) & 255 )) \
        $(( (network >> 8) & 255 )) \
        $(( network & 255 )) \
        "$prefix"
)

get_tun_cidr() {
    dev=$1
    cidr=$(ip -o -4 addr show dev "$dev" 2>/dev/null | awk '$3 == "inet" {print $4; exit}')
    [ -n "$cidr" ] || cidr=$(configured_ipv4_cidr 2>/dev/null)
    [ -n "$cidr" ] && normalize_ipv4_cidr "$cidr"
}

get_rpc_portal() {
    portal=$(get_toml_string rpc_portal)
    [ -n "$portal" ] || portal="127.0.0.1:15888"
    case "$portal" in
        0.0.0.0:*) portal="127.0.0.1:${portal##*:}" ;;
    esac
    echo "$portal"
}

cli_route_cidrs() {
    [ -x "$CLI" ] || return 0
    portal=$(get_rpc_portal)
    if command -v timeout >/dev/null 2>&1; then
        output=$(timeout 6 "$CLI" --rpc-portal "$portal" -o json route list 2>/dev/null)
    else
        output=$("$CLI" --rpc-portal "$portal" -o json route list 2>/dev/null)
    fi
    printf '%s\n' "$output" | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])' 2>/dev/null
}

overlay_remote_peer_count() (
    [ -x "$CLI" ] || { echo -1; exit 0; }
    core_running || { echo 0; exit 0; }
    portal=$(get_rpc_portal)
    if command -v timeout >/dev/null 2>&1; then
        output=$(timeout 6 "$CLI" --rpc-portal "$portal" -o json route list 2>/dev/null) || {
            echo -1
            exit 0
        }
    else
        output=$("$CLI" --rpc-portal "$portal" -o json route list 2>/dev/null) || {
            echo -1
            exit 0
        }
    fi
    case "$output" in
        *'"next_hop_hostname"'*) ;;
        *) echo -1; exit 0 ;;
    esac
    total=$(printf '%s
' "$output" | grep -c '"next_hop_hostname"[[:space:]]*:')
    local_count=$(printf '%s
' "$output" | grep -c '"next_hop_hostname"[[:space:]]*:[[:space:]]*"Local"')
    case "$total" in *[!0-9]*|'') echo -1; exit 0;; esac
    case "$local_count" in *[!0-9]*|'') local_count=0;; esac
    remote=$((total - local_count))
    [ "$remote" -ge 0 ] || remote=0
    echo "$remote"
)

should_wait_for_transport_reconnect() {
    state=$1
    [ "$state" = "overlay-unreachable" ] || return 1
    remote_count=$(overlay_remote_peer_count)
    [ "$remote_count" = "0" ] || return 1
    # Only wait when the RPC is responsive and the core still owns live transport
    # sockets. RPC timeout or zero endpoints is a half-dead core, not healthy reconnecting.
    [ "$(easytier_rpc_state)" = healthy ] || return 1
    endpoint_count=$(live_transport_endpoint_count)
    [ "$endpoint_count" -gt 0 ] 2>/dev/null
}

route_allowed() {
    cidr=$1
    if [ "$ALLOW_EXIT_ROUTES" != "1" ]; then
        case "$cidr" in
            0.0.0.0/0|0.0.0.0/1|128.0.0.0/1) return 1 ;;
        esac
    fi
    return 0
}


ipv4_cidr_contains() {
    outer=$1
    inner=$2
    awk -v outer="$outer" -v inner="$inner" '
        function ipnum(ip, p) {
            split(ip, p, ".")
            return p[1]*16777216 + p[2]*65536 + p[3]*256 + p[4]
        }
        function bounds(cidr, result, pair, size, start) {
            split(cidr, pair, "/")
            size=2^(32-pair[2])
            start=int(ipnum(pair[1])/size)*size
            result[1]=start
            result[2]=start+size-1
        }
        BEGIN {
            bounds(outer, a)
            bounds(inner, b)
            exit !(a[1] <= b[1] && a[2] >= b[2])
        }
    '
}

physical_connected_routes() {
    easytier_dev=$1
    [ "$PREFER_DIRECT_LOCAL_SUBNETS" = "1" ] || return 0
    ip -o -4 addr show 2>/dev/null | awk -v easytier="$easytier_dev" '
        $3 == "inet" {
            name=$2
            sub(/@.*/, "", name)
            if (name == easytier || name == "lo" || name == "Meta") next
            if (name ~ /^(tun|tap|wg|ppp)[0-9]*$/) next
            if (name !~ /^(wlan|swlan|ap|softap|rmnet|v4-rmnet|ccmni|pdp|usb|rndis|eth|bond|br|bt-pan|bnep)/) next
            print $4 "|" name
        }
    ' | while IFS='|' read -r cidr iface; do
        normalized=$(normalize_ipv4_cidr "$cidr" 2>/dev/null) || continue
        echo "$normalized|$iface"
    done | sort -u
}

refresh_local_route_overrides() {
    easytier_dev=$1
    tmp="$RUNDIR/local-route-overrides.$$.tmp"
    physical_connected_routes "$easytier_dev" > "$tmp" 2>/dev/null || true
    if ! cmp -s "$tmp" "$LOCAL_ROUTE_OVERRIDES_FILE" 2>/dev/null; then
        cp "$tmp" "$LOCAL_ROUTE_OVERRIDES_FILE"
        count=$(grep -c . "$tmp" 2>/dev/null || true)
        case "$count" in *[!0-9]*|'') count=0;; esac
        log_msg "Local direct-route overrides changed count=$count"
    fi
    mv "$tmp" "$LOCAL_ROUTE_OVERRIDES_FILE" 2>/dev/null || true
}

covering_local_route() {
    candidate=$1
    file=$2
    [ -r "$file" ] || return 1
    while IFS='|' read -r local_cidr local_iface; do
        [ -n "$local_cidr" ] || continue
        if ipv4_cidr_contains "$local_cidr" "$candidate"; then
            echo "$local_cidr|$local_iface"
            return 0
        fi
    done < "$file"
    return 1
}

build_expected_route_specs() {
    easytier_dev=$1
    overlay_file=$2
    local_file=$3
    output_file=$4
    raw="$output_file.raw"
    : > "$raw"

    while IFS= read -r cidr; do
        [ -n "$cidr" ] || continue
        if covering_local_route "$cidr" "$local_file" >/dev/null 2>&1; then
            continue
        fi
        echo "$cidr|$easytier_dev" >> "$raw"
    done < "$overlay_file"
    cat "$local_file" >> "$raw" 2>/dev/null || true

    awk -F'|' 'NF >= 2 && $1 != "" && $2 != "" { route[$1]=$2 } END { for (cidr in route) print cidr "|" route[cidr] }' "$raw" | sort > "$output_file"
    rm "$raw" 2>/dev/null || true
}


active_android_network_tables() {
    easytier_dev=$1
    android_network_table_mirroring_enabled || return 0
    rules_file="$RUNDIR/android-rules.$$.tmp"
    ifaces_file="$RUNDIR/android-ifaces.$$.tmp"
    ip -4 rule show 2>/dev/null > "$rules_file"
    physical_connected_routes "$easytier_dev" | awk -F'|' 'NF >= 2 {print $2}' | sort -u > "$ifaces_file"
    while IFS= read -r iface; do
        [ -n "$iface" ] || continue
        if grep -Eq "lookup[[:space:]]+$iface([[:space:]]|$)" "$rules_file" \
            && route_table_supported "$iface"; then
            echo "$iface"
        fi
    done < "$ifaces_file"
    rm "$rules_file" "$ifaces_file" 2>/dev/null || true
}

build_android_route_specs() {
    easytier_dev=$1
    overlay_file=$2
    local_file=$3
    output_file=$4
    tables_file="$output_file.tables"
    : > "$output_file"
    active_android_network_tables "$easytier_dev" > "$tables_file" 2>/dev/null || true
    while IFS= read -r table; do
        [ -n "$table" ] || continue
        while IFS= read -r cidr; do
            [ -n "$cidr" ] || continue
            if covering_local_route "$cidr" "$local_file" >/dev/null 2>&1; then
                continue
            fi
            echo "$table|$cidr|$easytier_dev"
        done < "$overlay_file"
    done < "$tables_file" | sort -u > "$output_file"
    mv "$tables_file" "$ANDROID_ROUTE_TABLES_FILE" 2>/dev/null || true
}

cleanup_android_network_routes() {
    [ -r "$ANDROID_ROUTE_SPECS_FILE" ] || {
        rm "$ANDROID_ROUTE_TABLES_FILE" 2>/dev/null || true
        return 0
    }
    while IFS='|' read -r table cidr route_dev; do
        [ -n "$table" ] && [ -n "$cidr" ] || continue
        ip -4 route del table "$table" "$cidr" dev "$route_dev" 2>/dev/null \
            || ip -4 route del table "$table" "$cidr" 2>/dev/null \
            || true
    done < "$ANDROID_ROUTE_SPECS_FILE"
    rm "$ANDROID_ROUTE_SPECS_FILE" "$ANDROID_ROUTE_TABLES_FILE" 2>/dev/null || true
}

sync_android_network_routes() {
    easytier_dev=$1
    overlay_file=$2
    local_file=$3
    desired="$RUNDIR/android-route-specs.$$.desired"
    successful="$RUNDIR/android-route-specs.$$.successful"
    : > "$successful"
    build_android_route_specs "$easytier_dev" "$overlay_file" "$local_file" "$desired"

    if [ -r "$ANDROID_ROUTE_SPECS_FILE" ]; then
        while IFS='|' read -r table cidr route_dev; do
            [ -n "$table" ] && [ -n "$cidr" ] || continue
            if ! grep -Fqx "$table|$cidr|$route_dev" "$desired" 2>/dev/null; then
                ip -4 route del table "$table" "$cidr" dev "$route_dev" 2>/dev/null \
                    || ip -4 route del table "$table" "$cidr" 2>/dev/null \
                    || true
            fi
        done < "$ANDROID_ROUTE_SPECS_FILE"
    fi

    while IFS='|' read -r table cidr route_dev; do
        [ -n "$table" ] && [ -n "$cidr" ] && [ -n "$route_dev" ] || continue
        if ip -4 route replace table "$table" "$cidr" dev "$route_dev" 2>> "$MODULE_LOG"; then
            echo "$table|$cidr|$route_dev" >> "$successful"
        fi
    done < "$desired"
    sort -u "$successful" > "$successful.sorted" 2>/dev/null
    mv "$successful.sorted" "$successful" 2>/dev/null || true

    if ! cmp -s "$successful" "$ANDROID_ROUTE_SPECS_FILE" 2>/dev/null; then
        count=$(grep -c . "$successful" 2>/dev/null || true)
        case "$count" in *[!0-9]*|'') count=0;; esac
        table_count=$(grep -c . "$ANDROID_ROUTE_TABLES_FILE" 2>/dev/null || true)
        case "$table_count" in *[!0-9]*|'') table_count=0;; esac
        log_msg "Synced Android app routes count=$count tables=$table_count tun=$easytier_dev"
    fi
    mv "$successful" "$ANDROID_ROUTE_SPECS_FILE"
    rm "$desired" 2>/dev/null || true
}

find_existing_rule_pref() {
    table=${1:-$ROUTE_TABLE}
    ip -4 rule show 2>/dev/null | awk -v table="$table" '$0 ~ ("lookup " table "([[:space:]]|$)") && $0 !~ / iif / {gsub(":", "", $1); print $1; exit}'
}

ensure_policy_rule() {
    existing=$(find_existing_rule_pref)
    if [ -n "$existing" ]; then
        echo "$existing" > "$RULE_PREF_FILE"
        return 0
    fi

    pref=$ROUTE_RULE_PRIORITY
    while [ "$pref" -gt 9900 ] && ip -4 rule show 2>/dev/null | grep -q "^[[:space:]]*$pref:"; do
        pref=$((pref - 1))
    done
    if [ "$pref" -le 9900 ]; then
        log_msg "ERROR: no free policy-rule priority between 9901 and $ROUTE_RULE_PRIORITY"
        return 1
    fi

    if ip -4 rule add pref "$pref" lookup "$ROUTE_TABLE" 2>> "$MODULE_LOG"; then
        echo "$pref" > "$RULE_PREF_FILE"
        log_msg "Added policy rule pref=$pref table=$ROUTE_TABLE"
        return 0
    fi
    log_msg "ERROR: failed to add policy rule pref=$pref table=$ROUTE_TABLE"
    return 1
}

build_desired_routes() {
    dev=$1
    tmp=$2
    raw="$tmp.raw"
    : > "$raw"

    get_tun_cidr "$dev" >> "$raw" 2>/dev/null
    ip -4 route show table main dev "$dev" 2>/dev/null | awk '{print $1}' >> "$raw"

    now_epoch=$(date +%s)
    case "$now_epoch" in *[!0-9]*|'') now_epoch=0;; esac
    last_discovery=0
    [ -r "$ROUTE_DISCOVERY_STAMP_FILE" ] && last_discovery=$(cat "$ROUTE_DISCOVERY_STAMP_FILE" 2>/dev/null)
    case "$last_discovery" in *[!0-9]*|'') last_discovery=0;; esac
    if [ ! -s "$DISCOVERED_ROUTES_FILE" ] || [ $((now_epoch - last_discovery)) -ge "$ROUTE_DISCOVERY_INTERVAL" ]; then
        discovered_tmp="$RUNDIR/discovered-routes.$$.tmp"
        cli_route_cidrs > "$discovered_tmp" 2>/dev/null || true
        if [ -s "$discovered_tmp" ]; then
            sort -u "$discovered_tmp" > "$DISCOVERED_ROUTES_FILE"
        fi
        rm "$discovered_tmp" 2>/dev/null || true
        echo "$now_epoch" > "$ROUTE_DISCOVERY_STAMP_FILE"
    fi
    cat "$DISCOVERED_ROUTES_FILE" >> "$raw" 2>/dev/null || true

    : > "$tmp"
    sort -u "$raw" 2>/dev/null | while IFS= read -r candidate; do
        normalized=$(normalize_ipv4_cidr "$candidate" 2>/dev/null) || continue
        route_allowed "$normalized" || continue
        echo "$normalized"
    done | sort -u > "$tmp"
    rm "$raw" 2>/dev/null
}

sync_dedicated_route_guard() {
    [ "$ROUTE_GUARD" = "1" ] || return 0
    dev=$(find_tun_device)
    [ -n "$dev" ] || {
        log_msg "WARN: EasyTier TUN device not found"
        return 1
    }

    desired="$RUNDIR/routes.desired"
    merged="$RUNDIR/routes.merged"
    actual="$RUNDIR/routes.actual"
    build_desired_routes "$dev" "$desired"
    [ -s "$desired" ] || {
        log_msg "WARN: no EasyTier IPv4 routes discovered on $dev"
        return 1
    }

    # Preserve learned overlay/proxy routes across short VPN transitions. Local physical
    # subnets are applied later as direct-route overrides and therefore never enter this cache.
    {
        cat "$desired" 2>/dev/null || true
        cat "$APPLIED_ROUTES_FILE" 2>/dev/null || true
    } | sort -u > "$merged"

    refresh_local_route_overrides "$dev"
    build_expected_route_specs "$dev" "$merged" "$LOCAL_ROUTE_OVERRIDES_FILE" "$EXPECTED_ROUTE_SPECS_FILE"
    [ -s "$EXPECTED_ROUTE_SPECS_FILE" ] || {
        log_msg "ERROR: no route specifications generated for table=$ROUTE_TABLE"
        return 1
    }

    ensure_policy_rule || return 1

    : > "$actual"
    ip -4 route show table "$ROUTE_TABLE" 2>/dev/null | awk '
        {
            iface=""
            for (i=1; i<=NF; i++) if ($i == "dev" && i < NF) { iface=$(i+1); break }
            if ($1 != "" && iface != "") {
                cidr=$1
                if (cidr !~ /\// && cidr ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/) cidr=cidr "/32"
                print cidr "|" iface
            }
        }
    ' | sort -u > "$actual"

    if cmp -s "$EXPECTED_ROUTE_SPECS_FILE" "$actual"; then
        cmp -s "$merged" "$APPLIED_ROUTES_FILE" || cp "$merged" "$APPLIED_ROUTES_FILE"
        sync_android_network_routes "$dev" "$merged" "$LOCAL_ROUTE_OVERRIDES_FILE" || true
        return 0
    fi

    removed=0
    while IFS='|' read -r cidr route_dev; do
        [ -n "$cidr" ] || continue
        if ! grep -Fqx "$cidr|$route_dev" "$EXPECTED_ROUTE_SPECS_FILE" 2>/dev/null; then
            if ip -4 route del table "$ROUTE_TABLE" "$cidr" 2>> "$MODULE_LOG"; then
                removed=$((removed + 1))
            fi
        fi
    done < "$actual"

    installed=0
    while IFS='|' read -r cidr route_dev; do
        [ -n "$cidr" ] && [ -n "$route_dev" ] || continue
        if ip -4 route replace table "$ROUTE_TABLE" "$cidr" dev "$route_dev" 2>> "$MODULE_LOG"; then
            installed=$((installed + 1))
        fi
    done < "$EXPECTED_ROUTE_SPECS_FILE"

    if [ "$installed" -gt 0 ]; then
        cp "$merged" "$APPLIED_ROUTES_FILE"
        sync_android_network_routes "$dev" "$merged" "$LOCAL_ROUTE_OVERRIDES_FILE" || true
        increment_counter "$ROUTE_SYNC_COUNT_FILE" >/dev/null
        local_count=$(grep -c . "$LOCAL_ROUTE_OVERRIDES_FILE" 2>/dev/null || true)
        case "$local_count" in *[!0-9]*|'') local_count=0;; esac
        log_msg "Reconciled $installed route(s), removed=$removed table=$ROUTE_TABLE tun=$dev local_overrides=$local_count"
        set_description "运行中 | $(framework_name) | 路由保护已启用"
        return 0
    fi

    log_msg "ERROR: failed to reconcile routes in table=$ROUTE_TABLE"
    return 1
}

cleanup_dedicated_route_guard() {
    cleanup_android_network_routes
    for table in "$ROUTE_TABLE" "$REQUESTED_ROUTE_TABLE"; do
        [ -n "$table" ] || continue
        ip -4 route flush table "$table" 2>/dev/null || true
        while :; do
            pref=$(find_existing_rule_pref "$table")
            [ -n "$pref" ] || break
            ip -4 rule del pref "$pref" 2>/dev/null || break
        done
    done
    rm "$APPLIED_ROUTES_FILE" "$DISCOVERED_ROUTES_FILE" "$ROUTE_DISCOVERY_STAMP_FILE" "$RULE_PREF_FILE" \
        "$ROUTE_TABLE_SELECTION_FILE" "$LOCAL_ROUTE_OVERRIDES_FILE" "$EXPECTED_ROUTE_SPECS_FILE"         "$ANDROID_ROUTE_SPECS_FILE" "$ANDROID_ROUTE_TABLES_FILE" \
        "$RUNDIR/routes.desired" "$RUNDIR/routes.merged" "$RUNDIR/routes.actual" 2>/dev/null || true
    return 0
}

is_xiaomi_family() {
    vendor="$(getprop ro.product.manufacturer 2>/dev/null) $(getprop ro.product.brand 2>/dev/null)"
    vendor=$(printf '%s' "$vendor" | tr '[:upper:]' '[:lower:]')
    case "$vendor" in *xiaomi*|*redmi*|*poco*) return 0;; esac
    return 1
}

route_strategy_effective() (
    strategy=""
    [ -r "$ROUTE_STRATEGY_FILE" ] && strategy=$(cat "$ROUTE_STRATEGY_FILE" 2>/dev/null)
    case "$strategy" in official|legacy) echo "$strategy" ;; *) echo "$ROUTE_STRATEGY_DEFAULT" ;; esac
)

route_mode_config_effective() {
    if [ "$(route_strategy_effective)" = legacy ]; then echo dedicated; else echo "$ROUTE_MODE"; fi
}

android_network_table_mirroring_enabled() {
    [ "$(route_strategy_effective)" = legacy ]
}

route_mode_active() {
    mode=""
    [ -r "$ROUTE_MODE_ACTIVE_FILE" ] && mode=$(cat "$ROUTE_MODE_ACTIVE_FILE" 2>/dev/null)
    case "$mode" in upstream|target-main|dedicated) echo "$mode"; return 0;; esac
    select_route_mode
}

select_route_mode() {
    if [ "$(route_strategy_effective)" = legacy ]; then
        echo dedicated
        return 0
    fi
    case "$ROUTE_MODE" in
        upstream|target-main|dedicated) echo "$ROUTE_MODE"; return 0;;
    esac
    override=""
    [ -r "$ROUTE_MODE_RUNTIME_OVERRIDE_FILE" ] && override=$(cat "$ROUTE_MODE_RUNTIME_OVERRIDE_FILE" 2>/dev/null)
    case "$override" in upstream|target-main|dedicated) echo "$override"; return 0;; esac
    # The official EasyTier Magisk route works across the tested devices and VPNs.
    # Start from that least-invasive mode everywhere; health probes may promote to
    # target-main or dedicated only when the current ROM/network actually needs it.
    echo upstream
}

policy_lookup_table() {
    case "$(route_mode_active)" in
        upstream|target-main) echo main ;;
        *) echo "$ROUTE_TABLE" ;;
    esac
}

find_upstream_main_rule_pref() {
    ip -4 rule show 2>/dev/null | awk '
        $0 ~ /^[[:space:]]*[0-9]+:[[:space:]]+from all lookup main[[:space:]]*$/ {
            gsub(":", "", $1); print $1; exit
        }
    '
}

ensure_upstream_main_rule() {
    existing=$(find_upstream_main_rule_pref)
    [ -n "$existing" ] && return 0
    if ip -4 rule add from all lookup main 2>> "$MODULE_LOG"; then
        pref=$(find_upstream_main_rule_pref)
        [ -n "$pref" ] && echo "$pref" > "$UPSTREAM_MAIN_RULE_FILE"
        log_msg "Added upstream-compatible rule lookup main pref=${pref:-auto}"
        return 0
    fi
    log_msg "ERROR: failed to add upstream-compatible lookup main rule"
    return 1
}

cleanup_upstream_main_rule() {
    if [ -r "$UPSTREAM_MAIN_RULE_FILE" ]; then
        pref=$(cat "$UPSTREAM_MAIN_RULE_FILE" 2>/dev/null)
        case "$pref" in *[!0-9]*|'') ;; *) ip -4 rule del pref "$pref" 2>/dev/null || true;; esac
    fi
    rm "$UPSTREAM_MAIN_RULE_FILE" 2>/dev/null || true
}

cleanup_target_main_rules() {
    if [ -r "$TARGET_MAIN_RULES_FILE" ]; then
        while IFS='|' read -r pref cidr; do
            case "$pref" in *[!0-9]*|'') continue;; esac
            ip -4 rule del pref "$pref" 2>/dev/null || true
        done < "$TARGET_MAIN_RULES_FILE"
    fi
    rm "$TARGET_MAIN_RULES_FILE" 2>/dev/null || true
}

build_cached_overlay_routes() {
    dev=$1
    desired="$RUNDIR/routes.desired"
    merged="$RUNDIR/routes.merged"
    build_desired_routes "$dev" "$desired"
    [ -s "$desired" ] || return 1
    {
        cat "$desired" 2>/dev/null || true
        cat "$APPLIED_ROUTES_FILE" 2>/dev/null || true
    } | sort -u > "$merged"
    cp "$merged" "$APPLIED_ROUTES_FILE"
    echo "$merged"
}

sync_upstream_route_guard() {
    dev=$(find_tun_device 2>/dev/null)
    [ -n "$dev" ] || return 1
    build_cached_overlay_routes "$dev" >/dev/null 2>&1 || true
    ensure_upstream_main_rule || return 1
    set_description "运行中 | $(framework_name) | 上游兼容路由"
    return 0
}

sync_target_main_route_guard() {
    dev=$(find_tun_device 2>/dev/null)
    [ -n "$dev" ] || return 1
    merged=$(build_cached_overlay_routes "$dev") || {
        log_msg "WARN: target-main mode has no EasyTier routes"
        return 1
    }
    desired_rules="$RUNDIR/target-main-rules.$$.tmp"
    : > "$desired_rules"
    old_rules="$RUNDIR/target-main-old.$$.tmp"
    cp "$TARGET_MAIN_RULES_FILE" "$old_rules" 2>/dev/null || : > "$old_rules"
    cleanup_target_main_rules

    pref=$ROUTE_RULE_PRIORITY
    while IFS= read -r cidr; do
        [ -n "$cidr" ] || continue
        while [ "$pref" -gt 9900 ] && ip -4 rule show 2>/dev/null | grep -q "^[[:space:]]*$pref:"; do
            pref=$((pref - 1))
        done
        [ "$pref" -gt 9900 ] || break
        if ip -4 rule add pref "$pref" to "$cidr" lookup main 2>> "$MODULE_LOG"; then
            echo "$pref|$cidr" >> "$desired_rules"
            pref=$((pref - 1))
        fi
    done < "$merged"
    mv "$desired_rules" "$TARGET_MAIN_RULES_FILE"
    rm "$old_rules" 2>/dev/null || true
    count=$(grep -c . "$TARGET_MAIN_RULES_FILE" 2>/dev/null || true)
    case "$count" in *[!0-9]*|'') count=0;; esac
    [ "$count" -gt 0 ] || return 1
    log_msg "Synced target-main rules count=$count"
    set_description "运行中 | $(framework_name) | VPN兼容主表路由"
    return 0
}

cleanup_all_route_modes() {
    cleanup_android_network_routes
    cleanup_upstream_main_rule
    cleanup_target_main_rules
    cleanup_dedicated_route_guard
}

sync_route_guard() {
    [ "$ROUTE_GUARD" = "1" ] || return 0
    if ! core_running; then
        cleanup_all_route_modes
        rm "$ROUTE_MODE_ACTIVE_FILE" 2>/dev/null || true
        return 1
    fi
    desired_mode=$(select_route_mode)
    current_mode=""
    [ -r "$ROUTE_MODE_ACTIVE_FILE" ] && current_mode=$(cat "$ROUTE_MODE_ACTIVE_FILE" 2>/dev/null)
    if [ "$current_mode" != "$desired_mode" ]; then
        cleanup_all_route_modes
        echo "$desired_mode" > "$ROUTE_MODE_ACTIVE_FILE"
        log_msg "Route mode switched ${current_mode:-none} -> $desired_mode"
    fi
    case "$desired_mode" in
        upstream) sync_upstream_route_guard ;;
        target-main) sync_target_main_route_guard ;;
        *) sync_dedicated_route_guard ;;
    esac
}

try_alternate_route_mode() {
    [ "$(route_strategy_effective)" = official ] || return 1
    [ "$ROUTE_MODE" = "auto" ] && [ "$ROUTE_AUTO_SWITCH_ENABLED" = "1" ] || return 1
    now_epoch=$(date +%s)
    case "$now_epoch" in *[!0-9]*|'') now_epoch=0;; esac
    last_switch=0
    [ -r "$ROUTE_MODE_LAST_SWITCH_FILE" ] && last_switch=$(cat "$ROUTE_MODE_LAST_SWITCH_FILE" 2>/dev/null)
    case "$last_switch" in *[!0-9]*|'') last_switch=0;; esac
    [ $((now_epoch - last_switch)) -ge "$ROUTE_AUTO_SWITCH_COOLDOWN" ] || return 1
    current=$(route_mode_active)
    case "$current" in
        upstream) alternate=target-main ;;
        target-main) alternate=dedicated ;;
        dedicated) alternate=upstream ;;
        *) alternate=upstream ;;
    esac
    echo "$alternate" > "$ROUTE_MODE_RUNTIME_OVERRIDE_FILE"
    echo "$now_epoch" > "$ROUTE_MODE_LAST_SWITCH_FILE"
    log_msg "Auto route-mode fallback $current -> $alternate"
    sync_route_guard
}

cleanup_route_guard() {
    cleanup_all_route_modes
    rm "$ROUTE_MODE_ACTIVE_FILE" "$ROUTE_MODE_RUNTIME_OVERRIDE_FILE" "$ROUTE_MODE_LAST_SWITCH_FILE" 2>/dev/null || true
    return 0
}

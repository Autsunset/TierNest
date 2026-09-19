#!/system/bin/sh

# TierNest hotspot support has two deliberately separate parts:
# 1. legacy cleanup for beta.15 and older artifacts;
# 2. an opt-in, outbound-only hotspot client access mode.
#
# The outbound-only mode never advertises the hotspot subnet to EasyTier. It
# source-NATs hotspot clients only when the destination is an active EasyTier
# virtual/proxy CIDR, accepts replies only for established flows, and explicitly
# drops new EasyTier -> hotspot forwarded connections.

# Legacy beta.15 chain names. Keep these only for safe upgrade cleanup.
HOTSPOT_NAT_CHAIN=TN_HS_NAT
HOTSPOT_FWD_CHAIN=TN_HS_FWD

# Outbound-only chain names introduced in beta.17 and retained in beta.18.
HOTSPOT_ACCESS_NAT_CHAIN=TN_HS_OUT_NAT
HOTSPOT_ACCESS_FWD_CHAIN=TN_HS_OUT_FWD

hotspot_log() {
    rotate_log "$HOTSPOT_LOG" 1048576
    printf '%s %s\n' "$(now)" "$*" >> "$HOTSPOT_LOG"
    log_msg "HOTSPOT-OUT: $*"
}

resolve_iptables_bin() {
    [ -n "${IPTABLES_BIN_CACHE:-}" ] && [ -x "$IPTABLES_BIN_CACHE" ] && return 0
    for candidate in /system/bin/iptables /system/xbin/iptables /vendor/bin/iptables; do
        [ -x "$candidate" ] && { IPTABLES_BIN_CACHE=$candidate; return 0; }
    done
    IPTABLES_BIN_CACHE=$(command -v iptables 2>/dev/null) || return 1
}

run_iptables() {
    resolve_iptables_bin || return 127
    "$IPTABLES_BIN_CACHE" -w 2 "$@" 2>/dev/null || "$IPTABLES_BIN_CACHE" "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Legacy cleanup (beta.15 and older)
# ---------------------------------------------------------------------------

write_legacy_sysctl_value() {
    relative=$1
    value=$2
    file="$SYSCTL_ROOT/$relative"
    [ -e "$file" ] || return 1
    if [ -w "$file" ]; then
        printf '%s\n' "$value" > "$file" 2>/dev/null && return 0
    fi
    [ "$SYSCTL_ROOT" = /proc/sys ] || return 1
    sysctl -w "$(printf '%s' "$relative" | tr / .)=$value" >/dev/null 2>&1
}

legacy_hotspot_interface_active() {
    [ -r "$HOTSPOT_STATE_FILE" ] || return 1
    IFS='|' read -r iface rest < "$HOTSPOT_STATE_FILE"
    [ -n "$iface" ] || return 1
    ip -o -4 addr show dev "$iface" 2>/dev/null | grep -q ' inet '
}

cleanup_hotspot_policy_rules() {
    if [ -r "$HOTSPOT_RULE_PREF_FILE" ]; then
        while IFS='|' read -r pref rest; do
            case "$pref" in *[!0-9]*|'') continue;; esac
            ip -4 rule del pref "$pref" 2>/dev/null || true
        done < "$HOTSPOT_RULE_PREF_FILE"
    fi
    rm "$HOTSPOT_RULE_PREF_FILE" 2>/dev/null || true
}

restore_hotspot_sysctl_state() {
    [ -r "$HOTSPOT_SYSCTL_STATE_FILE" ] || return 0
    while IFS='|' read -r relative value; do
        case "$relative:$value" in
            net/ipv4/conf/*/rp_filter:[012]) write_legacy_sysctl_value "$relative" "$value" || true ;;
        esac
    done < "$HOTSPOT_SYSCTL_STATE_FILE"
    rm "$HOTSPOT_SYSCTL_STATE_FILE" 2>/dev/null || true
}

restore_hotspot_ip_forward_if_safe() {
    [ -r "$HOTSPOT_IP_FORWARD_PREV_FILE" ] || return 0
    legacy_hotspot_interface_active && return 0
    previous=$(cat "$HOTSPOT_IP_FORWARD_PREV_FILE" 2>/dev/null)
    current=$(cat "$SYSCTL_ROOT/net/ipv4/ip_forward" 2>/dev/null)
    [ "$previous" = 0 ] && [ "$current" = 1 ] \
        && write_legacy_sysctl_value net/ipv4/ip_forward 0 || true
    rm "$HOTSPOT_IP_FORWARD_PREV_FILE" 2>/dev/null || true
}

legacy_hotspot_artifacts_present() {
    [ -e "$HOTSPOT_STATE_FILE" ] || [ -e "$HOTSPOT_RULE_PREF_FILE" ] \
        || [ -e "$HOTSPOT_SYSCTL_STATE_FILE" ] || [ -e "$HOTSPOT_IP_FORWARD_PREV_FILE" ] \
        || [ -e "$HOTSPOT_CONFLICT_FILE" ] || [ -e "$HOTSPOT_OVERRIDE_FILE" ]
}

cleanup_hotspot_forwarding() {
    cleanup_hotspot_policy_rules
    if resolve_iptables_bin; then
        cleanup_count=0
        while [ "$cleanup_count" -lt 16 ] && run_iptables -t nat -C POSTROUTING -j "$HOTSPOT_NAT_CHAIN"; do
            run_iptables -t nat -D POSTROUTING -j "$HOTSPOT_NAT_CHAIN" || break
            cleanup_count=$((cleanup_count + 1))
        done
        cleanup_count=0
        while [ "$cleanup_count" -lt 16 ] && run_iptables -C FORWARD -j "$HOTSPOT_FWD_CHAIN"; do
            run_iptables -D FORWARD -j "$HOTSPOT_FWD_CHAIN" || break
            cleanup_count=$((cleanup_count + 1))
        done
        run_iptables -t nat -F "$HOTSPOT_NAT_CHAIN" || true
        run_iptables -F "$HOTSPOT_FWD_CHAIN" || true
        run_iptables -t nat -X "$HOTSPOT_NAT_CHAIN" || true
        run_iptables -X "$HOTSPOT_FWD_CHAIN" || true
    fi
    restore_hotspot_sysctl_state
    restore_hotspot_ip_forward_if_safe
    rm "$HOTSPOT_STATE_FILE" "$HOTSPOT_CONFLICT_FILE" "$HOTSPOT_OVERRIDE_FILE" \
        "$HOTSPOT_REAPPLY_COUNT_FILE" "$HOTSPOT_LAST_APPLY_FILE" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Outbound-only hotspot client access
# ---------------------------------------------------------------------------

hotspot_access_effective_enabled() {
    if [ -r "$HOTSPOT_ACCESS_OVERRIDE_FILE" ]; then
        value=$(cat "$HOTSPOT_ACCESS_OVERRIDE_FILE" 2>/dev/null)
        case "$value" in
            on) echo 1; return 0 ;;
            off) echo 0; return 0 ;;
        esac
    fi
    [ "$HOTSPOT_CLIENT_ACCESS_ENABLED" = 1 ] && echo 1 || echo 0
}

hotspot_access_lock_acquire() {
    if mkdir "$HOTSPOT_ACCESS_LOCK_DIR" 2>/dev/null; then
        echo $$ > "$HOTSPOT_ACCESS_LOCK_DIR/pid"
        return 0
    fi

    owner=""
    [ -r "$HOTSPOT_ACCESS_LOCK_DIR/pid" ] && owner=$(cat "$HOTSPOT_ACCESS_LOCK_DIR/pid" 2>/dev/null)
    case "$owner" in
        *[!0-9]*|'') owner="" ;;
    esac
    if [ -z "$owner" ] || ! kill -0 "$owner" 2>/dev/null; then
        rm "$HOTSPOT_ACCESS_LOCK_DIR/pid" 2>/dev/null || true
        rmdir "$HOTSPOT_ACCESS_LOCK_DIR" 2>/dev/null || true
        mkdir "$HOTSPOT_ACCESS_LOCK_DIR" 2>/dev/null || return 1
        echo $$ > "$HOTSPOT_ACCESS_LOCK_DIR/pid"
        return 0
    fi
    return 1
}

hotspot_access_lock_release() {
    rm "$HOTSPOT_ACCESS_LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$HOTSPOT_ACCESS_LOCK_DIR" 2>/dev/null || true
}

hotspot_access_set_error() {
    error_code=$1
    shift
    error_message=$*
    previous=""
    [ -r "$HOTSPOT_ACCESS_ERROR_FILE" ] && previous=$(cat "$HOTSPOT_ACCESS_ERROR_FILE" 2>/dev/null)
    current="$error_code|$error_message"
    printf '%s\n' "$current" > "$HOTSPOT_ACCESS_ERROR_FILE"
    [ "$previous" = "$current" ] || hotspot_log "status=$error_code detail=$error_message"
}

hotspot_access_clear_error() {
    rm "$HOTSPOT_ACCESS_ERROR_FILE" 2>/dev/null || true
}

is_private_ipv4() (
    hotspot_ip=$1
    old_ifs=$IFS
    IFS=.
    set -- $hotspot_ip
    IFS=$old_ifs
    [ "$#" -eq 4 ] || return 1
    case "$1" in
        10) return 0 ;;
        172) [ "$2" -ge 16 ] 2>/dev/null && [ "$2" -le 31 ] 2>/dev/null; return ;;
        192) [ "$2" = 168 ]; return ;;
    esac
    return 1
)

interface_is_default_uplink() {
    hotspot_iface=$1
    ip -4 route show table all default 2>/dev/null \
        | awk -v dev="$hotspot_iface" '$0 ~ (" dev " dev "([[:space:]]|$)") {found=1} END {exit !found}'
}

hotspot_access_interface_allowed() (
    hotspot_iface=$1
    case "$hotspot_iface" in
        ap[0-9]*|ap_*|apbr*|swlan[0-9]*|softap[0-9]*|br_tether*) return 0 ;;
        rndis[0-9]*|usb[0-9]*|eth[0-9]*) [ "$HOTSPOT_ACCESS_INCLUDE_USB" = 1 ]; return ;;
    esac
    return 1
)

interface_is_up() {
    hotspot_iface=$1
    ip link show dev "$hotspot_iface" 2>/dev/null | head -n 1 | grep -q '<[^>]*UP[,>]'
}

interface_ipv4_cidr() {
    hotspot_iface=$1
    ip -o -4 addr show dev "$hotspot_iface" 2>/dev/null | awk '$3 == "inet" {print $4; exit}'
}

find_hotspot_access_context() {
    if [ "$HOTSPOT_ACCESS_INTERFACE" != auto ] && [ -n "$HOTSPOT_ACCESS_INTERFACE" ]; then
        hotspot_iface=$HOTSPOT_ACCESS_INTERFACE
        hotspot_addr_cidr=$(interface_ipv4_cidr "$hotspot_iface")
        [ -n "$hotspot_addr_cidr" ] || return 1
        hotspot_gateway=${hotspot_addr_cidr%/*}
        is_private_ipv4 "$hotspot_gateway" || return 1
        hotspot_network=$hotspot_addr_cidr
        if [ "$HOTSPOT_ACCESS_CIDR" != auto ] && [ -n "$HOTSPOT_ACCESS_CIDR" ]; then
            hotspot_network=$HOTSPOT_ACCESS_CIDR
        fi
        hotspot_network=$(normalize_ipv4_cidr "$hotspot_network" 2>/dev/null) || return 1
        printf '%s|%s|%s\n' "$hotspot_iface" "$hotspot_network" "$hotspot_gateway"
        return 0
    fi

    ip -o -4 addr show 2>/dev/null | while read -r index hotspot_iface family hotspot_addr_cidr rest; do
        [ "$family" = inet ] || continue
        hotspot_iface=${hotspot_iface%@*}
        hotspot_access_interface_allowed "$hotspot_iface" || continue
        interface_is_up "$hotspot_iface" || continue
        hotspot_gateway=${hotspot_addr_cidr%/*}
        is_private_ipv4 "$hotspot_gateway" || continue
        interface_is_default_uplink "$hotspot_iface" && continue
        hotspot_network=$(normalize_ipv4_cidr "$hotspot_addr_cidr" 2>/dev/null) || continue
        hotspot_priority=30
        case "$hotspot_iface" in
            ap[0-9]*|ap_*|apbr*|swlan[0-9]*|softap[0-9]*|br_tether*) hotspot_priority=10 ;;
            rndis[0-9]*|usb[0-9]*) hotspot_priority=20 ;;
        esac
        printf '%s|%s|%s|%s\n' "$hotspot_priority" "$hotspot_iface" "$hotspot_network" "$hotspot_gateway"
    done | sort -t'|' -k1,1n | awk -F'|' 'NR == 1 {print $2 "|" $3 "|" $4}'
}

cidrs_overlap() (
    first=$1
    second=$2
    first_ip=${first%/*}
    first_prefix=${first#*/}
    second_ip=${second%/*}
    second_prefix=${second#*/}
    case "$first_prefix$second_prefix" in *[!0-9]*) return 1;; esac
    common_prefix=$first_prefix
    [ "$second_prefix" -lt "$common_prefix" ] && common_prefix=$second_prefix
    first_common=$(normalize_ipv4_cidr "$first_ip/$common_prefix" 2>/dev/null) || return 1
    second_common=$(normalize_ipv4_cidr "$second_ip/$common_prefix" 2>/dev/null) || return 1
    [ "$first_common" = "$second_common" ]
)

configured_proxy_network_cidrs() (
    if [ -r "$COMMAND_ARGS" ]; then
        awk '
            {
                for (i=1; i<=NF; i++) {
                    token=$i
                    if (want) { print token; want=0; continue }
                    if (token == "-n" || token == "--proxy-networks") { want=1; continue }
                    if (token ~ /^--proxy-networks=/) {
                        sub(/^--proxy-networks=/, "", token)
                        print token
                    }
                }
            }
        ' "$COMMAND_ARGS" 2>/dev/null \
            | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])' 2>/dev/null
        return 0
    fi
    [ -r "$CONFIG_FILE" ] || return 0
    awk '
        /^[[:space:]]*\[/ { if (capture) exit; section=1 }
        !section && /^[[:space:]]*proxy_networks[[:space:]]*=/ { capture=1 }
        capture { print; if ($0 ~ /]/) exit }
    ' "$CONFIG_FILE" 2>/dev/null \
        | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])' 2>/dev/null
)

hotspot_subnet_is_advertised() (
    hotspot_network=$1
    configured_proxy_network_cidrs | while IFS= read -r proxy_cidr; do
        normalized_proxy=$(normalize_ipv4_cidr "$proxy_cidr" 2>/dev/null) || continue
        if cidrs_overlap "$hotspot_network" "$normalized_proxy"; then
            echo "$normalized_proxy"
            break
        fi
    done
)

hotspot_access_ip_forward_ready() (
    [ "$(cat "$SYSCTL_ROOT/net/ipv4/ip_forward" 2>/dev/null)" = 1 ]
)

route_table_has_tun_route() (
    lookup_table=$1
    target_cidr=$2
    tun_dev=$3
    ip -4 route show table "$lookup_table" 2>/dev/null \
        | awk -v cidr="$target_cidr" -v dev="$tun_dev" '
            $1 == cidr {
                for (i=1; i<=NF; i++) if ($i == "dev" && i < NF && $(i+1) == dev) found=1
            }
            END {exit !found}
        '
)

build_hotspot_access_targets() (
    hotspot_network=$1
    tun_dev=$2
    lookup_table=$3
    output_file=$4
    candidates="$RUNDIR/hotspot-access-candidates.$$.tmp"
    raw="$RUNDIR/hotspot-access-candidates.$$.raw"
    build_desired_routes "$tun_dev" "$raw" >/dev/null 2>&1 || true
    {
        cat "$raw" 2>/dev/null || true
        cat "$APPLIED_ROUTES_FILE" 2>/dev/null || true
    } | sort -u > "$candidates"
    : > "$output_file"
    while IFS= read -r target_cidr; do
        [ -n "$target_cidr" ] || continue
        normalized_target=$(normalize_ipv4_cidr "$target_cidr" 2>/dev/null) || continue
        route_allowed "$normalized_target" || continue
        cidrs_overlap "$hotspot_network" "$normalized_target" && continue
        route_table_has_tun_route "$lookup_table" "$normalized_target" "$tun_dev" || continue
        echo "$normalized_target" >> "$output_file"
    done < "$candidates"
    sort -u "$output_file" -o "$output_file" 2>/dev/null || true
    rm "$candidates" "$raw" 2>/dev/null || true
    [ -s "$output_file" ]
)

hotspot_access_rule_present() (
    pref=$1
    hotspot_iface=$2
    target_cidr=$3
    lookup_table=$4
    ip -4 rule show 2>/dev/null | awk \
        -v pref="$pref" -v iface="$hotspot_iface" -v cidr="$target_cidr" -v table="$lookup_table" '
        $1 == pref ":" && $0 ~ ("iif " iface "([[:space:]]|$)") \
            && $0 ~ ("to " cidr "([[:space:]]|$)") \
            && $0 ~ ("lookup " table "([[:space:]]|$)") {found=1}
        END {exit !found}
    '
)

remove_hotspot_access_policy_rules_unlocked() (
    [ -r "$HOTSPOT_ACCESS_RULES_FILE" ] || return 0
    while IFS='|' read -r pref hotspot_iface target_cidr lookup_table; do
        case "$pref" in *[!0-9]*|'') continue;; esac
        if hotspot_access_rule_present "$pref" "$hotspot_iface" "$target_cidr" "$lookup_table"; then
            ip -4 rule del pref "$pref" iif "$hotspot_iface" to "$target_cidr" lookup "$lookup_table" 2>/dev/null \
                || { hotspot_access_rule_present "$pref" "$hotspot_iface" "$target_cidr" "$lookup_table" \
                    && ip -4 rule del pref "$pref" 2>/dev/null || true; }
        fi
    done < "$HOTSPOT_ACCESS_RULES_FILE"
    rm "$HOTSPOT_ACCESS_RULES_FILE" 2>/dev/null || true
)

remove_hotspot_access_hooks_unlocked() (
    resolve_iptables_bin || { rm "$HOTSPOT_ACCESS_HOOKS_FILE" 2>/dev/null || true; return 0; }
    if [ -r "$HOTSPOT_ACCESS_HOOKS_FILE" ]; then
        while IFS='|' read -r hook_type first second; do
            case "$hook_type" in
                nat)
                    cleanup_count=0
                    while [ "$cleanup_count" -lt 8 ] && run_iptables -t nat -C POSTROUTING -s "$first" -o "$second" -j "$HOTSPOT_ACCESS_NAT_CHAIN"; do
                        run_iptables -t nat -D POSTROUTING -s "$first" -o "$second" -j "$HOTSPOT_ACCESS_NAT_CHAIN" || break
                        cleanup_count=$((cleanup_count + 1))
                    done
                    ;;
                fwd-out)
                    cleanup_count=0
                    while [ "$cleanup_count" -lt 8 ] && run_iptables -C FORWARD -i "$first" -o "$second" -j "$HOTSPOT_ACCESS_FWD_CHAIN"; do
                        run_iptables -D FORWARD -i "$first" -o "$second" -j "$HOTSPOT_ACCESS_FWD_CHAIN" || break
                        cleanup_count=$((cleanup_count + 1))
                    done
                    ;;
                fwd-in)
                    cleanup_count=0
                    while [ "$cleanup_count" -lt 8 ] && run_iptables -C FORWARD -i "$first" -o "$second" -j "$HOTSPOT_ACCESS_FWD_CHAIN"; do
                        run_iptables -D FORWARD -i "$first" -o "$second" -j "$HOTSPOT_ACCESS_FWD_CHAIN" || break
                        cleanup_count=$((cleanup_count + 1))
                    done
                    ;;
            esac
        done < "$HOTSPOT_ACCESS_HOOKS_FILE"
    fi
    # Clean experimental/beta leftovers that used an unscoped parent jump.
    cleanup_count=0
    while [ "$cleanup_count" -lt 8 ] && run_iptables -t nat -C POSTROUTING -j "$HOTSPOT_ACCESS_NAT_CHAIN"; do
        run_iptables -t nat -D POSTROUTING -j "$HOTSPOT_ACCESS_NAT_CHAIN" || break
        cleanup_count=$((cleanup_count + 1))
    done
    cleanup_count=0
    while [ "$cleanup_count" -lt 8 ] && run_iptables -C FORWARD -j "$HOTSPOT_ACCESS_FWD_CHAIN"; do
        run_iptables -D FORWARD -j "$HOTSPOT_ACCESS_FWD_CHAIN" || break
        cleanup_count=$((cleanup_count + 1))
    done
    rm "$HOTSPOT_ACCESS_HOOKS_FILE" 2>/dev/null || true
)

cleanup_hotspot_access_unlocked() {
    had_state=0
    [ -e "$HOTSPOT_ACCESS_STATE_FILE" ] && had_state=1
    remove_hotspot_access_hooks_unlocked
    remove_hotspot_access_policy_rules_unlocked
    if resolve_iptables_bin; then
        run_iptables -t nat -F "$HOTSPOT_ACCESS_NAT_CHAIN" || true
        run_iptables -F "$HOTSPOT_ACCESS_FWD_CHAIN" || true
        run_iptables -t nat -X "$HOTSPOT_ACCESS_NAT_CHAIN" || true
        run_iptables -X "$HOTSPOT_ACCESS_FWD_CHAIN" || true
    fi
    rm "$HOTSPOT_ACCESS_STATE_FILE" "$HOTSPOT_ACCESS_TARGETS_FILE" "$HOTSPOT_ACCESS_HOOKS_FILE" 2>/dev/null || true
    [ "$had_state" = 1 ] && hotspot_log "outbound-only access rules removed"
}

cleanup_hotspot_access() {
    hotspot_access_lock_acquire || return 0
    cleanup_hotspot_access_unlocked
    hotspot_access_lock_release
}

hotspot_access_policy_rules_ready() (
    [ -s "$HOTSPOT_ACCESS_RULES_FILE" ] || return 1
    while IFS='|' read -r pref hotspot_iface target_cidr lookup_table; do
        hotspot_access_rule_present "$pref" "$hotspot_iface" "$target_cidr" "$lookup_table" || return 1
    done < "$HOTSPOT_ACCESS_RULES_FILE"
)

hotspot_access_rules_ready() (
    hotspot_iface=$1
    hotspot_network=$2
    tun_dev=$3
    desired_targets=$4
    cmp -s "$desired_targets" "$HOTSPOT_ACCESS_TARGETS_FILE" 2>/dev/null || return 1
    hotspot_access_policy_rules_ready || return 1
    run_iptables -t nat -C POSTROUTING -s "$hotspot_network" -o "$tun_dev" -j "$HOTSPOT_ACCESS_NAT_CHAIN" || return 1
    run_iptables -C FORWARD -i "$hotspot_iface" -o "$tun_dev" -j "$HOTSPOT_ACCESS_FWD_CHAIN" || return 1
    run_iptables -C FORWARD -i "$tun_dev" -o "$hotspot_iface" -j "$HOTSPOT_ACCESS_FWD_CHAIN" || return 1
    while IFS= read -r target_cidr; do
        [ -n "$target_cidr" ] || continue
        run_iptables -t nat -C "$HOTSPOT_ACCESS_NAT_CHAIN" -s "$hotspot_network" -d "$target_cidr" -o "$tun_dev" -j MASQUERADE || return 1
        run_iptables -C "$HOTSPOT_ACCESS_FWD_CHAIN" -i "$hotspot_iface" -o "$tun_dev" -s "$hotspot_network" -d "$target_cidr" -j ACCEPT || return 1
    done < "$desired_targets"
    run_iptables -C "$HOTSPOT_ACCESS_FWD_CHAIN" -i "$tun_dev" -o "$hotspot_iface" -d "$hotspot_network" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT \
        || run_iptables -C "$HOTSPOT_ACCESS_FWD_CHAIN" -i "$tun_dev" -o "$hotspot_iface" -d "$hotspot_network" -m state --state ESTABLISHED,RELATED -j ACCEPT \
        || return 1
    run_iptables -C "$HOTSPOT_ACCESS_FWD_CHAIN" -i "$tun_dev" -o "$hotspot_iface" -d "$hotspot_network" -j DROP || return 1
)

install_hotspot_access_policy_rules_unlocked() (
    hotspot_iface=$1
    lookup_table=$2
    desired_targets=$3
    installed="$RUNDIR/hotspot-access-rules.$$.tmp"
    : > "$installed"
    pref=$HOTSPOT_ACCESS_RULE_PRIORITY
    while IFS= read -r target_cidr; do
        [ -n "$target_cidr" ] || continue
        while [ "$pref" -ge "$HOTSPOT_ACCESS_RULE_PRIORITY_MIN" ] \
            && ip -4 rule show 2>/dev/null | grep -q "^[[:space:]]*$pref:"; do
            pref=$((pref - 1))
        done
        if [ "$pref" -lt "$HOTSPOT_ACCESS_RULE_PRIORITY_MIN" ]; then
            rm "$installed" 2>/dev/null || true
            return 1
        fi
        if ip -4 rule add pref "$pref" iif "$hotspot_iface" to "$target_cidr" lookup "$lookup_table" 2>> "$HOTSPOT_LOG"; then
            printf '%s|%s|%s|%s\n' "$pref" "$hotspot_iface" "$target_cidr" "$lookup_table" >> "$installed"
            pref=$((pref - 1))
        else
            while IFS='|' read -r added_pref added_iface added_cidr added_table; do
                hotspot_access_rule_present "$added_pref" "$added_iface" "$added_cidr" "$added_table" \
                    && ip -4 rule del pref "$added_pref" 2>/dev/null || true
            done < "$installed"
            rm "$installed" 2>/dev/null || true
            return 1
        fi
    done < "$desired_targets"
    mv "$installed" "$HOTSPOT_ACCESS_RULES_FILE"
)

apply_hotspot_access_rules_unlocked() (
    hotspot_iface=$1
    hotspot_network=$2
    tun_dev=$3
    lookup_table=$4
    desired_targets=$5

    resolve_iptables_bin || return 1
    remove_hotspot_access_hooks_unlocked
    remove_hotspot_access_policy_rules_unlocked

    run_iptables -t nat -N "$HOTSPOT_ACCESS_NAT_CHAIN" || true
    run_iptables -N "$HOTSPOT_ACCESS_FWD_CHAIN" || true
    run_iptables -t nat -F "$HOTSPOT_ACCESS_NAT_CHAIN" || return 1
    run_iptables -F "$HOTSPOT_ACCESS_FWD_CHAIN" || return 1

    while IFS= read -r target_cidr; do
        [ -n "$target_cidr" ] || continue
        run_iptables -t nat -A "$HOTSPOT_ACCESS_NAT_CHAIN" -s "$hotspot_network" -d "$target_cidr" -o "$tun_dev" -j MASQUERADE || return 1
        run_iptables -A "$HOTSPOT_ACCESS_FWD_CHAIN" -i "$hotspot_iface" -o "$tun_dev" -s "$hotspot_network" -d "$target_cidr" -j ACCEPT || return 1
    done < "$desired_targets"

    run_iptables -A "$HOTSPOT_ACCESS_FWD_CHAIN" -i "$tun_dev" -o "$hotspot_iface" -d "$hotspot_network" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT \
        || run_iptables -A "$HOTSPOT_ACCESS_FWD_CHAIN" -i "$tun_dev" -o "$hotspot_iface" -d "$hotspot_network" -m state --state ESTABLISHED,RELATED -j ACCEPT \
        || return 1
    # Privacy guarantee: never allow a new EasyTier-side forwarded connection to
    # reach a hotspot client, even if a later Android tethering chain would accept it.
    run_iptables -A "$HOTSPOT_ACCESS_FWD_CHAIN" -i "$tun_dev" -o "$hotspot_iface" -d "$hotspot_network" -j DROP || return 1

    install_hotspot_access_policy_rules_unlocked "$hotspot_iface" "$lookup_table" "$desired_targets" || return 1

    # Publish narrowly-scoped parent hooks last. Recording the intended hooks
    # first makes a partially interrupted apply removable on the next pass.
    {
        printf 'nat|%s|%s\n' "$hotspot_network" "$tun_dev"
        printf 'fwd-out|%s|%s\n' "$hotspot_iface" "$tun_dev"
        printf 'fwd-in|%s|%s\n' "$tun_dev" "$hotspot_iface"
    } > "$HOTSPOT_ACCESS_HOOKS_FILE"
    run_iptables -t nat -I POSTROUTING 1 -s "$hotspot_network" -o "$tun_dev" -j "$HOTSPOT_ACCESS_NAT_CHAIN" || return 1
    run_iptables -I FORWARD 1 -i "$hotspot_iface" -o "$tun_dev" -j "$HOTSPOT_ACCESS_FWD_CHAIN" || return 1
    run_iptables -I FORWARD 1 -i "$tun_dev" -o "$hotspot_iface" -j "$HOTSPOT_ACCESS_FWD_CHAIN" || return 1
)

sync_hotspot_access_unlocked() (
    enabled=$(hotspot_access_effective_enabled)
    if [ "$enabled" != 1 ]; then
        cleanup_hotspot_access_unlocked
        hotspot_access_clear_error
        return 0
    fi

    core_running || {
        cleanup_hotspot_access_unlocked
        hotspot_access_set_error waiting-core "EasyTier core is not running"
        return 0
    }

    tun_dev=$(find_tun_device 2>/dev/null)
    [ -n "$tun_dev" ] || {
        cleanup_hotspot_access_unlocked
        hotspot_access_set_error waiting-tun "EasyTier TUN device is unavailable"
        return 0
    }

    hotspot_context=$(find_hotspot_access_context 2>/dev/null)
    [ -n "$hotspot_context" ] || {
        cleanup_hotspot_access_unlocked
        hotspot_access_set_error waiting-hotspot "No high-confidence Android hotspot interface is active"
        return 0
    }
    old_ifs=$IFS
    IFS='|'
    set -- $hotspot_context
    IFS=$old_ifs
    hotspot_iface=$1
    hotspot_network=$2
    hotspot_gateway=$3

    advertised=$(hotspot_subnet_is_advertised "$hotspot_network" 2>/dev/null || true)
    if [ -n "$advertised" ]; then
        cleanup_hotspot_access_unlocked
        hotspot_access_set_error subnet-advertised "hotspot=$hotspot_network overlaps proxy_networks=$advertised; remove it to keep access one-way"
        return 1
    fi

    hotspot_access_ip_forward_ready || {
        cleanup_hotspot_access_unlocked
        hotspot_access_set_error ip-forward-disabled "Android net.ipv4.ip_forward is not enabled; TierNest will not change this global sysctl"
        return 1
    }

    lookup_table=$(policy_lookup_table)
    desired_targets="$RUNDIR/hotspot-access-targets.$$.tmp"
    if ! build_hotspot_access_targets "$hotspot_network" "$tun_dev" "$lookup_table" "$desired_targets"; then
        cleanup_hotspot_access_unlocked
        rm "$desired_targets" 2>/dev/null || true
        hotspot_access_set_error waiting-routes "No active EasyTier CIDRs are routed through $tun_dev in table $lookup_table"
        return 0
    fi

    target_count=$(grep -c . "$desired_targets" 2>/dev/null || true)
    case "$target_count" in *[!0-9]*|'') target_count=0;; esac
    if [ "$target_count" -gt "$HOTSPOT_ACCESS_MAX_TARGETS" ]; then
        cleanup_hotspot_access_unlocked
        rm "$desired_targets" 2>/dev/null || true
        hotspot_access_set_error too-many-targets "target_count=$target_count limit=$HOTSPOT_ACCESS_MAX_TARGETS"
        return 1
    fi

    current="$hotspot_iface|$hotspot_network|$hotspot_gateway|$tun_dev|$lookup_table"
    previous=""
    [ -r "$HOTSPOT_ACCESS_STATE_FILE" ] && previous=$(cat "$HOTSPOT_ACCESS_STATE_FILE" 2>/dev/null)
    if [ "$current" = "$previous" ] \
        && hotspot_access_rules_ready "$hotspot_iface" "$hotspot_network" "$tun_dev" "$desired_targets"; then
        rm "$desired_targets" 2>/dev/null || true
        hotspot_access_clear_error
        return 0
    fi

    if ! apply_hotspot_access_rules_unlocked "$hotspot_iface" "$hotspot_network" "$tun_dev" "$lookup_table" "$desired_targets"; then
        cleanup_hotspot_access_unlocked
        rm "$desired_targets" 2>/dev/null || true
        hotspot_access_set_error apply-failed "Failed to install isolated outbound-only rules; partial state was rolled back"
        return 1
    fi

    cp "$desired_targets" "$HOTSPOT_ACCESS_TARGETS_FILE"
    rm "$desired_targets" 2>/dev/null || true
    printf '%s\n' "$current" > "$HOTSPOT_ACCESS_STATE_FILE"
    date +%s > "$HOTSPOT_ACCESS_LAST_APPLY_FILE"
    increment_counter "$HOTSPOT_ACCESS_REAPPLY_COUNT_FILE" >/dev/null
    hotspot_access_clear_error
    hotspot_log "active iface=$hotspot_iface cidr=$hotspot_network tun=$tun_dev table=$lookup_table targets=$target_count inbound=new-drop"
    return 0
)

sync_hotspot_access() {
    hotspot_access_lock_acquire || return 0
    sync_hotspot_access_unlocked
    result=$?
    hotspot_access_lock_release
    return "$result"
}

hotspot_client_count() (
    hotspot_iface=$1
    [ -n "$hotspot_iface" ] || { echo 0; return; }
    ip neigh show dev "$hotspot_iface" 2>/dev/null \
        | awk '$NF != "FAILED" && $NF != "INCOMPLETE" {seen[$1]=1} END {for (ip in seen) count++; print count+0}'
)

print_hotspot_access_status() (
    enabled=$(hotspot_access_effective_enabled)
    active=0
    hotspot_iface=""
    hotspot_network=""
    hotspot_gateway=""
    tun_dev=$(find_tun_device 2>/dev/null || true)
    lookup_table=$(policy_lookup_table)

    if [ -r "$HOTSPOT_ACCESS_STATE_FILE" ]; then
        IFS='|' read -r hotspot_iface hotspot_network hotspot_gateway state_tun state_table < "$HOTSPOT_ACCESS_STATE_FILE"
        [ -n "$state_tun" ] && tun_dev=$state_tun
        [ -n "$state_table" ] && lookup_table=$state_table
        if [ "$enabled" = 1 ] && hotspot_access_ip_forward_ready \
            && hotspot_access_rules_ready "$hotspot_iface" "$hotspot_network" "$tun_dev" "$HOTSPOT_ACCESS_TARGETS_FILE"; then
            active=1
        fi
    else
        hotspot_context=$(find_hotspot_access_context 2>/dev/null || true)
        if [ -n "$hotspot_context" ]; then
            old_ifs=$IFS
            IFS='|'
            set -- $hotspot_context
            IFS=$old_ifs
            hotspot_iface=$1
            hotspot_network=$2
            hotspot_gateway=$3
        fi
    fi

    status=disabled
    error_code=""
    error_detail=""
    if [ -r "$HOTSPOT_ACCESS_ERROR_FILE" ]; then
        IFS='|' read -r error_code error_detail < "$HOTSPOT_ACCESS_ERROR_FILE"
    fi
    if [ "$enabled" = 1 ]; then
        if [ "$active" = 1 ]; then status=active
        elif [ -n "$error_code" ]; then status=$error_code
        else status=waiting
        fi
    fi

    target_count=$(grep -c . "$HOTSPOT_ACCESS_TARGETS_FILE" 2>/dev/null || true)
    case "$target_count" in *[!0-9]*|'') target_count=0;; esac
    rule_count=$(grep -c . "$HOTSPOT_ACCESS_RULES_FILE" 2>/dev/null || true)
    case "$rule_count" in *[!0-9]*|'') rule_count=0;; esac
    last_apply=0
    [ -r "$HOTSPOT_ACCESS_LAST_APPLY_FILE" ] && last_apply=$(cat "$HOTSPOT_ACCESS_LAST_APPLY_FILE" 2>/dev/null)
    case "$last_apply" in *[!0-9]*|'') last_apply=0;; esac

    echo "enabled=$enabled"
    echo "active=$active"
    echo "status=$status"
    echo "mode=outbound-only-nat"
    echo "interface=$hotspot_iface"
    echo "cidr=$hotspot_network"
    echo "gateway=$hotspot_gateway"
    echo "tun=$tun_dev"
    echo "route_table=$lookup_table"
    echo "target_count=$target_count"
    echo "rule_count=$rule_count"
    echo "client_count=$(hotspot_client_count "$hotspot_iface")"
    echo "reapply_count=$(read_counter "$HOTSPOT_ACCESS_REAPPLY_COUNT_FILE")"
    echo "last_apply_epoch=$last_apply"
    echo "ip_forward=$(cat "$SYSCTL_ROOT/net/ipv4/ip_forward" 2>/dev/null || echo unknown)"
    echo "inbound_policy=established-related-only;drop-new"
    echo "advertises_hotspot_subnet=0"
    echo "error_code=$error_code"
    echo "error_detail=$error_detail"
)

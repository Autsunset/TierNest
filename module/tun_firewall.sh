#!/system/bin/sh

# Minimal TUN firewall compatibility layer. It only accepts local INPUT/OUTPUT
# traffic whose interface and source/destination match active EasyTier CIDRs.
# It never flushes Android chains and never installs a default ACCEPT/DROP.
TUN_FW_INPUT_CHAIN=TN_ET_INPUT
TUN_FW_OUTPUT_CHAIN=TN_ET_OUTPUT

remove_tun_firewall_hooks_unlocked() (
    resolve_iptables_bin || return 0
    old_tun=""
    [ -r "$TUN_FIREWALL_STATE_FILE" ] && old_tun=$(cat "$TUN_FIREWALL_STATE_FILE" 2>/dev/null)
    [ -n "$old_tun" ] || return 0
    count=0
    while [ "$count" -lt 8 ] && run_iptables -C INPUT -i "$old_tun" -j "$TUN_FW_INPUT_CHAIN"; do
        run_iptables -D INPUT -i "$old_tun" -j "$TUN_FW_INPUT_CHAIN" || break
        count=$((count + 1))
    done
    count=0
    while [ "$count" -lt 8 ] && run_iptables -C OUTPUT -o "$old_tun" -j "$TUN_FW_OUTPUT_CHAIN"; do
        run_iptables -D OUTPUT -o "$old_tun" -j "$TUN_FW_OUTPUT_CHAIN" || break
        count=$((count + 1))
    done
)

cleanup_tun_firewall_guard_unlocked() {
    remove_tun_firewall_hooks_unlocked
    if resolve_iptables_bin; then
        run_iptables -F "$TUN_FW_INPUT_CHAIN" || true
        run_iptables -F "$TUN_FW_OUTPUT_CHAIN" || true
        run_iptables -X "$TUN_FW_INPUT_CHAIN" || true
        run_iptables -X "$TUN_FW_OUTPUT_CHAIN" || true
    fi
    rm "$TUN_FIREWALL_STATE_FILE" "$TUN_FIREWALL_TARGETS_FILE" "$TUN_FIREWALL_ERROR_FILE" 2>/dev/null || true
}

cleanup_tun_firewall_guard() {
    if ! mkdir "$TUN_FIREWALL_LOCK_DIR" 2>/dev/null; then return 0; fi
    cleanup_tun_firewall_guard_unlocked
    rmdir "$TUN_FIREWALL_LOCK_DIR" 2>/dev/null || true
}

build_tun_firewall_targets() (
    tun_dev=$1
    output=$2
    raw="$RUNDIR/tun-firewall-targets.$$.raw"
    build_desired_routes "$tun_dev" "$raw" >/dev/null 2>&1 || true
    {
        cat "$raw" 2>/dev/null || true
        cat "$APPLIED_ROUTES_FILE" 2>/dev/null || true
    } | sort -u | while IFS= read -r cidr; do
        normalized=$(normalize_ipv4_cidr "$cidr" 2>/dev/null) || continue
        route_allowed "$normalized" || continue
        echo "$normalized"
    done | sort -u > "$output"
    rm "$raw" 2>/dev/null || true
    [ -s "$output" ]
)

tun_firewall_rules_ready() (
    tun_dev=$1
    targets=$2
    cmp -s "$targets" "$TUN_FIREWALL_TARGETS_FILE" 2>/dev/null || return 1
    run_iptables -C INPUT -i "$tun_dev" -j "$TUN_FW_INPUT_CHAIN" || return 1
    run_iptables -C OUTPUT -o "$tun_dev" -j "$TUN_FW_OUTPUT_CHAIN" || return 1
    while IFS= read -r cidr; do
        [ -n "$cidr" ] || continue
        run_iptables -C "$TUN_FW_INPUT_CHAIN" -i "$tun_dev" -s "$cidr" -j ACCEPT || return 1
        run_iptables -C "$TUN_FW_OUTPUT_CHAIN" -o "$tun_dev" -d "$cidr" -j ACCEPT || return 1
    done < "$targets"
)

apply_tun_firewall_guard_unlocked() (
    tun_dev=$1
    targets=$2
    resolve_iptables_bin || return 1
    remove_tun_firewall_hooks_unlocked
    run_iptables -N "$TUN_FW_INPUT_CHAIN" || true
    run_iptables -N "$TUN_FW_OUTPUT_CHAIN" || true
    run_iptables -F "$TUN_FW_INPUT_CHAIN" || return 1
    run_iptables -F "$TUN_FW_OUTPUT_CHAIN" || return 1
    while IFS= read -r cidr; do
        [ -n "$cidr" ] || continue
        run_iptables -A "$TUN_FW_INPUT_CHAIN" -i "$tun_dev" -s "$cidr" -j ACCEPT || return 1
        run_iptables -A "$TUN_FW_OUTPUT_CHAIN" -o "$tun_dev" -d "$cidr" -j ACCEPT || return 1
    done < "$targets"
    echo "$tun_dev" > "$TUN_FIREWALL_STATE_FILE"
    run_iptables -I INPUT 1 -i "$tun_dev" -j "$TUN_FW_INPUT_CHAIN" || return 1
    run_iptables -I OUTPUT 1 -o "$tun_dev" -j "$TUN_FW_OUTPUT_CHAIN" || return 1
)

sync_tun_firewall_guard() {
    if ! mkdir "$TUN_FIREWALL_LOCK_DIR" 2>/dev/null; then return 0; fi
    result=0
    if [ "$TUN_FIREWALL_GUARD" != 1 ] || ! core_running; then
        cleanup_tun_firewall_guard_unlocked
    else
        tun_dev=$(find_tun_device 2>/dev/null || true)
        targets="$RUNDIR/tun-firewall-targets.$$.tmp"
        if [ -z "$tun_dev" ]; then
            cleanup_tun_firewall_guard_unlocked
            echo 'tun-unavailable' > "$TUN_FIREWALL_ERROR_FILE"
        elif ! build_tun_firewall_targets "$tun_dev" "$targets"; then
            cleanup_tun_firewall_guard_unlocked
            echo 'targets-unavailable' > "$TUN_FIREWALL_ERROR_FILE"
        elif [ -r "$TUN_FIREWALL_STATE_FILE" ] \
            && [ "$(cat "$TUN_FIREWALL_STATE_FILE" 2>/dev/null)" = "$tun_dev" ] \
            && tun_firewall_rules_ready "$tun_dev" "$targets"; then
            rm "$TUN_FIREWALL_ERROR_FILE" 2>/dev/null || true
        elif apply_tun_firewall_guard_unlocked "$tun_dev" "$targets"; then
            cp "$targets" "$TUN_FIREWALL_TARGETS_FILE"
            rm "$TUN_FIREWALL_ERROR_FILE" 2>/dev/null || true
            log_msg "TUN firewall guard active tun=$tun_dev targets=$(grep -c . "$targets" 2>/dev/null || echo 0)"
        else
            cleanup_tun_firewall_guard_unlocked
            echo 'apply-failed' > "$TUN_FIREWALL_ERROR_FILE"
            log_msg "ERROR: failed to apply TUN firewall guard"
            result=1
        fi
        rm "$targets" 2>/dev/null || true
    fi
    rmdir "$TUN_FIREWALL_LOCK_DIR" 2>/dev/null || true
    return "$result"
}

print_tun_firewall_status() {
    enabled=$TUN_FIREWALL_GUARD
    tun_dev=""
    [ -r "$TUN_FIREWALL_STATE_FILE" ] && tun_dev=$(cat "$TUN_FIREWALL_STATE_FILE" 2>/dev/null)
    target_count=$(grep -c . "$TUN_FIREWALL_TARGETS_FILE" 2>/dev/null || true)
    case "$target_count" in *[!0-9]*|'') target_count=0;; esac
    active=0
    [ "$enabled" = 1 ] && [ -n "$tun_dev" ] \
        && tun_firewall_rules_ready "$tun_dev" "$TUN_FIREWALL_TARGETS_FILE" && active=1
    echo "enabled=$enabled"
    echo "active=$active"
    echo "tun=$tun_dev"
    echo "target_count=$target_count"
    echo "error=$(cat "$TUN_FIREWALL_ERROR_FILE" 2>/dev/null || true)"
}

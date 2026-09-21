# TierNest App root engine. Sourced by engine.sh; no eval and no module daemon.
# The app owns a root session, a core PID identity, and an exact routing journal.

fail() { printf '%s\n' "$*" >&2; return 1; }

# The upstream RPC is unauthenticated. Only root-owned local clients may reach
# it; all app RPC calls run inside this su session. Fail closed if unavailable.
protect_rpc() {
    command -v iptables >/dev/null 2>&1 || { fail 'iptables is required to isolate the local RPC'; return 1; }
    if iptables -w 2 -S TNAPP_RPC >/dev/null 2>&1; then
        fail 'RPC firewall chain is already owned'; return 1
    fi
    iptables -w 2 -N TNAPP_RPC || return 1
    : > "$TN_RUN/rpc-owned"
    iptables -w 2 -A TNAPP_RPC -m owner --uid-owner 0 -j RETURN &&
        iptables -w 2 -A TNAPP_RPC -j REJECT &&
        iptables -w 2 -I OUTPUT 1 -o lo -p tcp -d 127.0.0.1/32 --dport 15888 -j TNAPP_RPC || return 1
}

cleanup_rpc() {
    [ -f "$TN_RUN/rpc-owned" ] || return 0
    if iptables -w 2 -C OUTPUT -o lo -p tcp -d 127.0.0.1/32 --dport 15888 -j TNAPP_RPC 2>/dev/null; then
        iptables -w 2 -D OUTPUT -o lo -p tcp -d 127.0.0.1/32 --dport 15888 -j TNAPP_RPC || return 1
    fi
    if iptables -w 2 -S TNAPP_RPC >/dev/null 2>&1; then
        iptables -w 2 -F TNAPP_RPC && iptables -w 2 -X TNAPP_RPC || return 1
    fi
    rm -f "$TN_RUN/rpc-owned"
}

pid_identity() {
    [ -r "/proc/$1/stat" ] || return 1
    # Strip comm (which can contain spaces) before reading starttime.
    sed 's/.*) //' "/proc/$1/stat" | awk '{print $20}'
}

core_alive() {
    [ -f "$TN_RUN/core.pid" ] || return 1
    read -r tn_pid tn_start < "$TN_RUN/core.pid"
    case "$tn_pid:$tn_start" in *[!0-9:]*|:*) return 1;; esac
    [ "$(pid_identity "$tn_pid")" = "$tn_start" ] || return 1
    [ "$(readlink "/proc/$tn_pid/exe" 2>/dev/null)" = "$TN_ROOT/bin/easytier-core" ]
}

stop_core() {
    if core_alive; then
        kill "$tn_pid" 2>/dev/null || true
        tn_wait=0
        while core_alive && [ "$tn_wait" -lt 30 ]; do
            sleep 0.1
            tn_wait=$((tn_wait + 1))
        done
        if core_alive; then kill -9 "$tn_pid" 2>/dev/null || return 1; fi
        wait "$tn_pid" 2>/dev/null || true
    fi
    rm -f "$TN_RUN/core.pid"
}

valid_cidr() {
    awk -v c="$1" 'BEGIN {
        if (split(c, a, "/") != 2 || a[2] !~ /^[0-9]+$/ || a[2] < 8 || a[2] > 32) exit 1
        if (split(a[1], o, ".") != 4) exit 1
        for (i=1;i<=4;i++) if (o[i] !~ /^[0-9]+$/ || o[i] > 255) exit 1
        if (o[1] == 0 || o[1] == 127 || o[1] >= 224 || (o[1] == 169 && o[2] == 254)) exit 1
    }'
}

read_lease() {
    [ -r "$TN_RUN/lease" ] || return 1
    read -r tn_table tn_pref < "$TN_RUN/lease"
    case "$tn_table:$tn_pref" in *[!0-9:]*|:*) return 1;; esac
    [ "$tn_table" -ge 20110 ] && [ "$tn_table" -le 20129 ] &&
        [ "$tn_pref" -ge 9901 ] && [ "$tn_pref" -le 9980 ]
}

cleanup_routes() {
    read_lease || return 0
    tn_failed=0
    # Delete by full identity, never by priority alone or by flushing a table.
    if ip -4 rule show | grep -Eq "^[[:space:]]*$tn_pref:.*lookup $tn_table([[:space:]]|$)"; then
        ip -4 rule del pref "$tn_pref" lookup "$tn_table" || tn_failed=1
    fi
    if [ -f "$TN_RUN/routes" ]; then
        while IFS= read -r tn_cidr; do
            valid_cidr "$tn_cidr" || continue
            # A recorded but unsuccessful add is harmless. Never delete a replacement
            # owned by another client (different interface/protocol).
            if ip -4 route show table "$tn_table" exact "$tn_cidr" proto 186 | grep -Eq 'dev tiernest0([[:space:]]|$)'; then
                ip -4 route del table "$tn_table" "$tn_cidr" dev tiernest0 proto 186 || tn_failed=1
            fi
        done < "$TN_RUN/routes"
    fi
    if [ "$tn_failed" = 0 ]; then rm -f "$TN_RUN/routes" "$TN_RUN/lease"; fi
    [ "$tn_failed" = 0 ]
}

allocate_routes() {
    read_lease && return 0
    tn_table=20110
    while [ "$tn_table" -le 20129 ]; do
        if [ -z "$(ip -4 route show table "$tn_table" 2>/dev/null)" ] &&
            ! ip -4 rule show | grep -Eq "lookup $tn_table([[:space:]]|$)"; then break; fi
        tn_table=$((tn_table + 1))
    done
    [ "$tn_table" -le 20129 ] || { fail 'No unused TierNest routing table'; return 1; }
    tn_pref=9980
    while ip -4 rule show | grep -Eq "^[[:space:]]*$tn_pref:"; do
        tn_pref=$((tn_pref - 1))
        [ "$tn_pref" -ge 9901 ] || { fail 'No unused TierNest rule priority'; return 1; }
    done
    printf '%s %s\n' "$tn_table" "$tn_pref" > "$TN_RUN/lease"
}

sync_routes() {
    core_alive || { fail 'Core is not running'; return 1; }
    ip link show dev tiernest0 >/dev/null 2>&1 || { fail 'Waiting for tiernest0'; return 1; }
    [ -s "$TN_STAGE/routes.txt" ] || { fail 'No overlay routes available'; return 1; }
    while IFS= read -r tn_cidr; do
        valid_cidr "$tn_cidr" || { fail 'Rejected unsafe overlay route'; return 1; }
    done < "$TN_STAGE/routes.txt"
    allocate_routes || return 1
    # A foreign default route appearing in our table would capture normal VPN
    # traffic through the lookup rule. Withdraw our rule instead of using it.
    ip -4 route show table "$tn_table" 2>/dev/null | awk '{print $1}' > "$TN_RUN/actual"
    while IFS= read -r tn_cidr; do
        case "$tn_cidr" in */*) ;; *) tn_cidr="$tn_cidr/32";; esac
        if ! grep -Fxq "$tn_cidr" "$TN_RUN/routes" 2>/dev/null; then
            cleanup_routes; fail 'Foreign route appeared in the TierNest table'; return 1
        fi
    done < "$TN_RUN/actual"
    sort -u "$TN_STAGE/routes.txt" > "$TN_RUN/desired"
    # Publish all attempted additions before mutations, for crash recovery.
    cat "$TN_RUN/routes" "$TN_RUN/desired" 2>/dev/null | sort -u > "$TN_RUN/journal.new"
    mv "$TN_RUN/journal.new" "$TN_RUN/routes"
    tn_ip=$(ip -o -4 addr show dev tiernest0 | awk 'NR==1{split($4,a,"/"); print a[1]}')
    [ -n "$tn_ip" ] || return 1
    tn_failed=0
    while IFS= read -r tn_cidr; do
        if grep -Fxq "$tn_cidr" "$TN_RUN/desired"; then
            tn_existing=$(ip -4 route show table "$tn_table" exact "$tn_cidr" 2>/dev/null)
            if [ -n "$tn_existing" ] && ! ip -4 route show table "$tn_table" exact "$tn_cidr" proto 186 | grep -Eq 'dev tiernest0([[:space:]]|$)'; then
                fail 'Routing table changed by another owner'; tn_failed=1; break
            fi
            ip -4 route replace table "$tn_table" "$tn_cidr" dev tiernest0 proto 186 src "$tn_ip" || tn_failed=1
        else
            tn_existing=$(ip -4 route show table "$tn_table" exact "$tn_cidr" proto 186 2>/dev/null)
            if printf '%s\n' "$tn_existing" | grep -Eq 'dev tiernest0([[:space:]]|$)'; then
                ip -4 route del table "$tn_table" "$tn_cidr" dev tiernest0 proto 186 || tn_failed=1
            fi
        fi
    done < "$TN_RUN/routes"
    if [ "$tn_failed" != 0 ]; then cleanup_routes; return 1; fi
    cp "$TN_RUN/desired" "$TN_RUN/routes"
    if ! ip -4 rule show | grep -Eq "^[[:space:]]*$tn_pref:.*lookup $tn_table([[:space:]]|$)"; then
        if ip -4 rule show | grep -Eq "^[[:space:]]*$tn_pref:"; then
            cleanup_routes; fail 'Rule priority changed by another owner'; return 1
        fi
        ip -4 rule add pref "$tn_pref" lookup "$tn_table" || { cleanup_routes; return 1; }
    fi
}

check_modules() {
    for tn_module in /data/adb/modules/tiernest /data/adb/modules/easytier_magisk; do
        if [ -d "$tn_module" ] && [ ! -f "$tn_module/disable" ] && [ ! -f "$tn_module/remove" ]; then
            fail 'Stop and disable the existing EasyTier/TierNest module before connecting'; return 1
        fi
    done
    # Disabled modules may leave rules matching a future tiernest0. Refuse the
    # conflict; their WebUI owns their cleanup, not this app's journal.
    for tn_chain in TN_HS_FWD TN_HS_OUT_FWD; do
        if iptables -w 2 -t filter -S "$tn_chain" >/dev/null 2>&1; then
            fail 'Stop the old module in its WebUI to remove its hotspot rules'; return 1
        fi
    done
    for tn_chain in TN_HS_NAT TN_HS_OUT_NAT; do
        if iptables -w 2 -t nat -S "$tn_chain" >/dev/null 2>&1; then
            fail 'Stop the old module in its WebUI to remove its hotspot rules'; return 1
        fi
    done
    # Disabling a module does not stop its current process. The interface check
    # below catches this too; never take ownership of an existing TUN.
}

start_core() {
    core_alive && return 0
    check_modules || return 1
    ip link show dev tiernest0 >/dev/null 2>&1 && { fail 'tiernest0 already exists; stop the other instance'; return 1; }
    [ -c /dev/net/tun ] || [ -c /dev/tun ] || { fail 'TUN device unavailable'; return 1; }
    timeout 10 "$TN_ROOT/bin/easytier-core" --check-config -c "$TN_STAGE/effective.toml" >/dev/null 2>&1 || {
        fail 'EasyTier rejected the configuration'; return 1;
    }
    cp "$TN_STAGE/effective.toml" "$TN_ROOT/effective.toml.new" &&
        mv "$TN_ROOT/effective.toml.new" "$TN_ROOT/effective.toml" || return 1
    protect_rpc || return 1
    # Suppress startup TOML dumps. Let the core rotate its own bounded error logs
    # even while Android freezes the UI; never kill the network for a full log.
    mkdir -p "$TN_ROOT/logs" || return 1
    "$TN_ROOT/bin/easytier-core" -c "$TN_ROOT/effective.toml" \
        --rpc-portal 127.0.0.1:15888 --rpc-portal-whitelist 127.0.0.1/32 \
        --console-log-level off --file-log-level error --file-log-dir "$TN_ROOT/logs" --file-log-size 1 --file-log-count 2 \
        >/dev/null 2>&1 </dev/null &
    tn_pid=$!
    tn_start=$(pid_identity "$tn_pid")
    printf '%s %s\n' "$tn_pid" "$tn_start" > "$TN_RUN/core.pid"
    tn_wait=0
    until core_alive; do
        tn_wait=$((tn_wait + 1))
        [ "$tn_wait" -lt 30 ] || { fail 'Core did not start'; return 1; }
        sleep 0.1
    done
}

engine_status() {
    if core_alive; then printf 'alive=1\npid=%s\n' "$tn_pid"; else printf 'alive=0\n'; fi
    if core_alive && ip link show dev tiernest0 >/dev/null 2>&1; then
        printf 'cidr=%s\n' "$(ip -o -4 addr show dev tiernest0 | awk 'NR==1{print $4}')"
        printf 'rx=%s\n' "$(cat /sys/class/net/tiernest0/statistics/rx_bytes 2>/dev/null)"
        printf 'tx=%s\n' "$(cat /sys/class/net/tiernest0/statistics/tx_bytes 2>/dev/null)"
    fi
    if read_lease; then printf 'table=%s\npref=%s\n' "$tn_table" "$tn_pref"; fi
    [ ! -f "$TN_RUN/hotspot.status" ] || cat "$TN_RUN/hotspot.status"
}

backup_file() {
    [ -s "$TN_STAGE/backup.toml" ] || { fail 'No configuration to back up'; return 1; }
    mkdir -p "$TN_BACKUPS" || return 1
    # Android toybox mktemp requires Xs at the end, unlike GNU mktemp. Reserve
    # a final .toml filename atomically with noclobber on both implementations.
    tn_stamp=$(date +%Y%m%d-%H%M%S)
    tn_index=0
    while :; do
        tn_backup="$TN_BACKUPS/app-$tn_stamp-$$-$tn_index.toml"
        (set -C; : > "$tn_backup") 2>/dev/null && break
        tn_index=$((tn_index + 1))
        [ "$tn_index" -lt 1000 ] || { fail 'Cannot reserve a unique backup file'; return 1; }
    done
    cp "$TN_STAGE/backup.toml" "$tn_backup" && cmp -s "$TN_STAGE/backup.toml" "$tn_backup" || {
        fail 'Backup verification failed; configuration not changed'; return 1;
    }
    printf '%s\n' "$tn_backup"
}

tree_equal() (
    [ ! -L "$1" ] && [ ! -L "$2" ] || exit 1
    if [ -d "$1" ]; then
        [ -d "$2" ] || exit 1
        for tn_entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
            [ -e "$tn_entry" ] || [ -L "$tn_entry" ] || continue
            tree_equal "$tn_entry" "$2/${tn_entry##*/}" || exit 1
        done
        for tn_entry in "$2"/* "$2"/.[!.]* "$2"/..?*; do
            [ -e "$tn_entry" ] || [ -L "$tn_entry" ] || continue
            [ -e "$1/${tn_entry##*/}" ] || exit 1
        done
    else [ -f "$1" ] && cmp -s "$1" "$2"; fi
)

snapshot_module() {
    tn_source=/data/adb/modules/tiernest
    [ -f "$tn_source/config/config.toml" ] || tn_source=/data/adb/modules/easytier_magisk
    [ -f "$tn_source/config/config.toml" ] || { fail 'No installed module configuration'; return 1; }
    mkdir -p "$TN_BACKUPS" || return 1
    tn_snapshot=$(mktemp -d "$TN_BACKUPS/app-import-$(date +%Y%m%d-%H%M%S)-XXXXXX") || return 1
    cp -R "$tn_source/config" "$tn_snapshot/config" &&
        tree_equal "$tn_source/config" "$tn_snapshot/config" || { fail 'Module snapshot verification failed'; return 1; }
    if [ -f "$tn_source/settings.conf" ]; then
        cp "$tn_source/settings.conf" "$tn_snapshot/settings.conf" &&
            cmp -s "$tn_source/settings.conf" "$tn_snapshot/settings.conf" || return 1
    fi
    # The original module and its backups remain intact. Copy the verified
    # snapshot into the app inbox; root permissions must not leak secrets.
    mkdir -p "$TN_STAGE/import" || return 1
    cp -R "$tn_snapshot/." "$TN_STAGE/import/" || return 1
    tn_uid=$(stat -c %u "$TN_STAGE")
    chown -R "$tn_uid:$tn_uid" "$TN_STAGE/import" || return 1
    printf '%s\n' "$tn_snapshot"
}

dispatch() {
    case "$1" in
        start) start_core;;
        stop) cleanup_hotspot && stop_core && cleanup_routes && cleanup_rpc;;
        status) engine_status;;
        sync) sync_routes;;
        hotspot) sync_hotspot;;
        peers) timeout 8 "$TN_ROOT/bin/easytier-cli" -p 127.0.0.1:15888 -o json route list 2>/dev/null;;
        backup) backup_file;;
        import) snapshot_module;;
        validate) timeout 10 "$TN_ROOT/bin/easytier-core" --check-config -c "$TN_STAGE/effective.toml" >/dev/null 2>&1;;
        probe)
            read -r tn_wifi tn_source tn_target tn_port tn_extra < "$TN_STAGE/probe-query" || return 1
            [ -z "$tn_extra" ] || return 1
            timeout 4 "$TN_ROOT/bin/home-probe" "$tn_wifi" "$tn_source" "$tn_target" "$tn_port";;
        gateway)
            read -r tn_iface tn_gateway < "$TN_STAGE/wifi-query" || return 1
            case "$tn_iface" in wlan[0-9]*) ;; *) return 1;; esac
            case "$tn_iface" in *[!a-zA-Z0-9]*) return 1;; esac
            valid_cidr "$tn_gateway/32" || return 1
            tn_mac=$(ip neigh show to "$tn_gateway" dev "$tn_iface" | awk '!/FAILED|INCOMPLETE/{for(i=1;i<NF;i++)if($i=="lladdr"){print tolower($(i+1));exit}}')
            if [ -z "$tn_mac" ]; then
                ping -I "$tn_iface" -c 1 -W 1 "$tn_gateway" >/dev/null 2>&1 || true
                tn_mac=$(ip neigh show to "$tn_gateway" dev "$tn_iface" | awk '!/FAILED|INCOMPLETE/{for(i=1;i<NF;i++)if($i=="lladdr"){print tolower($(i+1));exit}}')
            fi
            printf '%s\n' "$tn_mac";;
        *) fail 'Unknown engine operation';;
    esac
}

# Optional IPv4 hotspot access. All callers share the Root session lock.
# Only Android-reported Wi-Fi tether interfaces are eligible. No global sysctl,
# netd chain, proxy advertisement, or ordinary internet route is changed.

hs_iface_valid() {
    case "$1" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac
    [ "${#1}" -le 15 ] || return 1
    case "$1" in wlan[0-9]*|ap[0-9]*|ap_*|apbr*|swlan[0-9]*|softap[0-9]*|br_tether*) return 0;; esac
    return 1
}

hs_network() {
    valid_cidr "$1" || return 1
    awk -v cidr="$1" 'BEGIN {
        split(cidr,c,"/"); split(c[1],a,"."); n=((a[1]*256+a[2])*256+a[3])*256+a[4];
        block=2^(32-c[2]); n=int(n/block)*block;
        printf "%d.%d.%d.%d/%d\n", int(n/16777216), int(n/65536)%256, int(n/256)%256, n%256,c[2]
    }'
}

hs_overlap() {
    awk -v x="$1" -v y="$2" 'function addr(s,a) {split(s,a,"."); return ((a[1]*256+a[2])*256+a[3])*256+a[4]}
        BEGIN {split(x,a,"/"); split(y,b,"/"); p=a[2]<b[2]?a[2]:b[2]; k=2^(32-p); exit int(addr(a[1])/k)!=int(addr(b[1])/k)}'
}

hs_private() {
    awk -v s="$1" 'BEGIN {split(s,a,"."); exit !(a[1]==10 || (a[1]==172 && a[2]>=16 && a[2]<=31) || (a[1]==192 && a[2]==168))}'
}

hs_forward_ready() { [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ]; }

hs_iptables() { iptables -w 2 -t "$@"; }

# A private journal contains only validated arguments generated below, never
# TOML or shell code. Record intent before mutation so partial apply is removable.
hs_add() {
    printf '%s\n' "$*" >> "$TN_RUN/hotspot.rules" || return 1
    hs_table=$1; hs_chain=$2; shift 2
    case "$hs_chain" in FORWARD|POSTROUTING) hs_iptables "$hs_table" -I "$hs_chain" 1 "$@";;
        *) hs_iptables "$hs_table" -A "$hs_chain" "$@";; esac
}

hs_return_rule_present() {
    ip -4 rule show | awk -v p="$1:" -v c="$2" -v t="$3" '
        NF==9 && $1==p && $2=="from" && $3=="all" && $4=="to" && $5==c &&
        $6=="iif" && $7=="tiernest0" && $8=="lookup" && $9==t {found=1} END {exit !found}'
}

cleanup_hotspot() (
    hs_failed=0
    if [ -f "$TN_RUN/hotspot.rules" ] || [ -f "$TN_RUN/hotspot.return" ] || [ -f "$TN_RUN/hotspot.chains" ]; then
        printf 'hotspot_state=error\n' > "$TN_RUN/hotspot.status" || return 1
    fi
    # Remove parent hooks before chain contents. Never flush a chain: additions
    # from another owner survive and cause an explicit cleanup error.
    if [ -f "$TN_RUN/hotspot.rules" ]; then
        awk '{a[NR]=$0} END {for(i=NR;i>0;i--) print a[i]}' "$TN_RUN/hotspot.rules" > "$TN_RUN/hotspot.undo" || return 1
        while IFS= read -r hs_line; do
            set -f; set -- $hs_line
            hs_table=$1; hs_chain=$2; shift 2
            case "$hs_table:$hs_chain" in filter:FORWARD|filter:TNAPP_HSF|nat:POSTROUTING|nat:TNAPP_HSN) ;; *) hs_failed=1; continue;; esac
            if hs_iptables "$hs_table" -C "$hs_chain" "$@" 2>/dev/null; then
                hs_iptables "$hs_table" -D "$hs_chain" "$@" || hs_failed=1
            fi
        done < "$TN_RUN/hotspot.undo"
    fi
    if [ -f "$TN_RUN/hotspot.return" ]; then
        read -r hs_iface hs_cidr hs_gateway hs_table hs_pref < "$TN_RUN/hotspot.return" || return 1
        hs_iface_valid "$hs_iface" && valid_cidr "$hs_cidr" || return 1
        case "$hs_table:$hs_pref" in *[!0-9:]*|:*) return 1;; esac
        [ "$hs_table" -ge 20130 ] && [ "$hs_table" -le 20149 ] &&
            [ "$hs_pref" -ge 9871 ] && [ "$hs_pref" -le 9890 ] || return 1
        if hs_return_rule_present "$hs_pref" "$hs_cidr" "$hs_table"; then
            ip -4 rule del pref "$hs_pref" iif tiernest0 to "$hs_cidr" lookup "$hs_table" || hs_failed=1
        fi
        if ip -4 route show table "$hs_table" exact "$hs_cidr" proto 186 | grep -Eq "dev $hs_iface([[:space:]]|$)"; then
            ip -4 route del table "$hs_table" "$hs_cidr" dev "$hs_iface" proto 186 || hs_failed=1
        fi
    fi
    if [ -f "$TN_RUN/hotspot.chains" ]; then
        while read -r hs_table hs_chain; do
            case "$hs_table:$hs_chain" in filter:TNAPP_HSF|nat:TNAPP_HSN) ;; *) hs_failed=1; continue;; esac
            if hs_iptables "$hs_table" -S "$hs_chain" >/dev/null 2>&1; then
                hs_iptables "$hs_table" -X "$hs_chain" || hs_failed=1
            fi
        done < "$TN_RUN/hotspot.chains"
    fi
    if [ "$hs_failed" = 0 ]; then
        rm -f "$TN_RUN/hotspot.rules" "$TN_RUN/hotspot.undo" "$TN_RUN/hotspot.return" \
            "$TN_RUN/hotspot.chains" "$TN_RUN/hotspot.applied" "$TN_RUN/hotspot.status" "$TN_RUN/hotspot.chain-state"
    fi
    [ "$hs_failed" = 0 ]
)

# Only parse the live state section, never the historical log below it. A name
# like wlan0 alone is not proof that a Wi-Fi client interface is a hotspot.
hs_detect() (
    hs_dump="$TN_RUN/hotspot.dump"
    if ! timeout 3 dumpsys tethering --short > "$hs_dump" 2>/dev/null || ! grep -q 'Tether state:' "$hs_dump"; then
        timeout 3 dumpsys connectivity > "$hs_dump" 2>/dev/null || { rm -f "$hs_dump"; return 1; }
    fi
    if ! grep -q 'Tether state:' "$hs_dump"; then rm -f "$hs_dump"; return 1; fi
    awk '/Tether state:/ {live=1; next} live && /Upstream wanted:|Current upstream|Hardware offload:|Log:/ {exit}
        live && NF==7 && $2=="-" && $3=="TetheredState" && $4=="-" && $5=="lastError" && $6=="=" && $7=="0" {print $1}' \
        "$hs_dump" > "$TN_RUN/hotspot.ifaces"
    rm -f "$hs_dump"
    while IFS= read -r hs_iface; do
        hs_iface_valid "$hs_iface" || continue
        ip link show dev "$hs_iface" | head -n 1 | grep -q '<[^>]*UP[,>]' || continue
        ip -4 route show table all default | grep -Eq "dev $hs_iface([[:space:]]|$)" && continue
        hs_addr=$(ip -o -4 addr show dev "$hs_iface" | awk '$3=="inet" {print $4; exit}')
        hs_cidr=$(hs_network "$hs_addr") || continue
        hs_gateway=${hs_addr%/*}
        hs_private "$hs_gateway" || continue
        printf '%s %s %s\n' "$hs_iface" "$hs_cidr" "$hs_gateway"
    done < "$TN_RUN/hotspot.ifaces"
    rm -f "$TN_RUN/hotspot.ifaces"
)

hs_status() {
    printf 'hotspot_state=%s\n' "$1" > "$TN_RUN/hotspot.status"
    if [ "$1" = active ]; then printf 'hotspot_cidr=%s\n' "$2" >> "$TN_RUN/hotspot.status"; fi
    cat "$TN_RUN/hotspot.status"
}

hs_inactive() { cleanup_hotspot && hs_status "$1"; }

hs_chain_snapshot() {
    hs_iptables filter -S TNAPP_HSF && hs_iptables nat -S TNAPP_HSN
}

hs_ready() (
    [ -s "$TN_RUN/hotspot.return" ] && [ -s "$TN_RUN/hotspot.rules" ] || return 1
    read -r hs_iface hs_cidr hs_gateway hs_table hs_pref < "$TN_RUN/hotspot.return"
    hs_return_rule_present "$hs_pref" "$hs_cidr" "$hs_table" || return 1
    ip -4 route show table "$hs_table" exact "$hs_cidr" proto 186 | grep -Eq "dev $hs_iface([[:space:]]|$)" || return 1
    # Constant number of subprocesses during maintenance, independent of peer
    # count. -S excludes packet counters; compare the exact installed chains.
    hs_chain_snapshot > "$TN_RUN/hotspot.chain-current" || return 1
    cmp -s "$TN_RUN/hotspot.chain-state" "$TN_RUN/hotspot.chain-current" || return 1
    hs_iptables nat -C POSTROUTING -s "$hs_cidr" -o tiernest0 -j TNAPP_HSN &&
        hs_iptables filter -C FORWARD -i "$hs_iface" -o tiernest0 -j TNAPP_HSF &&
        hs_iptables filter -C FORWARD -i tiernest0 -o "$hs_iface" -j TNAPP_HSF
)

hs_apply() (
    read -r hs_iface hs_cidr hs_gateway < "$TN_RUN/hotspot.context"
    for hs_spec in 'filter TNAPP_HSF' 'nat TNAPP_HSN'; do
        set -- $hs_spec
        if hs_iptables "$1" -S "$2" >/dev/null 2>&1; then return 1; fi
    done
    for hs_spec in 'filter TNAPP_HSF' 'nat TNAPP_HSN'; do
        set -- $hs_spec
        hs_iptables "$1" -N "$2" || return 1
        printf '%s\n' "$hs_spec" >> "$TN_RUN/hotspot.chains" || return 1
    done
    hs_table=20130
    while [ "$hs_table" -le 20149 ]; do
        [ -z "$(ip -4 route show table "$hs_table")" ] &&
            ! ip -4 rule show | grep -Eq "lookup $hs_table([[:space:]]|$)" && break
        hs_table=$((hs_table+1))
    done
    [ "$hs_table" -le 20149 ] || return 1
    hs_pref=9890
    while ip -4 rule show | grep -Eq "^[[:space:]]*$hs_pref:"; do hs_pref=$((hs_pref-1)); done
    [ "$hs_pref" -ge 9871 ] || return 1
    printf '%s %s %s %s %s\n' "$hs_iface" "$hs_cidr" "$hs_gateway" "$hs_table" "$hs_pref" > "$TN_RUN/hotspot.return" || return 1
    ip -4 route add table "$hs_table" "$hs_cidr" dev "$hs_iface" proto 186 src "$hs_gateway" || return 1
    ip -4 rule add pref "$hs_pref" iif tiernest0 to "$hs_cidr" lookup "$hs_table" || return 1
    while IFS= read -r hs_target; do
        hs_add nat TNAPP_HSN -s "$hs_cidr" -d "$hs_target" -o tiernest0 -j MASQUERADE || return 1
        hs_add filter TNAPP_HSF -i "$hs_iface" -o tiernest0 -s "$hs_cidr" -d "$hs_target" -j ACCEPT || return 1
    done < "$TN_RUN/hotspot.targets"
    hs_add filter TNAPP_HSF -i tiernest0 -o "$hs_iface" -d "$hs_cidr" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || return 1
    hs_add filter TNAPP_HSF -i tiernest0 -o "$hs_iface" -j DROP || return 1
    hs_add filter TNAPP_HSF -i "$hs_iface" -o tiernest0 -j DROP || return 1
    # Hooks published last, after the return route and restricted rules exist.
    hs_add nat POSTROUTING -s "$hs_cidr" -o tiernest0 -j TNAPP_HSN || return 1
    hs_add filter FORWARD -i "$hs_iface" -o tiernest0 -j TNAPP_HSF || return 1
    hs_add filter FORWARD -i tiernest0 -o "$hs_iface" -j TNAPP_HSF || return 1
)

sync_hotspot() (
    read -r hs_enabled hs_extra < "$TN_STAGE/hotspot-query" || return 1
    [ -z "$hs_extra" ] || return 1
    case "$hs_enabled" in off) hs_inactive disabled; return;; on) ;; *) return 1;; esac
    core_alive && read_lease || { hs_inactive waiting_core; return; }
    if ! hs_detect > "$TN_RUN/hotspot.context"; then hs_inactive unavailable; return; fi
    hs_count=$(wc -l < "$TN_RUN/hotspot.context")
    [ "$hs_count" -gt 0 ] || { hs_inactive waiting_hotspot; return; }
    [ "$hs_count" = 1 ] || { hs_inactive ambiguous; return; }
    read -r hs_iface hs_cidr hs_gateway < "$TN_RUN/hotspot.context"
    hs_forward_ready || { hs_inactive forwarding_off; return; }
    # A userspace subnet proxy can bypass FORWARD. Refuse a published hotspot
    # subnet rather than claim one-way access while the core proxies inbound.
    [ -f "$TN_STAGE/hotspot-proxies" ] || { hs_inactive conflict; return; }
    while IFS= read -r hs_proxy; do
        [ -n "$hs_proxy" ] || continue
        valid_cidr "$hs_proxy" || { hs_inactive conflict; return; }
        hs_overlap "$hs_proxy" "$hs_cidr" && { hs_inactive conflict; return; }
    done < "$TN_STAGE/hotspot-proxies"
    : > "$TN_RUN/hotspot.targets"
    while IFS= read -r hs_target; do
        valid_cidr "$hs_target" || { hs_inactive conflict; return; }
        hs_overlap "$hs_target" "$hs_cidr" && { hs_inactive conflict; return; }
        ip -4 route show table "$tn_table" exact "$hs_target" proto 186 | grep -Eq 'dev tiernest0([[:space:]]|$)' || continue
        echo "$hs_target" >> "$TN_RUN/hotspot.targets"
    done < "$TN_RUN/routes"
    hs_count=$(wc -l < "$TN_RUN/hotspot.targets")
    [ "$hs_count" -gt 0 ] || { hs_inactive waiting_routes; return; }
    [ "$hs_count" -le 128 ] || { hs_inactive too_many_routes; return; }
    cat "$TN_RUN/hotspot.context" "$TN_RUN/hotspot.targets" > "$TN_RUN/hotspot.desired"
    if cmp -s "$TN_RUN/hotspot.desired" "$TN_RUN/hotspot.applied" && hs_ready; then hs_status active "$hs_cidr"; return; fi
    cleanup_hotspot || return 1
    if ! hs_apply; then hs_inactive error; return; fi
    if ! hs_chain_snapshot > "$TN_RUN/hotspot.chain-state"; then hs_inactive error; return; fi
    # Verify the hotspot still has the same identity after installing rules.
    if ! hs_detect > "$TN_RUN/hotspot.after" || ! cmp -s "$TN_RUN/hotspot.context" "$TN_RUN/hotspot.after"; then
        hs_inactive waiting_hotspot; return
    fi
    cp "$TN_RUN/hotspot.desired" "$TN_RUN/hotspot.applied" || return 1
    hs_status active "$hs_cidr"
)

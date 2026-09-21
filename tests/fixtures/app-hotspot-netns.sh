#!/system/bin/sh
# Invoked only inside the runner's disposable network namespace.
set -eu
DIR=$1
TN_ROOT=$DIR/root
TN_RUN=$TN_ROOT/run
TN_STAGE=$DIR/stage
mkdir -p "$TN_RUN" "$TN_STAGE"
. "$DIR/engine-lib.sh"
. "$DIR/hotspot-lib.sh"
core_alive() { return 0; }
# Use synthetic Android tethering state; routing and netfilter below are real.
mkdir -p "$DIR/mock-bin"
printf '#!/system/bin/sh\ncat "$TEST_TETHER_STATE"\n' > "$DIR/mock-bin/dumpsys"
chmod 755 "$DIR/mock-bin/dumpsys"
export TEST_TETHER_STATE="$DIR/tether-state"
export PATH="$DIR/mock-bin:$PATH"
PIDS=''
cleanup() { for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
for role in client mesh internet; do
    unshare -n sleep 180 & pid=$!; PIDS="$PIDS $pid"
    case "$role" in client) CLIENT=$pid;; mesh) MESH=$pid;; internet) INTERNET=$pid;; esac
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(readlink /proc/$pid/ns/net)" != "$(readlink /proc/$$/ns/net)" ] && break
        sleep 0.1
    done
    [ "$(readlink /proc/$pid/ns/net)" != "$(readlink /proc/$$/ns/net)" ] || exit 1
done
ip link set lo up
ip link add ap0 type veth peer name client0
ip link add tiernest0 type veth peer name mesh0
ip link add wlan0 type veth peer name internet0
ip link set client0 netns "$CLIENT"
ip link set mesh0 netns "$MESH"
ip link set internet0 netns "$INTERNET"
for iface in ap0 tiernest0 wlan0; do ip link set "$iface" up; done
ip addr add 192.168.77.1/24 dev ap0
ip addr add 10.77.0.2/24 dev tiernest0
ip addr add 198.51.100.2/24 dev wlan0
for pid in $PIDS; do nsenter -t "$pid" -n -- ip link set lo up; done
nsenter -t "$CLIENT" -n -- ip link set client0 up
nsenter -t "$CLIENT" -n -- ip addr add 192.168.77.2/24 dev client0
nsenter -t "$CLIENT" -n -- ip route add default via 192.168.77.1
nsenter -t "$MESH" -n -- ip link set mesh0 up
nsenter -t "$MESH" -n -- ip addr add 10.77.0.9/24 dev mesh0
nsenter -t "$MESH" -n -- ip route add 192.168.77.0/24 via 10.77.0.2
# A successful request proves source NAT too: untranslated client packets drop.
nsenter -t "$MESH" -n -- iptables -I INPUT -s 192.168.77.0/24 -j DROP
nsenter -t "$INTERNET" -n -- ip link set internet0 up
nsenter -t "$INTERNET" -n -- ip addr add 198.51.100.1/24 dev internet0

# Simulate Android policy routing: no fallback to the main table for replies.
ip rule del pref 32766
ip rule del pref 32767
ip route add table 20110 10.77.0.0/24 dev tiernest0 proto 186 src 10.77.0.2
ip rule add pref 9980 lookup 20110
ip route add table 42 default via 198.51.100.1 dev wlan0 onlink
ip rule add pref 10000 iif ap0 lookup 42
ip route add table 43 192.168.77.0/24 dev ap0
ip rule add pref 10010 iif wlan0 lookup 43
ip rule add pref 32000 unreachable
iptables -P FORWARD DROP
iptables -A FORWARD -i ap0 -o wlan0 -j ACCEPT
iptables -A FORWARD -i wlan0 -o ap0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.77.0/24 -o wlan0 -j MASQUERADE
echo 1 > /proc/sys/net/ipv4/ip_forward # Only this disposable namespace.
printf '20110 9980\n' > "$TN_RUN/lease"
printf '10.77.0.0/24\n' > "$TN_RUN/routes"
: > "$TN_STAGE/hotspot-proxies"
printf 'Tether state:\n  ap0 - TetheredState - lastError = 0\n  Upstream wanted: true\n' > "$DIR/tether-state"
snapshot() {
    ip -4 rule show
    ip -4 route show table all
    iptables-save | sed -E 's/\[[0-9]+:[0-9]+\]/[0:0]/g; /^# /d'
}
snapshot > "$DIR/before"
client_ping() { nsenter -t "$CLIENT" -n -- ping -c 1 -W 1 "$1" >/dev/null 2>&1; }
if client_ping 10.77.0.9; then echo 'Unexpected overlay access before enable'; exit 1; fi
client_ping 198.51.100.1
echo on > "$TN_STAGE/hotspot-query"
[ "$(sync_hotspot | head -n 1)" = hotspot_state=active ]
client_ping 10.77.0.9
echo 'PASS: hotspot client reaches overlay with NAT and a scoped return route'
client_ping 198.51.100.1
echo 'PASS: ordinary hotspot internet still uses the system path'
if nsenter -t "$MESH" -n -- ping -c 1 -W 1 192.168.77.2 >/dev/null 2>&1; then
    echo 'Unexpected inbound overlay connection'; exit 1
fi
echo 'PASS: new overlay-to-client connection blocked'
snapshot > "$DIR/active"
sync_hotspot >/dev/null
snapshot > "$DIR/again"
cmp "$DIR/active" "$DIR/again"
echo 'PASS: repeated maintenance does not duplicate or rebuild rules'
echo off > "$TN_STAGE/hotspot-query"
sync_hotspot >/dev/null
snapshot > "$DIR/after"
cmp "$DIR/before" "$DIR/after"
if client_ping 10.77.0.9; then echo 'Access survived disable'; exit 1; fi
client_ping 198.51.100.1
echo 'PASS: disable exactly restores rules and ordinary internet'
echo on > "$TN_STAGE/hotspot-query"
sync_hotspot >/dev/null
# A new shell has no previous variables; the root-owned journal is sufficient.
sh -c '. "$1/engine-lib.sh"; . "$1/hotspot-lib.sh"; TN_RUN="$1/root/run"; cleanup_hotspot' sh "$DIR"
snapshot > "$DIR/recovered"
cmp "$DIR/before" "$DIR/recovered"
echo 'PASS: a new process cleans an interrupted session from its journal'

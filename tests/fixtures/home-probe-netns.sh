#!/system/bin/sh
set -eu
DIR=$1
PROBE=$DIR/home-probe
HTTP=$DIR/home-http
PIDS=''
cleanup() { for pid in $PIDS; do kill "$pid" 2>/dev/null || true; done; wait 2>/dev/null || true; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
unshare -n sleep 120 & ROUTER=$!; PIDS="$PIDS $ROUTER"
unshare -n sleep 120 & MESH=$!; PIDS="$PIDS $MESH"
# Let each child enter its namespace before moving veth endpoints into it.
for pid in "$ROUTER" "$MESH"; do
    for attempt in 1 2 3 4 5 6 7 8 9 10; do
        [ "$(readlink /proc/$pid/ns/net)" != "$(readlink /proc/$$/ns/net)" ] && break
        sleep 0.1
    done
    [ "$(readlink /proc/$pid/ns/net)" != "$(readlink /proc/$$/ns/net)" ] || exit 1
done
ip link set lo up
ip link add wlan0 type veth peer name router0
ip link add tiernest0 type veth peer name mesh0
ip link set router0 netns "$ROUTER"
ip link set mesh0 netns "$MESH"
ip link set wlan0 up
ip link set tiernest0 up
ip addr add 192.0.2.2/24 dev wlan0
ip addr add 10.77.0.2/24 dev tiernest0
ip route add default via 192.0.2.1 dev wlan0
ip route add 10.77.0.0/24 dev tiernest0 table 20110
ip rule add pref 9980 table 20110
nsenter -t "$ROUTER" -n ip link set lo up
nsenter -t "$ROUTER" -n ip link set router0 up
nsenter -t "$ROUTER" -n ip addr add 192.0.2.1/24 dev router0
nsenter -t "$MESH" -n ip link set lo up
nsenter -t "$MESH" -n ip link set mesh0 up
nsenter -t "$MESH" -n ip addr add 10.77.0.9/24 dev mesh0
ip rule show > "$DIR/rules.before"
ip -4 route show table all > "$DIR/routes.before"
start_server() {
    rm -f "$DIR/ready"
    nsenter -t "$1" -n "$HTTP" 10.77.0.9 "$2" "$DIR/ready" & SERVER=$!; PIDS="$PIDS $SERVER"
    for attempt in 1 2 3 4 5 6 7 8 9 10; do [ -f "$DIR/ready" ] && return; sleep 0.1; done
    echo 'Server did not start' >&2; exit 1
}
probe() { "$PROBE" wlan0 192.0.2.2 10.77.0.9 18080; }
start_server "$MESH" ok
timeout 4 "$HTTP" 10.77.0.9 client unused
[ "$(probe)" = reachable=0 ]
echo 'PASS: overlay-only HTTP cannot validate home Wi-Fi'
nsenter -t "$ROUTER" -n ip addr add 10.77.0.9/32 dev lo
start_server "$ROUTER" ok
[ "$(probe)" = reachable=1 ]
echo 'PASS: actual Wi-Fi gateway HTTP works despite the overlay rule'
kill "$SERVER"; wait "$SERVER" 2>/dev/null || true
start_server "$ROUTER" auth
[ "$(probe)" = reachable=1 ]
echo 'PASS: HTTP authentication response proves reachability'
kill "$SERVER"; wait "$SERVER" 2>/dev/null || true
start_server "$ROUTER" malformed
[ "$(probe)" = reachable=0 ]
echo 'PASS: non-HTTP response rejected'
kill "$SERVER"; wait "$SERVER" 2>/dev/null || true
start_server "$ROUTER" slow
# timeout's nonzero exit fails the test if the probe exceeds the total budget.
[ "$(timeout 3 "$PROBE" wlan0 192.0.2.2 10.77.0.9 18080)" = reachable=0 ]
echo 'PASS: slow response bounded by 2.5 seconds'
kill "$SERVER"; wait "$SERVER" 2>/dev/null || true
[ "$(probe)" = reachable=0 ]
echo 'PASS: refused Wi-Fi connection cannot fall back to working overlay'
if "$PROBE" wlan0 192.0.2.99 10.77.0.9 18080; then exit 1; fi
if "$PROBE" wlan1 192.0.2.2 10.77.0.9 18080; then exit 1; fi
if "$PROBE" wlan0 192.0.2.2 10.77.0.2 18080; then exit 1; fi
if "$PROBE" wlan0 192.0.2.2 127.0.0.1 18080; then exit 1; fi
if "$PROBE" 'wlan0;id' 192.0.2.2 10.77.0.9 18080; then exit 1; fi
if "$PROBE" wlan0 192.0.2.2 10.77.0.9 65536; then exit 1; fi
echo 'PASS: changed address, absent interface, self-target and invalid inputs rejected'
ip rule show > "$DIR/rules.after"
ip -4 route show table all > "$DIR/routes.after"
cmp "$DIR/rules.before" "$DIR/rules.after"
cmp "$DIR/routes.before" "$DIR/routes.after"
echo 'PASS: no policy rule or route mutations'

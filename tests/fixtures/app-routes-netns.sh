#!/system/bin/sh
# Never run outside the runner's disposable network namespace.
set -eu
DIR=$1
TN_ROOT=$DIR/root
TN_RUN=$TN_ROOT/run
TN_STAGE=$DIR/stage
mkdir -p "$TN_RUN" "$TN_STAGE" "$DIR/mock-bin"
. "$DIR/engine-lib.sh"
core_alive() { return 0; }
export TEST_REAL_IP=$(command -v ip)
export TEST_IP_TRACE=$DIR/ip.trace
cat > "$DIR/mock-bin/ip" <<'WRAPPER'
#!/system/bin/sh
printf '%s\n' "$*" >> "$TEST_IP_TRACE"
exec "$TEST_REAL_IP" "$@"
WRAPPER
chmod 755 "$DIR/mock-bin/ip"
export PATH="$DIR/mock-bin:$PATH"
ip link set lo up
ip link add tiernest0 type veth peer name mesh0
ip link set tiernest0 up
ip addr add 10.77.0.2/24 dev tiernest0
ip addr add 10.77.0.3/32 dev tiernest0
ip link add foreign0 type veth peer name other0
ip link set foreign0 up
ip route add table 20110 203.0.113.0/24 dev foreign0 proto static
ip rule add pref 9980 lookup 20110
ip route show table 20110 > "$DIR/foreign.before"
printf '10.77.0.0/24\n' > "$TN_STAGE/routes.txt"
for n in $(seq 10 136); do printf '10.77.0.%s/32\n' "$n" >> "$TN_STAGE/routes.txt"; done
sync_routes
read -r table pref < "$TN_RUN/lease"
[ "$table" = 20111 ] && [ "$pref" = 9979 ]
ip route show table "$table" > "$DIR/initial"
[ "$(wc -l < "$DIR/initial")" = 128 ]
echo 'PASS: first sync allocates a separate table and installs 128 synthetic routes'
: > "$TEST_IP_TRACE"
started=$(cut -d ' ' -f 1 /proc/uptime)
sync_routes
finished=$(cut -d ' ' -f 1 /proc/uptime)
awk -v start="$started" -v end="$finished" 'BEGIN {printf "MEASURE: unchanged_128_routes_seconds=%.2f\n", end-start}'
[ "$(grep -c '^-4 route show table ' "$TEST_IP_TRACE")" = 1 ]
if grep -Eq '^-4 route (add|replace|del) ' "$TEST_IP_TRACE"; then exit 1; fi
ip route show table "$table" > "$DIR/unchanged"
cmp "$DIR/initial" "$DIR/unchanged"
echo 'PASS: forced integrity pass reads one snapshot and writes no healthy routes'
ip route del table "$table" 10.77.0.10/32
ip route replace table "$table" 10.77.0.11/32 dev tiernest0 proto 186 src 10.77.0.3
sync_routes
ip route show table "$table" > "$DIR/repaired"
cmp "$DIR/initial" "$DIR/repaired"
echo 'PASS: missing route and wrong source are repaired'
printf '10.77.0.0/24\n' > "$TN_STAGE/routes.txt"
sync_routes
[ "$(ip route show table "$table" | wc -l)" = 1 ]
echo 'PASS: withdrawn subnets are removed'
ip route replace table "$table" 10.77.0.0/24 dev foreign0 proto static
if sync_routes; then echo 'Unexpected ownership takeover'; exit 1; fi
ip route show table "$table" | grep -q 'dev foreign0'
if ip rule show | grep -q "$pref:.*lookup $table"; then exit 1; fi
ip route show table 20110 > "$DIR/foreign.after"
cmp "$DIR/foreign.before" "$DIR/foreign.after"
echo 'PASS: foreign replacement survives while the App lookup is withdrawn'

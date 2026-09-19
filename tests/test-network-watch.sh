#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOD/bin" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/hotspot.sh" "$MOD/hotspot.sh"
cp "$ROOT/module/network_watch.sh" "$MOD/network_watch.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
sed -i 's#^HEALTH_TCP_TARGET=.*#HEALTH_TCP_TARGET=192.168.50.1#' "$MOD/settings.conf"
sed -i 's/^HEALTH_TCP_PORT=.*/HEALTH_TCP_PORT=80/' "$MOD/settings.conf"
sed -i 's/^NETWORK_WATCH_INTERVAL=.*/NETWORK_WATCH_INTERVAL=1/' "$MOD/settings.conf"
export TEST_NETWORK_CHANGE_FILE="$TMP/network-change"
export TEST_NETWORK_SAMPLED_FILE="$TMP/network-sampled"
cp "$ROOT/module/module.prop" "$MOD/module.prop"
cat > "$MOD/config/config.toml" <<'CONFIG'
hostname = "Example-Phone-A"
ipv4 = "10.42.0.10/24"
dhcp = false
rpc_portal = "127.0.0.1:15888"
[network_identity]
network_name = "Example-Network"
network_secret = "test-secret-must-not-appear"
[flags]
dev_name = "tiernest0"
CONFIG
: > "$MOD/bin/easytier-core"
: > "$MOD/bin/easytier-cli"
chmod +x "$MOD"/*.sh "$MOD/bin"/*

cat > "$MOCK/getprop" <<'MOCK'
#!/bin/sh
case "$1" in
  ro.build.version.release) echo 16 ;;
  ro.build.version.sdk) echo 36 ;;
  ro.product.brand) echo OnePlus ;;
  ro.product.model) echo PJX110 ;;
esac
MOCK
cat > "$MOCK/ping" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "$MOCK/nc" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "$MOCK/dumpsys" <<'MOCK'
#!/bin/sh
echo 'NetworkAgentInfo{VPN CONNECTED TRANSPORT_VPN}'
MOCK
cat > "$MOCK/pgrep" <<'MOCK'
#!/bin/sh
exit 1
MOCK
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
case "$*" in
  "link show dev tiernest0") exit 0 ;;
  "-4 rule show")
    echo '0: from all lookup local'
    echo '9980: from all lookup 20110'
    [ ! -f "$TEST_NETWORK_CHANGE_FILE" ] || echo '31000: from all lookup wlan0'
    ;;
  "-4 route show table 20110")
    echo '10.42.0.0/24 dev tiernest0'
    echo '192.168.50.0/24 dev tiernest0'
    ;;
  "-4 route get 10.42.0.1") echo '10.42.0.1 dev tiernest0 src 10.42.0.10' ;;
  "-4 route get 192.168.50.100") echo '192.168.50.100 dev tiernest0 src 10.42.0.10' ;;
  "-4 route get 1.1.1.1") echo '1.1.1.1 via 192.0.2.1 dev wlan0 src 192.0.2.2' ;;
  "-o link show")
    echo '1: lo: <LOOPBACK,UP>'
    echo '9: tiernest0: <POINTOPOINT,UP>'
    echo '10: tun0: <POINTOPOINT,UP>'
    echo sampled >> "$TEST_NETWORK_SAMPLED_FILE"
    ;;
  "-o -4 addr show")
    echo '9: tiernest0 inet 10.42.0.10/24 scope global tiernest0'
    echo '10: tun0 inet 10.8.0.2/32 scope global tun0'
    ;;
  "-o -4 addr show dev tiernest0") echo '9: tiernest0 inet 10.42.0.10/24 scope global tiernest0' ;;
  "-d addr show dev tiernest0") echo '9: tiernest0: <POINTOPOINT,UP> inet 10.42.0.10/24' ;;
  "-4 route show table main dev tiernest0") echo '10.42.0.0/24 dev tiernest0' ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK"/*

set +e
PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" timeout 90 /bin/bash "$MOD/network_watch.sh" &
runner_pid=$!
set -e
for _ in $(seq 1 30); do
  [[ -s "$MOD/run/network-watch.pid" ]] && break
  sleep 0.1
done
[[ -s "$MOD/run/network-watch.pid" ]]
first_pid=$(cat "$MOD/run/network-watch.pid")
[[ -d "$MOD/run/network-watch.lock" ]]
# A concurrent invocation must exit without replacing the active watcher.
PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" timeout 2 /bin/bash "$MOD/network_watch.sh"
[[ "$(cat "$MOD/run/network-watch.pid")" = "$first_pid" ]]
# Cause one change after startup, then leave all inputs stable. A nested
# transport checksum must not replace the watcher's network checksum.
for _ in $(seq 1 600); do
  [[ -f "$TEST_NETWORK_SAMPLED_FILE" && "$(wc -l < "$TEST_NETWORK_SAMPLED_FILE")" -ge 2 ]] && break
  sleep 0.1
done
[[ -f "$TEST_NETWORK_SAMPLED_FILE" && "$(wc -l < "$TEST_NETWORK_SAMPLED_FILE")" -ge 2 ]]
touch "$TEST_NETWORK_CHANGE_FILE"
# Wait for the change snapshot and two later stable samples, not a fixed short
# runtime that can expire during process startup on Windows/slow CI hosts.
for _ in $(seq 1 600); do
  [[ "$(wc -l < "$TEST_NETWORK_SAMPLED_FILE")" -ge 6 ]] && break
  sleep 0.1
done
[[ "$(wc -l < "$TEST_NETWORK_SAMPLED_FILE")" -ge 6 ]]
kill -TERM "$first_pid"
set +e
wait "$runner_pid"
rc=$?
set -e
[[ "$rc" -eq 124 || "$rc" -eq 143 || "$rc" -eq 0 ]]
[[ ! -e "$MOD/run/network-watch.pid" ]]
[[ ! -e "$MOD/run/network-watch.lock" ]]
LOG="$MOD/logs/network-watch.log"
[[ -s "$LOG" ]]
grep -q 'reason=startup' "$LOG"
[[ "$(grep -c '^reason=network-state-changed$' "$LOG")" = 2 ]]
# Each snapshot contains its own reason and the embedded transport reason.
[[ "$(grep -c '^TierNest automatic network snapshot$' "$LOG")" = 2 ]]
grep -q 'config_ipv4=10.42.0.10/24' "$LOG"
grep -q 'TRANSPORT_VPN' "$LOG"
grep -q 'easytier=OK target=10.42.0.1' "$LOG"
grep -q 'internet=OK target=1.1.1.1' "$LOG"
grep -q 'tcp_health=OK target=192.168.50.1 port=80' "$LOG"
grep -q 'tcp_compatibility=recommended' "$LOG"
grep -q '== EasyTier transport endpoints ==' "$LOG"
if grep -q 'test-secret-must-not-appear' "$LOG"; then
  echo 'network-watch.log leaked network_secret' >&2
  exit 1
fi

echo 'Network watch mock test passed.'

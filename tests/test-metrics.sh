#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOD/logs" "$MOD/run" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/metrics.sh" "$MOD/metrics.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cat > "$MOD/config/config.toml" <<'CONFIG'
ipv4 = "10.42.0.10/24"
[network_identity]
network_name = "test"
network_secret = "must-not-leak"
[flags]
dev_name = "tiernest0"
CONFIG
printf '123' > "$MOD/logs/tiernest.log"
printf '4567' > "$MOD/logs/easytier.log"
printf '89' > "$MOD/logs/network-watch.log"
printf 'abcde' > "$MOD/logs/transport.log"
echo 2 > "$MOD/run/vpn-restart-count"
echo 5 > "$MOD/run/route-sync-count"
echo 3 > "$MOD/run/health-restart-count"
echo "$(( $(date +%s) - 60 ))" > "$MOD/run/core-started-at"
printf '%s|none|tun0=172.19.0.1/30,\n' "$(date +%s)" > "$MOD/run/last-vpn-change"
printf '%s|external-vpn-change|success|7\n' "$(date +%s)" > "$MOD/run/last-recovery-event"
printf 'active protocol=tcp remote=203.0.113.7:11010\n' > "$MOD/run/transport-endpoints.txt"
printf '192.168.50.0/24|wlan0\n' > "$MOD/run/local-route-overrides.txt"
printf 'wlan0|10.42.0.0/24|tiernest0\nwlan0|192.168.50.0/24|tiernest0\n' > "$MOD/run/android-route-specs.txt"
printf 'wlan0\n' > "$MOD/run/android-route-tables.txt"
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
case "$*" in
  "-4 route show table 20110") printf '10.42.0.0/24 dev tiernest0\n192.168.50.0/24 dev tiernest0\n' ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK/ip"
export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD"
. "$MOD/common.sh"
. "$MOD/metrics.sh"
core_pid() { echo $$; }
find_tun_device() { echo tiernest0; }
output=$(print_metrics)
grep -q '^rss_kb=[0-9]' <<<"$output"
grep -q '^runtime_seconds=' <<<"$output"
grep -q '^vpn_restart_count=2$' <<<"$output"
grep -q '^route_sync_count=5$' <<<"$output"
grep -q '^health_restart_count=3$' <<<"$output"
grep -q '^route_count=2$' <<<"$output"
grep -q '^local_route_override_count=1$' <<<"$output"
grep -q '^android_app_route_count=2$' <<<"$output"
grep -q '^android_app_table_count=1$' <<<"$output"
grep -q '^transport_log_bytes=5$' <<<"$output"
grep -q '^log_total_bytes=14$' <<<"$output"
grep -q '^last_recovery_reason=external-vpn-change$' <<<"$output"
grep -q '^last_recovery_duration=7$' <<<"$output"
grep -q '^transport_endpoint_count=1$' <<<"$output"
if grep -q 'must-not-leak' <<<"$output"; then
  echo 'metrics leaked secret' >&2
  exit 1
fi
echo 'Metrics test passed.'

#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOD/bin" "$MOD/run" "$MOD/logs" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/hotspot.sh" "$MOD/hotspot.sh"
cp "$ROOT/module/tun_firewall.sh" "$MOD/tun_firewall.sh"
cp "$ROOT/module/tiernestd.sh" "$MOD/tiernestd.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
sed -i 's/^WATCHDOG_INTERVAL=.*/WATCHDOG_INTERVAL=1/; s/^HOTSPOT_FORWARD_ENABLED=.*/HOTSPOT_FORWARD_ENABLED=0/' "$MOD/settings.conf"
cp "$ROOT/module/config/config.toml" "$MOD/config/config.toml"
# An unconfigured template keeps the supervisor alive without a core.
cat > "$MOD/network_watch.sh" <<'WATCH'
#!/bin/sh
echo $$ > "${0%/*}/run/network-watch.pid"
echo launched >> "${0%/*}/run/watcher-launches"
sleep 30
WATCH
chmod +x "$MOD"/*.sh
cat > "$MOCK/getprop" <<'MOCK'
#!/bin/sh
[ "$1" = "sys.boot_completed" ] && echo 1
MOCK
cat > "$MOCK/pgrep" <<'MOCK'
#!/bin/sh
exit 1
MOCK
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
case "$*" in
  "-4 rule show") exit 0 ;;
  "-4 route flush table 20110") exit 0 ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK"/*

# A watcher surviving an earlier daemon must be adopted, not replaced by a
# short-lived duplicate whose PID would break shutdown/uninstall ownership.
/bin/sh "$MOD/network_watch.sh" &
surviving_watcher=$!
for _ in $(seq 1 30); do
  [[ -s "$MOD/run/network-watch.pid" ]] && break
  sleep 0.1
done
set +e
PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" timeout 6 /bin/bash "$MOD/tiernestd.sh" &
runner_pid=$!
set -e
for _ in $(seq 1 30); do
  [[ -s "$MOD/run/tiernestd.pid" ]] && break
  sleep 0.1
done
[[ -s "$MOD/run/tiernestd.pid" ]]
first_pid=$(cat "$MOD/run/tiernestd.pid")
[[ -d "$MOD/run/tiernestd.lock" ]]
PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" timeout 2 /bin/bash "$MOD/tiernestd.sh"
[[ "$(cat "$MOD/run/tiernestd.pid")" = "$first_pid" ]]
set +e
wait "$runner_pid"
rc=$?
set -e
[[ "$rc" -eq 124 || "$rc" -eq 143 || "$rc" -eq 0 ]]
[[ "$(wc -l < "$MOD/run/watcher-launches")" = 1 ]]
set +e
wait "$surviving_watcher"
watcher_rc=$?
set -e
[[ "$watcher_rc" -eq 143 ]]
[[ ! -e "$MOD/run/tiernestd.pid" ]]
[[ ! -e "$MOD/run/tiernestd.lock" ]]
echo 'Daemon lock test passed.'

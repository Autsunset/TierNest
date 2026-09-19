#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
export MODDIR="$TMP/module" TIERNEST_PROC_ROOT="$TMP/proc"
mkdir -p "$MODDIR/config" "$TMP/proc/1234"
. "$ROOT/module/common.sh"
cat > "$MODDIR/tiernestd.sh" <<'SH'
#!/bin/sh
touch "${0%/*}/launched"
mkdir -p "$TIERNEST_PROC_ROOT/1235"
printf '/bin/sh\0%s\0' "$0" > "$TIERNEST_PROC_ROOT/1235/cmdline"
echo 1235 > "${0%/*}/run/tiernestd.pid"
SH
chmod +x "$MODDIR/tiernestd.sh"
mock_app=0
easytier_app_vpn_active() { [ "$mock_app" = 1 ]; }
for flag in "$MANUAL_STOP_FILE" "$HOME_PAUSED_FILE" "$MODDIR/disable" "$MODDIR/remove"; do
    touch "$flag"
    ensure_daemon_running
    [[ ! -e "$MODDIR/launched" ]]
    rm "$flag"
done
mock_app=1; ensure_daemon_running; [[ ! -e "$MODDIR/launched" ]]
mock_app=0
echo 1234 > "$DAEMON_PID_FILE"
printf '/system/bin/sh\0%s/tiernestd.sh\0' "$MODDIR" > "$TMP/proc/1234/cmdline"
ensure_daemon_running
[[ ! -e "$MODDIR/launched" ]]
[[ "$(managed_script_pid "$DAEMON_PID_FILE" tiernestd.sh)" = 1234 ]]
print_supervision_status > "$TMP/status"
grep -q '^daemon_pid=1234$' "$TMP/status"
grep -q '^manual_stop=0$' "$TMP/status"
# PID reuse must not make an unrelated process count as the daemon.
printf '/system/bin/unrelated\0' > "$TMP/proc/1234/cmdline"
! managed_script_pid "$DAEMON_PID_FILE" tiernestd.sh
ensure_daemon_running
for _ in $(seq 1 50); do
    [[ -e "$MODDIR/launched" ]] && break
    sleep 0.02
done
[[ -e "$MODDIR/launched" ]]
rm "$TMP/proc/1235/cmdline"
print_supervision_status > "$TMP/status"
grep -q '^daemon_pid=stopped$' "$TMP/status"
rm "$MODDIR/launched"
mock_app=1
ensure_daemon_running boot
for _ in $(seq 1 50); do
    [[ -e "$MODDIR/launched" ]] && break
    sleep 0.02
done
[[ -e "$MODDIR/launched" ]]
echo 'Supervisor identity, explicit-stop guards and missing-daemon recovery tests passed.'

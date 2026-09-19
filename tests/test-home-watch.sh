#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
export TIERNEST_WATCH_TEST="$TMP"
export MODDIR="$TMP/module"
mkdir -p "$MODDIR/config" "$MODDIR/bin" "$MODDIR/run"
. "$ROOT/module/common.sh"
runner=''
cleanup() {
  stop_script_tree "$HOME_WATCH_PID_FILE" home_watch.sh || true
  [[ -z "$runner" ]] || wait "$runner" 2>/dev/null || true
  find "$TMP" -depth -delete
}
trap cleanup EXIT
cp "$ROOT/module/home_watch.sh" "$MODDIR/home_watch.sh"
printf 'auto\n' > "$SERVICE_MODE_FILE"
printf 'event\n' > "$TMP/mode"
cat > "$MODDIR/common.sh" <<'COMMON'
RUNDIR="$MODDIR/run"
HOME_WATCH_PID_FILE="$RUNDIR/home-watch.pid"
HOME_WATCH_LOCK_DIR="$RUNDIR/home-watch.lock"
HOME_WATCH_READY_FILE="$RUNDIR/home-watch.ready"
HOME_WATCH_ERROR_FILE="$RUNDIR/home-watch.error"
HOME_EVENT_BIN="$MODDIR/bin/tiernest-netwatch"
service_user_blocked() { [ -f "$MODDIR/config/manual_stop" ]; }
service_mode() { cat "$MODDIR/config/service-mode.state"; }
home_detection_mode() { cat "$TIERNEST_WATCH_TEST/mode"; }
home_check_interval() { cat "$TIERNEST_WATCH_TEST/interval"; }
managed_script_pid() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }
COMMON
: > "$MODDIR/hotspot.sh"
: > "$MODDIR/tun_firewall.sh"
cat > "$MODDIR/service_api.sh" <<'API'
service_with_lock() { "$@"; }
auto_reconcile_unlocked() { echo tick >> "$TIERNEST_WATCH_TEST/ticks"; }
home_monitor_failed_unlocked() { echo failure > "$HOME_WATCH_ERROR_FILE"; }
API
cat > "$HOME_EVENT_BIN" <<'SOURCE'
#!/bin/sh
echo $$ > "$TIERNEST_WATCH_TEST/event-pid"
echo ready
while IFS= read -r event; do
    [ "$event" != crash ] || exit 1
    echo change
done < "$TIERNEST_WATCH_TEST/input"
SOURCE
chmod +x "$HOME_EVENT_BIN"
mkfifo "$TMP/input"
exec 9<> "$TMP/input"
await_ticks() {
  for _ in $(seq 1 150); do
    [[ -f "$TMP/ticks" && "$(wc -l < "$TMP/ticks")" -ge "$1" ]] && return 0
    sleep 0.05
  done
  echo "Watch did not reach $1 reconciliations" >&2; return 1
}
wait_exit() {
  for _ in $(seq 1 150); do kill -0 "$runner" 2>/dev/null || return 0; sleep 0.05; done
  echo 'Watch did not exit' >&2; return 1
}
bash "$MODDIR/home_watch.sh" & runner=$!
await_ticks 3
[[ -s "$HOME_WATCH_READY_FILE" ]]
sleep 1
[[ "$(wc -l < "$TMP/ticks")" = 3 ]] # Blocking listener, no recurring reconciliation.
echo change >&9
await_ticks 6
sleep 1
[[ "$(wc -l < "$TMP/ticks")" = 6 ]]
echo crash >&9
wait_exit
wait "$runner" && { echo 'Unexpected successful listener exit' >&2; exit 1; }
runner=''
[[ -s "$HOME_WATCH_ERROR_FILE" && ! -f "$HOME_WATCH_READY_FILE" && ! -d "$HOME_WATCH_LOCK_DIR" ]]

# A real process-tree stop must also stop the blocked native event source.
: > "$TMP/ticks"
bash "$MODDIR/home_watch.sh" & runner=$!
await_ticks 3
native_pid=$(cat "$TMP/event-pid")
touch "$MANUAL_STOP_FILE"
stop_script_tree "$HOME_WATCH_PID_FILE" home_watch.sh
wait "$runner" || true
runner=''
! kill -0 "$native_pid" 2>/dev/null
[[ ! -f "$HOME_WATCH_READY_FILE" && ! -d "$HOME_WATCH_LOCK_DIR" ]]

# A fresh periodic watcher consumes the saved interval rather than a fixed 30s.
rm -f "$MANUAL_STOP_FILE"
echo poll > "$TMP/mode"
echo 1 > "$TMP/interval"
: > "$TMP/ticks"
bash "$MODDIR/home_watch.sh" & runner=$!
await_ticks 3
touch "$MANUAL_STOP_FILE"
stop_script_tree "$HOME_WATCH_PID_FILE" home_watch.sh
wait "$runner" || true
runner=''
[[ ! -d "$HOME_WATCH_LOCK_DIR" ]]
echo 'Home watcher: startup, event-only waits, live changes, source failure, child shutdown and configurable polling passed.'

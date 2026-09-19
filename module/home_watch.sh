#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/hotspot.sh"
. "$MODDIR/tun_firewall.sh"
. "$MODDIR/service_api.sh"

service_user_blocked && exit 0
[ "$(service_mode)" = auto ] || exit 0
if ! mkdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null; then
    managed_script_pid "$HOME_WATCH_PID_FILE" home_watch.sh >/dev/null && exit 0
    # The winner may still be publishing its PID.
    sleep 1
    managed_script_pid "$HOME_WATCH_PID_FILE" home_watch.sh >/dev/null && exit 0
    rmdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null || exit 0
    mkdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null || exit 0
fi
echo $$ > "$HOME_WATCH_PID_FILE"
event_pid=''
sleep_pid=''
event_fifo="$RUNDIR/home-events.$$"
cleanup_home_watch() {
    if [ -n "$sleep_pid" ]; then kill "$sleep_pid" 2>/dev/null || true; wait "$sleep_pid" 2>/dev/null || true; fi
    if [ -n "$event_pid" ]; then kill "$event_pid" 2>/dev/null || true; wait "$event_pid" 2>/dev/null || true; fi
    rm -f "$HOME_WATCH_PID_FILE" "$HOME_WATCH_READY_FILE" "$event_fifo"
    rmdir "$HOME_WATCH_LOCK_DIR" 2>/dev/null || true
}
trap cleanup_home_watch EXIT
trap 'exit 0' HUP INT TERM

rm -f "$HOME_WATCH_ERROR_FILE" "$HOME_WATCH_READY_FILE" "$event_fifo"
if [ "$(home_detection_mode)" = event ]; then
    umask 077
    mkfifo "$event_fifo" || exit 1
    "$HOME_EVENT_BIN" > "$event_fifo" &
    event_pid=$!
    while IFS= read -r event; do
        service_user_blocked && exit 0
        [ "$(service_mode)" = auto ] || exit 0
        case "$event" in
            ready) echo $$ > "$HOME_WATCH_READY_FILE";;
            change) ;;
            *) continue;;
        esac
        # A short, bounded settle window belongs to this event only. It lets
        # Android publish addresses/routes/ARP after association; then we block.
        for settle_delay in 0 1 2; do
            if [ "$settle_delay" != 0 ]; then sleep "$settle_delay" & sleep_pid=$!; wait "$sleep_pid" || true; sleep_pid=''; fi
            service_user_blocked && exit 0
            [ "$(service_mode)" = auto ] || exit 0
            service_with_lock auto_reconcile_unlocked || true
        done
    done < "$event_fifo"
    service_with_lock home_monitor_failed_unlocked || true
    exit 1
fi

echo $$ > "$HOME_WATCH_READY_FILE"
while ! service_user_blocked && [ "$(service_mode)" = auto ]; do
    service_with_lock auto_reconcile_unlocked || true
    # No snapshots, DNS lookups or log writes while the state is unchanged.
    sleep "$(home_check_interval)" &
    sleep_pid=$!
    wait "$sleep_pid" || true
    sleep_pid=''
done

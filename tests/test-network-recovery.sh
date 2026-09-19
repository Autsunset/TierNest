#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
export MODDIR="$TMP/module" TIERNEST_PROC_ROOT="$TMP/proc"
mkdir -p "$MODDIR/config" "$TMP/proc"
. "$ROOT/module/common.sh"

# The real Android default-network rule survives FlClash taking route-get.
physical_dev=rmnet_data4
vpn_dev=tun0
ip() {
    case "$*" in
        '-4 route get 1.1.1.1')
            echo "1.1.1.1 dev $vpn_dev table $vpn_dev src 172.19.0.1" ;;
        '-4 rule show')
            echo '24000: from all fwmark 0x0/0x30000 iif lo uidrange 0-99999 lookup tun0'
            echo '31000: from all fwmark 0x0/0xffff iif lo lookup 1017' ;;
        '-4 route show table 1017')
            [ "$physical_dev" = none ] || echo "default via 198.18.0.2 dev $physical_dev" ;;
        "-4 route get 1.1.1.1 oif $physical_dev")
            echo "1.1.1.1 via 198.18.0.2 dev $physical_dev table 1017 src 198.18.0.2" ;;
    esac
    return 0
}
[[ "$(underlay_signature)" = 'dev=rmnet_data4|via=198.18.0.2|src=198.18.0.2|table=1017' ]]
vpn_dev=Meta
[[ "$(underlay_signature)" == dev=rmnet_data4\|* ]]
physical_dev=wlan0
[[ "$(underlay_signature)" == dev=wlan0\|* ]]
physical_dev=none
[[ "$(underlay_signature)" = none ]]
physical_dev=tiernest0
[[ "$(underlay_signature)" = none ]]

# Load production state machines without starting the daemon or any core.
eval "$(sed -n '/^reconcile_underlay_change() {/,/^}/p' "$ROOT/module/tiernestd.sh")"
eval "$(sed -n '/^reconcile_external_vpn_change() {/,/^}/p' "$ROOT/module/tiernestd.sh")"
fake_now=100
mock_underlay=cell
mock_vpn=''
mock_app=0
restarts=0
restart_fails=0
debounce_action=''
restart_action=''
date() { echo "$fake_now"; }
log_msg() { :; }
sleep() { if [ -n "$debounce_action" ]; then eval "$debounce_action"; debounce_action=''; fi; }
underlay_signature() { echo "$mock_underlay"; }
external_vpn_state() { echo "$mock_vpn"; }
easytier_app_vpn_active() { [ "$mock_app" = 1 ]; }
restart_easytier_for_reason() {
    restarts=$((restarts + 1))
    if [ -n "$restart_action" ]; then eval "$restart_action"; restart_action=''; fi
    [ "$restart_fails" = 0 ]
}
last_underlay_signature=cell; recovered_underlay_signature=cell; last_underlay_restart=0
last_external_vpn_state=''; recovered_external_vpn_state=''; last_vpn_restart=0

# FlClash alone changes only the VPN. Repeating the stable state does nothing.
mock_vpn=tun0
reconcile_underlay_change
reconcile_external_vpn_change
[[ "$restarts" = 1 && "$recovered_external_vpn_state" = tun0 ]]
reconcile_underlay_change; reconcile_external_vpn_change
[[ "$restarts" = 1 ]]

# Wi-Fi and VPN change together: the underlay restart covers both.
fake_now=200; mock_underlay=wifi; mock_vpn=tun1
reconcile_underlay_change; reconcile_external_vpn_change
[[ "$restarts" = 2 && "$recovered_external_vpn_state" = tun1 ]]

# A new VPN appearing during restart must remain pending.
fake_now=300; mock_underlay=cell; restart_action='mock_vpn=tun2'
reconcile_underlay_change
[[ "$restarts" = 3 && "$recovered_external_vpn_state" = tun1 ]]
reconcile_external_vpn_change
[[ "$restarts" = 4 && "$recovered_external_vpn_state" = tun2 ]]

# Cooldown and failure postpone a VPN change instead of losing it.
fake_now=305; mock_vpn=''
reconcile_external_vpn_change
[[ "$restarts" = 4 && "$recovered_external_vpn_state" = tun2 ]]
fake_now=340; restart_fails=1
reconcile_external_vpn_change
[[ "$restarts" = 5 && "$recovered_external_vpn_state" = tun2 ]]
fake_now=380; restart_fails=0
reconcile_external_vpn_change
[[ "$restarts" = 6 && "$recovered_external_vpn_state" = '' ]]

# Stop/disable/APP conflicts during debounce must win; so must a newer VPN state.
fake_now=420; mock_vpn=tun0; debounce_action='touch "$MANUAL_STOP_FILE"'
reconcile_external_vpn_change; [[ "$restarts" = 6 ]]
rm "$MANUAL_STOP_FILE"; debounce_action='touch "$MODDIR/disable"'
reconcile_external_vpn_change; [[ "$restarts" = 6 ]]
rm "$MODDIR/disable"; debounce_action='mock_app=1'
reconcile_external_vpn_change; [[ "$restarts" = 6 ]]
mock_app=0; debounce_action='mock_vpn=tun1'
reconcile_external_vpn_change; [[ "$restarts" = 6 ]]
reconcile_external_vpn_change; [[ "$restarts" = 7 && "$recovered_external_vpn_state" = tun1 ]]

# The actual restart records where it got to and respects a stop arriving after
# core termination; a failure leaves an explicit terminal phase for diagnostics.
eval "$(sed -n '/^record_recovery_phase() {/,/^}/p' "$ROOT/module/tiernestd.sh")"
eval "$(sed -n '/^restart_easytier_for_reason() {/,/^}/p' "$ROOT/module/tiernestd.sh")"
capture_transport_endpoints() { :; }
cleanup_hotspot_access() { :; }
cleanup_tun_firewall_guard() { :; }
stop_core() { touch "$MANUAL_STOP_FILE"; }
cleanup_route_guard() { :; }
start_core() { touch "$TMP/started"; return 1; }
! restart_easytier_for_reason test "$VPN_RESTART_COUNT_FILE"
[[ ! -e "$TMP/started" && "$(cat "$RECOVERY_PHASE_FILE")" = '420|test|cancelled' ]]
rm "$MANUAL_STOP_FILE"
stop_core() { :; }
! restart_easytier_for_reason test "$VPN_RESTART_COUNT_FILE"
[[ -e "$TMP/started" && "$(cat "$RECOVERY_PHASE_FILE")" = '420|test|failed' ]]
grep -q '|test|failed|' "$LAST_RECOVERY_EVENT_FILE"

echo 'Network recovery coalescing, retries, cancellation and phase tests passed.'

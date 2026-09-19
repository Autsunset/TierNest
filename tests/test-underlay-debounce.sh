#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
# Load only the production state-machine function, never launch the real daemon.
sed -n '/^reconcile_underlay_change() {/,/^}/p' "$ROOT/module/tiernestd.sh" > "$TMP/function.sh"
. "$TMP/function.sh"
MODDIR="$TMP/module"; mkdir -p "$MODDIR"
MANUAL_STOP_FILE="$TMP/manual-stop"
HOME_PAUSED_FILE="$TMP/home-paused"
eval "$(sed -n '/^service_user_blocked() {/,/^}/p' "$ROOT/module/common.sh")"
eval "$(sed -n '/^workers_blocked() {/,/^}/p' "$ROOT/module/common.sh")"
LAST_UNDERLAY_CHANGE_FILE="$TMP/changes"
UNDERLAY_RESTART_COUNT_FILE="$TMP/count"
AUTO_RESTART_ON_UNDERLAY_CHANGE=1
UNDERLAY_RESTART_DELAY=1
UNDERLAY_RESTART_COOLDOWN=30
last_underlay_signature=A; recovered_underlay_signature=A; last_underlay_restart=0
fake_now=100; restart_count=0; fail_restart=0; mock_app=0
printf 'B\nC\nC\nC\n' > "$TMP/probes"
underlay_signature() { head -n 1 "$TMP/probes"; tail -n +2 "$TMP/probes" > "$TMP/remaining"; mv "$TMP/remaining" "$TMP/probes"; }
date() { echo "$fake_now"; }
sleep() { :; }
log_msg() { :; }
easytier_app_vpn_active() { [ "$mock_app" = 1 ]; }
external_vpn_state() { echo ''; }
restart_easytier_for_reason() { restart_count=$((restart_count+1)); [ "$fail_restart" = 0 ]; }
reconcile_underlay_change
[[ "$restart_count" = 0 && "$recovered_underlay_signature" = A ]]
reconcile_underlay_change
[[ "$restart_count" = 1 && "$recovered_underlay_signature" = C ]]
printf 'C\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 1 ]]
# Cooldown must postpone, not consume, the next change.
fake_now=110; printf 'D\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 1 && "$recovered_underlay_signature" = C ]]
fake_now=140; printf 'D\nD\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 2 && "$recovered_underlay_signature" = D ]]
# A failed restart remains pending and is retried after the cooldown.
fake_now=180; fail_restart=1; printf 'E\nE\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 3 && "$recovered_underlay_signature" = D ]]
fake_now=220; fail_restart=0; printf 'E\nE\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 4 && "$recovered_underlay_signature" = E ]]
# No recovery on a missing underlay; a manual stop and an APP VPN win over debounce.
fake_now=260; printf 'none\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 4 ]]
touch "$MANUAL_STOP_FILE"; printf 'F\nF\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 4 && "$recovered_underlay_signature" = E ]]
rm "$MANUAL_STOP_FILE"; mock_app=1; printf 'F\nF\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 4 ]]
mock_app=0; printf 'F\nF\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 5 && "$recovered_underlay_signature" = F ]]
AUTO_RESTART_ON_UNDERLAY_CHANGE=0; printf 'G\n' > "$TMP/probes"; reconcile_underlay_change
[[ "$restart_count" = 5 && "$recovered_underlay_signature" = G ]]
echo 'Underlay debounce/cooldown/failure regression test passed.'

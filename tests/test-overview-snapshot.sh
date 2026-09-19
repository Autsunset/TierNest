#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
MOD="$TMP/module"; mkdir -p "$MOD/config" "$TMP/mockbin"
cp "$ROOT/module/"{common.sh,metrics.sh,settings.conf,module.prop} "$MOD/"
printf 'hostname = "test"\nipv4 = "10.0.0.1/24"\n' > "$MOD/config/config.toml"
cat > "$TMP/mockbin/ip" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "$TMP/mockbin/du" <<'MOCK'
#!/bin/sh
echo du >> "$COUNTS"
printf '123\tmodule\n'
MOCK
chmod +x "$TMP/mockbin/"*
export MODDIR="$MOD" PATH="$TMP/mockbin:/usr/bin:/bin" COUNTS="$TMP/counts"
. "$MOD/common.sh"; . "$MOD/metrics.sh"
sed -n '/^print_status() {/,/^}/p; /^print_overview() (/,/^)/p' "$ROOT/module/control.sh" > "$TMP/functions"
. "$TMP/functions"
core_pid() { echo pid >> "$COUNTS"; return 0; }
find_tun_device() { echo tun >> "$COUNTS"; return 0; }
external_vpn_state() { echo vpn >> "$COUNTS"; echo none; }
easytier_app_vpn_active() { echo app >> "$COUNTS"; return 1; }
underlay_signature() { echo underlay >> "$COUNTS"; echo 'dev=wlan0|via=10.0.0.1'; }
easytier_rpc_state() { echo rpc >> "$COUNTS"; echo healthy; }
live_transport_endpoint_count() { echo endpoints >> "$COUNTS"; echo 2; }
print_hotspot_access_status() { echo enabled=0; }
print_tun_firewall_status() { echo enabled=0; }
: > "$COUNTS"
output=$(print_overview)
for probe in pid tun vpn app underlay rpc endpoints du; do
  [[ $(grep -cx "$probe" "$COUNTS") = 1 ]] || { echo "duplicate probe: $probe"; cat "$COUNTS"; exit 1; }
done
grep -q '^schema=1$' <<< "$output"
grep -q '^status.state=stopped$' <<< "$output"
grep -q '^status.rpc_state=healthy$' <<< "$output"
grep -q '^metrics.rpc_state=healthy$' <<< "$output"
grep -q '^metrics.live_transport_endpoint_count=2$' <<< "$output"
grep -q '^metrics.module_size_bytes=125952$' <<< "$output"
# A standalone metrics/status call must still use live probes, not previous snapshot state.
[[ "${OVERVIEW_SAMPLE_READY:-0}" = 0 ]]
print_metrics >/dev/null
[[ $(grep -cx rpc "$COUNTS") = 2 ]]
[[ $(grep -cx du "$COUNTS") = 1 ]]
# Deterministic size TTL, clock rollback, version changes and malformed cache.
rm "$RUNDIR/module-size.cache"; : > "$COUNTS"
[[ $(module_size_kb_cached 100) = 123 ]]
[[ $(module_size_kb_cached 399) = 123 ]]
[[ $(grep -cx du "$COUNTS") = 1 ]]
module_size_kb_cached 400 >/dev/null; [[ $(grep -cx du "$COUNTS") = 2 ]]
module_size_kb_cached 200 >/dev/null; [[ $(grep -cx du "$COUNTS") = 3 ]]
sed -i 's/^version=.*/version=test-upgrade/' "$MOD/module.prop"
module_size_kb_cached 201 >/dev/null; [[ $(grep -cx du "$COUNTS") = 4 ]]
printf 'bad|data|cache\n' > "$RUNDIR/module-size.cache"
module_size_kb_cached 202 >/dev/null; [[ $(grep -cx du "$COUNTS") = 5 ]]
echo 'Overview single-snapshot and module-size cache tests passed.'

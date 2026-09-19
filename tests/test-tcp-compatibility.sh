#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cat > "$MOD/config/config.toml" <<'CONFIG'
hostname = "Compatibility-Test"
ipv4 = "10.42.0.51/24"
[network_identity]
network_name = "test"
network_secret = "must-not-leak"
[flags]
dev_name = "tiernest0"
use_smoltcp = false
enable_kcp_proxy = false
CONFIG
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
case "$*" in
  "-4 route show table "*) exit 0 ;;
  *) exit 0 ;;
esac
MOCK
cat > "$MOCK/nc" <<'MOCK'
#!/bin/sh
[ "${NC_MODE:-ok}" = "ok" ]
MOCK
chmod +x "$MOCK"/*
export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD"
. "$MOD/common.sh"

[[ "$(get_toml_bool enable_kcp_proxy false)" == false ]]
[[ "$(get_toml_bool use_smoltcp false)" == false ]]
[[ "$(tcp_compatibility_state)" == recommended ]]

sed -i 's/enable_kcp_proxy = false/enable_kcp_proxy = true/' "$MOD/config/config.toml"
[[ "$(tcp_compatibility_state)" == kcp-kernel-risk ]]
log_tcp_compatibility
grep -q 'KCP kernel TCP path may cause Ping/ICMP to work while HTTP/SSH TCP times out' "$MOD/logs/tiernest.log"
if grep -q 'must-not-leak' "$MOD/logs/tiernest.log"; then
  echo 'compatibility log leaked network_secret' >&2
  exit 1
fi

sed -i 's/use_smoltcp = false/use_smoltcp = true/' "$MOD/config/config.toml"
[[ "$(tcp_compatibility_state)" == kcp-smoltcp ]]

NC_MODE=ok; export NC_MODE
[[ "$(tcp_probe_result tcp_health 192.168.50.1 80)" == 'tcp_health=OK target=192.168.50.1 port=80' ]]
NC_MODE=fail; export NC_MODE
[[ "$(tcp_probe_result tcp_health 192.168.50.1 80)" == 'tcp_health=FAIL target=192.168.50.1 port=80' ]]

echo 'TCP compatibility test passed.'

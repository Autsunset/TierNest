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
cp "$ROOT/module/tun_firewall.sh" "$MOD/tun_firewall.sh"
cp "$ROOT/module/control.sh" "$MOD/control.sh"
cp "$ROOT/module/service_api.sh" "$MOD/service_api.sh"
cp "$ROOT/module/metrics.sh" "$MOD/metrics.sh"
cp "$ROOT/module/config_api.sh" "$MOD/config_api.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cat > "$MOD/config/config.toml" <<'CONFIG'
hostname = "Example-Phone-A"
ipv4 = "10.42.0.10/24"
dhcp = false
[network_identity]
network_name = "Example-Network"
network_secret = "must-not-leak"
[flags]
dev_name = "tiernest0"
use_smoltcp = false
enable_kcp_proxy = false
CONFIG
cat > "$MOCK/pgrep" <<'MOCK'
#!/bin/sh
exit 1
MOCK
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
case "$*" in
  "link show dev tiernest0") exit 0 ;;
  "-o -4 addr show")
    echo '32: tiernest0    inet 10.42.0.10/24 scope global tiernest0'
    echo '33: tun0    inet 172.19.0.1/30 scope global tun0'
    ;;
  "-4 rule show") echo '9980: from all lookup 20110' ;;
  *) exit 0 ;;
esac
MOCK
chmod +x "$MOCK"/* "$MOD"/*.sh
output=$(PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" /bin/bash "$MOD/control.sh" status)
grep -q '^state=stopped$' <<<"$output"
grep -q '^tun=$' <<<"$output"
grep -q '^external_vpn=tun0=172.19.0.1/30,$' <<<"$output"
grep -q '^network_name=Example-Network$' <<<"$output"
grep -q '^virtual_ipv4=10.42.0.10/24$' <<<"$output"
grep -q '^config_dev_name=tiernest0$' <<<"$output"
grep -q '^config_enable_kcp_proxy=false$' <<<"$output"
grep -q '^config_use_smoltcp=false$' <<<"$output"
grep -q '^tcp_compatibility=recommended$' <<<"$output"
if grep -q 'must-not-leak' <<<"$output"; then
  echo 'control status leaked network_secret' >&2
  exit 1
fi
echo 'Control status test passed.'

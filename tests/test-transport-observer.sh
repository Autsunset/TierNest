#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
PROC="$TMP/proc"
MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOD/bin" "$MOD/run" "$MOD/logs" "$PROC/4242/fd" "$PROC/4242/net" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cat > "$MOD/config/config.toml" <<'CONFIG'
hostname = "Transport-Test"
ipv4 = "10.42.0.10/24"
[network_identity]
network_name = "test"
network_secret = "must-never-appear"
[[peer]]
uri = "tcp://user:password@example.invalid:11010/private/path?token=hidden"
CONFIG
: > "$MOD/bin/easytier-core"
: > "$MOD/bin/easytier-cli"
chmod +x "$MOD/bin"/*

ln -s 'socket:[12345]' "$PROC/4242/fd/3"
ln -s 'socket:[54321]' "$PROC/4242/fd/4"
cat > "$PROC/4242/net/tcp" <<'TCP'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:2AF8 077100CB:2B02 01 00000000:00000000 00:00000000 00000000 0 0 12345 1
TCP
cat > "$PROC/4242/net/udp" <<'UDP'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   1: 00000000:5604 096433C6:5604 07 00000000:00000000 00:00000000 00000000 0 0 54321 1
UDP

cat > "$MOCK/ip" <<'MOCKIP'
#!/bin/sh
case "$*" in
  "-4 route get 203.0.113.7") echo '203.0.113.7 via 192.0.2.1 dev wlan0 src 192.0.2.2' ;;
  "-4 route get 198.51.100.9") echo '198.51.100.9 dev rmnet_data0 src 198.18.0.2' ;;
  "-o -4 addr show") echo '10: tun0 inet 10.8.0.2/32 scope global tun0' ;;
  *) exit 0 ;;
esac
MOCKIP
chmod +x "$MOCK/ip"

PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" TIERNEST_PROC_ROOT="$PROC" /bin/bash <<'SH'
set -e
. "$MODDIR/common.sh"
signature=network-signature
reason=network-reason
capture_transport_endpoints unit-test 4242
[[ "$signature" = network-signature && "$reason" = network-reason ]]
before_lines=$(wc -l < "$TRANSPORT_LOG")
capture_transport_endpoints unit-test 4242
[[ "$(wc -l < "$TRANSPORT_LOG")" = "$before_lines" ]]
SH

SNAPSHOT="$MOD/run/transport-endpoints.txt"
LOG="$MOD/logs/transport.log"
[[ -s "$SNAPSHOT" ]]
[[ -s "$LOG" ]]
grep -q '^configured_peer=tcp://<redacted>@example.invalid:11010$' "$SNAPSHOT"
grep -q 'active protocol=tcp remote=203.0.113.7:11010 state=01 inode=12345 route=203.0.113.7 via 192.0.2.1 dev wlan0' "$SNAPSHOT"
grep -q 'active protocol=udp remote=198.51.100.9:22020 state=07 inode=54321 route=198.51.100.9 dev rmnet_data0' "$SNAPSHOT"
grep -q '^external_vpn=tun0=10.8.0.2/32,$' "$SNAPSHOT"
if grep -Eq 'must-never-appear|password|token=hidden|private/path' "$SNAPSHOT" "$LOG"; then
  echo 'transport observer leaked sensitive endpoint/config data' >&2
  exit 1
fi

printf '%s\n' 'network_secret = "secret-value" --network-secret other-secret tcp://user:pass@example.com:1234/path' \
  | MODDIR="$MOD" TIERNEST_PROC_ROOT="$PROC" /bin/bash -c '. "$MODDIR/common.sh"; redact_sensitive' > "$TMP/redacted"
if grep -Eq 'secret-value|other-secret|user:pass' "$TMP/redacted"; then
  echo 'redaction helper failed' >&2
  exit 1
fi

echo 'Transport endpoint observer test passed.'

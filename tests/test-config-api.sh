#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
mkdir -p "$MOD/config" "$MOD/bin"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/config_api.sh" "$MOD/config_api.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cat > "$MOD/config/config.toml" <<'CONFIG'
instance_name = "before"
ipv4 = "10.0.0.2/24"
[network_identity]
network_name = "test"
network_secret = "old-secret"
[[peer]]
uri = "tcp://example.com:11010"
CONFIG
cat > "$MOD/bin/easytier-core" <<'CORE'
#!/bin/sh
file=""
while [ "$#" -gt 0 ]; do
  [ "$1" = "--config-file" ] && { file=$2; shift 2; continue; }
  shift
done
if grep -q 'INVALID' "$file"; then
  echo 'network_secret = "leaked-secret"' >&2
  echo 'invalid config' >&2
  exit 1
fi
exit 0
CORE
chmod +x "$MOD/bin/easytier-core"
export MODDIR="$MOD"
export TIERNEST_BACKUP_DIR="$TMP/Download/TierNest/backups"
. "$MOD/common.sh"
. "$MOD/config_api.sh"

payload=$(config_read_b64)
printf '%s' "$payload" | base64 -d | cmp -s - "$MOD/config/config.toml"
config_validate_b64 "$payload" | grep -q '^valid=1$'

cat > "$TMP/new.toml" <<'CONFIG'
instance_name = "after"
hostname = "NewPhone"
ipv4 = "10.0.0.3/24"
[network_identity]
network_name = "test"
network_secret = "new-secret"
[[peer]]
uri = "tcp://example.com:11010"
CONFIG
new_payload=$(base64 "$TMP/new.toml" | tr -d '\r\n')
result=$(config_save_b64 "$new_payload")
grep -q '^saved=' <<<"$result"
grep -q '^backup=' <<<"$result"
grep -q 'instance_name = "after"' "$MOD/config/config.toml"
[[ $(find "$CONFIG_BACKUP_DIR" -type f -name 'config-*.toml' | wc -l) -eq 1 ]]

invalid_payload=$(printf 'INVALID\nnetwork_secret = "should-hide"\n' | base64 | tr -d '\r\n')
set +e
error=$(config_validate_b64 "$invalid_payload" 2>&1)
rc=$?
set -e
[[ "$rc" -ne 0 ]]
[[ "$error" == *'<redacted>'* ]]
[[ "$error" != *'leaked-secret'* ]]
[[ "$error" != *'should-hide'* ]]

: > "$MOD/config/command_args"
set +e
error=$(config_save_b64 "$new_payload" 2>&1)
rc=$?
set -e
[[ "$rc" -ne 0 ]]
[[ "$error" == *'command_args'* ]]


cat > "$MOD/config/node-locations.conf" <<'LOCATIONS'
# hostname|location|role|longitude|latitude
Example-Phone-A|旧位置|phone||
Legacy-Node|保留条目|peer|120.1|30.2
LOCATIONS
cat > "$TMP/new-locations.conf" <<'LOCATIONS'
# hostname|location|role|longitude|latitude
Example-Phone-A|示例城市|phone|12.3456|45.6789
Example-Gateway|示例地点|gateway|12.3456|45.6789
Legacy-Node|保留条目|peer|120.1|30.2
LOCATIONS
location_payload=$(base64 "$TMP/new-locations.conf" | tr -d '\r\n')
location_result=$(save_topology_locations_b64 "$location_payload")
grep -q '^saved=' <<<"$location_result"
grep -q '^backup=' <<<"$location_result"
grep -q 'Example-Phone-A|示例城市|phone|12.3456|45.6789' "$MOD/config/node-locations.conf"
[[ $(find "$CONFIG_BACKUP_DIR" -type f -name 'node-locations-*.conf' | wc -l) -eq 1 ]]

printf 'Example-Phone-A|错误位置|phone|181|28
' > "$TMP/invalid-locations.conf"
invalid_location_payload=$(base64 "$TMP/invalid-locations.conf" | tr -d '\r\n')
set +e
location_error=$(save_topology_locations_b64 "$invalid_location_payload" 2>&1)
location_rc=$?
set -e
[[ "$location_rc" -ne 0 ]]
[[ "$location_error" == *'经纬度超出范围'* ]]
grep -q 'Example-Phone-A|示例城市|phone|12.3456|45.6789' "$MOD/config/node-locations.conf"

echo 'Config API test passed.'

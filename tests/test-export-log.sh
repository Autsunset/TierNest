#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
mkdir -p "$MOD/config" "$MOD/logs" "$MOD/bin" "$TMP/export"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/hotspot.sh" "$MOD/hotspot.sh"
cp "$ROOT/module/tun_firewall.sh" "$MOD/tun_firewall.sh"
cp "$ROOT/module/control.sh" "$MOD/control.sh"
cp "$ROOT/module/service_api.sh" "$MOD/service_api.sh"
cp "$ROOT/module/diagnose.sh" "$MOD/diagnose.sh"
cp "$ROOT/module/metrics.sh" "$MOD/metrics.sh"
cp "$ROOT/module/config_api.sh" "$MOD/config_api.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cp "$ROOT/module/module.prop" "$MOD/module.prop"
cp "$ROOT/module/config/config.toml" "$MOD/config/config.toml"
printf '%s\n' 'safe network log' > "$MOD/logs/network-watch.log"
printf '%s\n' 'safe module log' 'network_secret = "module-log-secret"' > "$MOD/logs/tiernest.log"
printf '%s\n' 'network_secret = "must-not-be-read"' > "$MOD/logs/easytier.log"
chmod +x "$MOD"/*.sh

output=$(TIERNEST_EXPORT_DIR="$TMP/export" /bin/bash "$MOD/control.sh" export-log)
[[ -f "$output" ]]
grep -q 'safe network log' "$output"
grep -q 'safe module log' "$output"
grep -q 'TierNest structured diagnostics' "$output"
if grep -Eq 'must-not-be-read|module-log-secret' "$output"; then
  echo 'exported log leaked easytier.log' >&2
  exit 1
fi

echo 'Export log test passed.'

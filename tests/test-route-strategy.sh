#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d); trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"; MOCK="$TMP/mockbin"
mkdir -p "$MOD/config" "$MOD/run" "$MOD/logs" "$MOCK"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
printf 'ipv4="10.42.0.10/24"\n[network_identity]\nnetwork_name="test"\nnetwork_secret="secret"\n[flags]\ndev_name="tiernest0"\n' > "$MOD/config/config.toml"
cat > "$MOCK/ip" <<'MOCK'
#!/bin/sh
case "$*" in "-4 route show table 20110") exit 0;; *) exit 0;; esac
MOCK
chmod +x "$MOCK/ip"
export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD"
. "$MOD/common.sh"
core_running() { return 0; }
ROUTE_STRATEGY_DEFAULT=official
ROUTE_MODE=auto
ROUTE_AUTO_SWITCH_ENABLED=1
[[ "$(route_strategy_effective)" = official ]]
[[ "$(route_mode_config_effective)" = auto ]]
[[ "$(select_route_mode)" = upstream ]]
! android_network_table_mirroring_enabled

echo legacy > "$ROUTE_STRATEGY_FILE"
[[ "$(route_strategy_effective)" = legacy ]]
[[ "$(route_mode_config_effective)" = dedicated ]]
[[ "$(select_route_mode)" = dedicated ]]
android_network_table_mirroring_enabled
! try_alternate_route_mode

echo official > "$ROUTE_STRATEGY_FILE"
[[ "$(route_strategy_effective)" = official ]]
! android_network_table_mirroring_enabled

echo invalid > "$ROUTE_STRATEGY_FILE"
[[ "$(route_strategy_effective)" = official ]]

echo 'Route strategy test passed.'

#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODULE="$ROOT/module"

# MSYS needs emulated symlinks for /proc socket fixtures with non-file targets.
case "$(uname -s)" in MINGW*|MSYS*) export MSYS="${MSYS:-} winsymlinks:lnk";; esac

required=(
  module.prop customize.sh service.sh boot-completed.sh action.sh control.sh metrics.sh config_api.sh hotspot.sh uninstall.sh common.sh
  tiernestd.sh network_watch.sh service_api.sh service_boot.sh home_watch.sh diagnose.sh tun_firewall.sh settings.conf skip_mount config/node-locations.conf
  bin/easytier-core bin/easytier-cli bin/tiernest-netwatch LICENSE THIRD_PARTY_NOTICES.md
  webroot/index.html webroot/app.js webroot/app.css webroot/icon.png
)

for path in "${required[@]}"; do
  [[ -e "$MODULE/$path" ]] || { echo "Missing: module/$path" >&2; exit 1; }
done

for script in "$MODULE"/*.sh; do
  sh -n "$script"
done
sh -n "$MODULE/META-INF/com/google/android/update-binary"
"$ROOT/tests/test-route-guard.sh"
"$ROOT/tests/test-route-table-fallback.sh"
"$ROOT/tests/test-route-mode-auto.sh"
"$ROOT/tests/test-route-strategy.sh"
"$ROOT/tests/test-android-app-routes.sh"
"$ROOT/tests/test-network-watch.sh"
"$ROOT/tests/test-transport-observer.sh"
"$ROOT/tests/test-export-log.sh"
"$ROOT/tests/test-vpn-state.sh"
"$ROOT/tests/test-recovery-signals.sh"
"$ROOT/tests/test-underlay-debounce.sh"
bash "$ROOT/tests/test-network-recovery.sh"
bash "$ROOT/tests/test-supervision.sh"
bash "$ROOT/tests/test-service-modes.sh"
bash "$ROOT/tests/test-trusted-networks.sh"
bash "$ROOT/tests/test-home-detection.sh"
bash "$ROOT/tests/test-home-watch.sh"
bash "$ROOT/tests/test-netwatch.sh"
"$ROOT/tests/test-auto-tun.sh"
"$ROOT/tests/test-control-status.sh"
"$ROOT/tests/test-config-api.sh"
bash "$ROOT/tests/test-backup-download.sh"
"$ROOT/tests/test-config-write-lock.sh"
"$ROOT/tests/test-metrics.sh"
"$ROOT/tests/test-overview-snapshot.sh"
"$ROOT/tests/test-health-probe.sh"
"$ROOT/tests/test-tcp-compatibility.sh"
"$ROOT/tests/test-customize-migration.sh"
bash "$ROOT/tests/test-install-permissions.sh"
"$ROOT/tests/test-hotspot.sh"
"$ROOT/tests/test-hotspot-access.sh"
"$ROOT/tests/test-tun-firewall.sh"
"$ROOT/tests/test-uninstall-cleanup.sh"
"$ROOT/tests/test-daemon-lock.sh"
node "$ROOT/tests/test-topology-graph.mjs"
node "$ROOT/tests/test-webui-requests.mjs"
node "$ROOT/tests/test-webui-toml.mjs" "$MODULE/config/config.toml" >/dev/null
"${PYTHON:-python3}" "$ROOT/tests/test-release-package.py"
if [[ -n "${CHROME_BIN:-}" ]] || command -v google-chrome >/dev/null 2>&1; then
  node "$ROOT/tests/test-webui-browser.mjs"
fi

if grep -R '/data/adb/magisk/busybox' "$MODULE" --exclude=update-binary; then
  echo "Hard-coded Magisk BusyBox path found." >&2
  exit 1
fi

[[ $(grep -c '^id=' "$MODULE/module.prop") -eq 1 ]]
[[ $(grep -c '^versionCode=' "$MODULE/module.prop") -eq 1 ]]
grep -q '^id=tiernest$' "$MODULE/module.prop"
grep -q '^webuiIcon=webroot/icon.png$' "$MODULE/module.prop"
grep -q '^actionIcon=webroot/icon.png$' "$MODULE/module.prop"
grep -q '^TRANSPORT_OBSERVER_ENABLED=[01]$' "$MODULE/settings.conf"
grep -q '^PREFER_DIRECT_LOCAL_SUBNETS=[01]$' "$MODULE/settings.conf"
grep -q '^ROUTE_AUTO_SWITCH_ENABLED=[01]$' "$MODULE/settings.conf"
grep -q '^ROUTE_STRATEGY_DEFAULT=\(official\|legacy\)$' "$MODULE/settings.conf"
grep -Eq '^ROUTE_MODE=(auto|upstream|target-main|dedicated)$' "$MODULE/settings.conf"
grep -q '^SYNC_ANDROID_NETWORK_TABLES=[01]$' "$MODULE/settings.conf"
grep -Eq '^ROUTE_TABLE_FALLBACK=[0-9]+$' "$MODULE/settings.conf"
grep -Eq '^TRANSPORT_ENDPOINT_LIMIT=[0-9]+$' "$MODULE/settings.conf"
grep -Eq '^HEALTH_TCP_PORT=[0-9]+$' "$MODULE/settings.conf"
grep -q '^HEALTH_TCP_TARGET=' "$MODULE/settings.conf"
grep -q '^AUTO_RESTART_ON_UNDERLAY_CHANGE=[01]$' "$MODULE/settings.conf"
grep -Eq '^UNDERLAY_RESTART_DELAY=[0-9]+$' "$MODULE/settings.conf"
grep -Eq '^UNDERLAY_RESTART_COOLDOWN=[0-9]+$' "$MODULE/settings.conf"
grep -q '^RPC_HEALTH_ENABLED=[01]$' "$MODULE/settings.conf"
grep -Eq '^RPC_HEALTH_INTERVAL=[0-9]+$' "$MODULE/settings.conf"
grep -Eq '^RPC_FAIL_THRESHOLD=[0-9]+$' "$MODULE/settings.conf"
grep -Eq '^RPC_RESTART_COOLDOWN=[0-9]+$' "$MODULE/settings.conf"
grep -q '^HOTSPOT_CLIENT_ACCESS_ENABLED=[01]$' "$MODULE/settings.conf"
grep -Eq '^HOTSPOT_ACCESS_CHECK_INTERVAL=[0-9]+$' "$MODULE/settings.conf"
grep -Eq '^HOTSPOT_ACCESS_RULE_PRIORITY=[0-9]+$' "$MODULE/settings.conf"
grep -Eq '^HOTSPOT_ACCESS_RULE_PRIORITY_MIN=[0-9]+$' "$MODULE/settings.conf"
grep -q '^HOTSPOT_ACCESS_INTERFACE=' "$MODULE/settings.conf"
grep -q '^HOTSPOT_ACCESS_CIDR=' "$MODULE/settings.conf"
grep -q '^HOTSPOT_ACCESS_INCLUDE_USB=[01]$' "$MODULE/settings.conf"
grep -q '^TUN_FIREWALL_GUARD=[01]$' "$MODULE/settings.conf"
# Device identities are inherited by the installer; the release has no profile override.
[[ ! -f "$MODULE/config/device-profile.txt" ]]
! grep -q '^PREFER_BUNDLED_CONFIG=' "$MODULE/settings.conf"
grep -q '^ROUTE_STRATEGY_DEFAULT=official$' "$MODULE/settings.conf"
grep -Eq '^HOTSPOT_ACCESS_MAX_TARGETS=[0-9]+$' "$MODULE/settings.conf"
[[ -f "$MODULE/webroot/icon.png" ]]
[[ -f "$MODULE/skip_mount" ]]
[[ ! -d "$MODULE/system" ]]

file "$MODULE/bin/easytier-core" | grep -q 'ARM aarch64'
file "$MODULE/bin/easytier-core" | grep -q 'statically linked'
file "$MODULE/bin/easytier-cli" | grep -q 'ARM aarch64'
file "$MODULE/bin/tiernest-netwatch" | grep -q 'ARM aarch64'

node --check "$MODULE/webroot/app.js"
grep -q '<title>TierNest Core</title>' "$MODULE/webroot/index.html"
grep -q '/internal/insets.css' "$MODULE/webroot/index.html"
external_refs=$(grep -R -E 'https?://' "$MODULE/webroot" 2>/dev/null | grep -v 'http://www.w3.org/2000/svg' || true)
if [[ -n "$external_refs" ]]; then
  printf '%s
' "$external_refs"
  echo "WebUI contains an external network dependency." >&2
  exit 1
fi

MODDIR="$MODULE" sh <<'SH'
set -e
. "$MODDIR/common.sh"
[ "$(normalize_ipv4_cidr 10.0.0.20/24)" = "10.0.0.0/24" ]
[ "$(normalize_ipv4_cidr 10.144.144.2/16)" = "10.144.0.0/16" ]
[ "$(normalize_ipv4_cidr 192.168.1.9/32)" = "192.168.1.9/32" ]
[ "$(normalize_ipv4_cidr 0.0.0.0/0)" = "0.0.0.0/0" ]
! normalize_ipv4_cidr 999.1.1.1/24 >/dev/null 2>&1
SH

echo "Module validation passed."

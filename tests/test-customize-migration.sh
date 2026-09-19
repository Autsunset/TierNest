#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT

run_installer() {
  TIERNEST_MODULES_ROOT="$CASE/modules" MODPATH="$NEW" ARCH=arm64 API=37 APATCH=true \
    bash -c '
      ui_print() { :; }
      abort() { echo "$*" >&2; exit 1; }
      set_perm() { :; }
      set_perm_recursive() { :; }
      pkill() { :; }
      cp() {
        if [ "${FAIL_UPGRADE_COPY:-0}" = 1 ] && [ "${@: -1}" = "$MODPATH/config/config.toml" ]; then return 1; fi
        command cp "$@"
      }
      date() { printf "20260912-200000\n"; }
      . "$1"
    ' bash "$ROOT/module/customize.sh"
}

new_case() {
  CASE="$TMP/$1"; OLD="$CASE/modules/tiernest"; NEW="$CASE/modules_update/tiernest"
  mkdir -p "$NEW/config" "$NEW/bin" "$NEW/META-INF"
  cp "$ROOT/module/settings.conf" "$NEW/settings.conf"
  cp "$ROOT/module/module.prop" "$NEW/module.prop"
  cp "$ROOT/module/config/config.toml" "$NEW/config/config.toml"
}

# Fresh installation has no bundled device IP, secret or profile.
new_case fresh
run_installer
cmp "$ROOT/module/config/config.toml" "$NEW/config/config.toml"
[[ ! -e "$NEW/config/device-profile.txt" ]]

# Every former private package inherits its exact identity and explicit strategy.
for label in Mi10-A13 MiPad5Pro-A16 Ace3Pro-A16; do
  new_case "$label"
  mkdir -p "$OLD/config/backups/upgrade-20260912-200000-0"
  cat > "$OLD/config/config.toml" <<CONFIG
# User formatting must survive byte-for-byte.
hostname = "User-$label"
ipv4 = "10.42.0.52/24"
dhcp = false
[network_identity]
network_name = "user-network"
network_secret = 'keep-dollar-\$-and-spaces'
[future_user_section]
unknown_value = "preserve me"
CONFIG
  printf 'profile=%s\nprofile_revision=1\n' "$label" > "$OLD/config/device-profile.txt"
  printf 'old-backup\n' > "$OLD/config/backups/existing.toml"
  printf 'collision-backup\n' > "$OLD/config/backups/upgrade-20260912-200000-0/config.toml"
  printf 'legacy\n' > "$OLD/config/route-strategy.state"
  printf 'off\n' > "$OLD/config/hotspot-client-access.state"
  printf 'user locations\n' > "$OLD/config/node-locations.conf"
  printf "auto\n" > "$OLD/config/service-mode.state"
  printf '# user preference\nmode=event\ninterval=300\n' > "$OLD/config/home-detection.conf"
  printf "interface=wlan0\ngateway=192.168.80.1\nmac=02:01:02:03:04:05\ntarget=10.80.0.1\nport=80\n" > "$OLD/config/home-network.conf"
  touch "$OLD/config/manual_stop" "$OLD/config/hotspot-forwarding.state"
  cat > "$OLD/settings.conf" <<'SETTINGS'
ROUTE_STRATEGY_DEFAULT=legacy
ROUTE_MODE=auto
HEALTH_CHECK_ENABLED=1
HEALTH_PROXY_TARGET=192.168.50.1
WATCHDOG_INTERVAL="19"
PREFER_BUNDLED_CONFIG=1
RETIRED_OPTION=not-copied
SETTINGS
  # Stale profile metadata must never force a reset.
  printf 'profile=Wrong-device\nprofile_revision=999\n' > "$NEW/config/device-profile.txt"
  run_installer
  cmp "$OLD/config/config.toml" "$NEW/config/config.toml"
  for file in route-strategy.state hotspot-client-access.state node-locations.conf manual_stop service-mode.state home-network.conf home-detection.conf; do
    cmp "$OLD/config/$file" "$NEW/config/$file"
    cmp "$OLD/config/$file" "$NEW/config/backups/upgrade-20260912-200000-1/$file"
  done
  cmp "$OLD/config/backups/existing.toml" "$NEW/config/backups/existing.toml"
  cmp "$OLD/config/config.toml" "$NEW/config/backups/upgrade-20260912-200000-1/config.toml"
  cmp "$OLD/settings.conf" "$NEW/config/backups/upgrade-20260912-200000-1/settings.conf"
  grep -q '^ROUTE_STRATEGY_DEFAULT=legacy$' "$NEW/settings.conf"
  grep -q '^WATCHDOG_INTERVAL=19$' "$NEW/settings.conf"
  grep -q '^HEALTH_PROXY_TARGET=192.168.50.1$' "$NEW/settings.conf"
  grep -q '^NETWORK_SNAPSHOT_INTERVAL=300$' "$NEW/settings.conf"
  ! grep -Eq '^(PREFER_BUNDLED_CONFIG|RETIRED_OPTION)=' "$NEW/settings.conf"
  [[ ! -e "$NEW/config/hotspot-forwarding.state" ]]
done

# Pre-strategy releases retain dedicated routing.
new_case old-routing
mkdir -p "$OLD/config"
printf 'ROUTE_MODE=dedicated\nSYNC_ANDROID_NETWORK_TABLES=1\n' > "$OLD/settings.conf"
run_installer
grep -q '^ROUTE_STRATEGY_DEFAULT=legacy$' "$NEW/settings.conf"

# Empty/invalid files remain the users configuration for later repair.
for state in empty invalid; do
  new_case "$state"
  mkdir -p "$OLD/config"
  : > "$OLD/config/config.toml"
  [[ "$state" != invalid ]] || printf '[unfinished\n' > "$OLD/config/config.toml"
  run_installer
  cmp "$OLD/config/config.toml" "$NEW/config/config.toml"
done

new_case command-mode
mkdir -p "$OLD/config"
printf '%s\n' '--hostname user-device --network-name own-network' > "$OLD/config/command_args"
run_installer
cmp "$OLD/config/command_args" "$NEW/config/command_args"

# Preserve disable ownership for the legacy module.
for disabled in no yes; do
  new_case "legacy-$disabled"
  LEGACY="$CASE/modules/easytier_magisk"
  mkdir -p "$LEGACY/config"
  printf 'hostname="legacy-user"\n' > "$LEGACY/config/config.toml"
  [[ "$disabled" != yes ]] || touch "$LEGACY/disable"
  run_installer
  cmp "$LEGACY/config/config.toml" "$NEW/config/config.toml"
  [[ -f "$LEGACY/disable" ]]
  if [[ "$disabled" == yes ]]; then [[ ! -e "$LEGACY/.disabled-by-tiernest" ]];
  else [[ -f "$LEGACY/.disabled-by-tiernest" ]]; fi
done
new_case precedence
mkdir -p "$OLD/config" "$CASE/modules/easytier_magisk/config"
printf 'hostname="tiernest-user"\n' > "$OLD/config/config.toml"
printf 'hostname="legacy-user"\n' > "$CASE/modules/easytier_magisk/config/config.toml"
printf 'DISABLE_OLD_EASYTIER_MODULE=0\n' > "$OLD/settings.conf"
run_installer
cmp "$OLD/config/config.toml" "$NEW/config/config.toml"
[[ ! -e "$CASE/modules/easytier_magisk/disable" ]]

# Never evaluate inherited shell expressions.
new_case unsafe-settings
mkdir -p "$OLD/config"
printf 'WATCHDOG_INTERVAL=$(touch "%s")\n' "$CASE/executed" > "$OLD/settings.conf"
if run_installer 2>/dev/null; then echo 'Unsafe inherited expression was accepted' >&2; exit 1; fi
[[ ! -e "$CASE/executed" ]]

# A failed staged copy must abort before changing the original or disabling another module.
new_case copy-failure
mkdir -p "$OLD/config" "$CASE/modules/easytier_magisk"
printf 'hostname="original-device"\n' > "$OLD/config/config.toml"
cp "$OLD/config/config.toml" "$CASE/before.toml"
if FAIL_UPGRADE_COPY=1 run_installer 2>/dev/null; then echo 'Failed copy did not abort' >&2; exit 1; fi
cmp "$CASE/before.toml" "$OLD/config/config.toml"
[[ ! -e "$CASE/modules/easytier_magisk/disable" ]]

# New multi-router state and the old stop choice must survive without rewriting.
new_case multi-router-state
mkdir -p "$OLD/config"
printf 'auto\n' > "$OLD/config/service-mode.state"
printf '# trusted networks\nnetwork=wlan0|192.168.80.1|02:01:02:03:04:05|10.80.0.1|80\nnetwork=wlan0|192.168.0.1|02:06:07:08:09:0a|10.80.0.1|8080\n' > "$OLD/config/home-network.conf"
touch "$OLD/config/manual_stop"
run_installer
for file in service-mode.state home-network.conf manual_stop; do
  cmp "$OLD/config/$file" "$NEW/config/$file"
  cmp "$OLD/config/$file" "$NEW/config/backups/upgrade-20260912-200000-0/$file"
done
echo 'Universal upgrade migration: 14 scenarios passed.'

#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd)
[[ -n "$TMP" && "$TMP" != / && "$TMP" != "$ROOT" ]]
trap 'find "$TMP" -depth -delete' EXIT
export MODPATH="$TMP/module" TIERNEST_MODULES_ROOT="$TMP/modules"
export PERMISSION_LOG="$TMP/permissions"
mkdir -p "$MODPATH/config" "$MODPATH/bin" "$MODPATH/META-INF" "$MODPATH/webroot"
cp "$ROOT/module/"*.sh "$MODPATH/"
cp "$ROOT/module/module.prop" "$ROOT/module/settings.conf" "$MODPATH/"
cp "$ROOT/module/config/config.toml" "$MODPATH/config/"
touch "$MODPATH/bin/easytier-core" "$MODPATH/bin/easytier-cli" "$MODPATH/bin/tiernest-netwatch"
# Root managers may normalize extracted files to 0644 despite ZIP mode bits.
# Record their permission API calls so this also works on Windows filesystems.
for script in "$MODPATH/"*.sh; do printf '%s|0644\n' "$script"; done > "$PERMISSION_LOG"
# A future executable must not depend on remembering to extend a manual list.
touch "$MODPATH/future-worker.sh"
printf '%s|0644\n' "$MODPATH/future-worker.sh" >> "$PERMISSION_LOG"
ARCH=arm64 API=36 KSU=true bash -c '
  ui_print() { :; }
  abort() { echo "$*" >&2; exit 1; }
  set_perm() { printf "%s|%s\n" "$1" "$4" >> "$PERMISSION_LOG"; }
  set_perm_recursive() {
    while IFS= read -r file; do printf "%s|%s\n" "$file" "$5"; done < <(find "$1" -type f) >> "$PERMISSION_LOG"
  }
  pkill() { :; }
  . "$1"
' bash "$MODPATH/customize.sh"
for entry in service.sh boot-completed.sh service_boot.sh home_watch.sh tiernestd.sh network_watch.sh control.sh future-worker.sh; do
  mode=$(awk -F '|' -v path="$MODPATH/$entry" '$1==path {mode=$2} END {print mode}' "$PERMISSION_LOG")
  [[ "$mode" = 0755 ]] || { echo "Installer left $entry non-executable (mode $mode)" >&2; exit 1; }
done
config_mode=$(awk -F '|' -v path="$MODPATH/config/config.toml" '$1==path {mode=$2} END {print mode}' "$PERMISSION_LOG")
[[ "$config_mode" = 0600 ]]
event_mode=$(awk -F '|' -v path="$MODPATH/bin/tiernest-netwatch" '$1==path {mode=$2} END {print mode}' "$PERMISSION_LOG")
[[ "$event_mode" = 0755 ]]
echo 'Installer permissions passed: normalized files, boot/auto workers, future scripts and private config.'

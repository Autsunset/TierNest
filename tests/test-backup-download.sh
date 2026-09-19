#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
export MODDIR="$TMP/module" TIERNEST_BACKUP_DIR="$TMP/Download/TierNest/backups"
mkdir -p "$MODDIR/config/backups/upgrade-old" "$MODDIR/bin"
cp "$ROOT/module/"{common.sh,config_api.sh,settings.conf} "$MODDIR/"
printf '#!/bin/sh\nexit 0\n' > "$MODDIR/bin/easytier-core"
chmod +x "$MODDIR/bin/easytier-core"
. "$MODDIR/common.sh"
. "$MODDIR/config_api.sh"
printf 'current\n' > "$CONFIG_FILE"
printf 'old\n' > "$CONFIG_DIR/backups/config-old.toml"
printf 'upgrade\n' > "$CONFIG_DIR/backups/upgrade-old/config.toml"
printf 'hidden\n' > "$CONFIG_DIR/backups/upgrade-old/.note"
cp -R "$CONFIG_DIR/backups" "$TMP/expected"
mkdir -p "$CONFIG_BACKUP_DIR"
printf 'already in Download\n' > "$CONFIG_BACKUP_DIR/config-old.toml"

# Reading settings migrates every old entry, preserves same-named Download files,
# and keeps the current configuration and Base64 protocol unchanged.
result=$(config_read_b64)
printf '%s' "$result" | base64 -d | cmp -s - "$CONFIG_FILE"
[[ ! -e "$CONFIG_DIR/backups" ]]
legacy=$(find "$CONFIG_BACKUP_DIR" -maxdepth 1 -type d -name 'legacy-*')
[[ -n "$legacy" ]]
backup_trees_equal "$TMP/expected" "$legacy"
grep -q 'already in Download' "$CONFIG_BACKUP_DIR/config-old.toml"
migrate_config_backups >/dev/null
[[ $(find "$CONFIG_BACKUP_DIR" -maxdepth 1 -type d -name 'legacy-*' | wc -l) = 1 ]]

# Emulated storage can reject chmod while writes and reads succeed.
chmod() { return 1; }
created=$(create_config_backup)
unset -f chmod
[[ "$created" = "$CONFIG_BACKUP_DIR"/config-*.toml ]]
cmp -s "$CONFIG_FILE" "$created"

# Copy corruption is detected before removing the original tree or saving TOML.
mkdir -p "$CONFIG_DIR/backups"
printf 'preserve me\n' > "$CONFIG_DIR/backups/config-old.toml"
cp() { command cp "$@"; printf 'corrupted\n' > "${@: -1}/config-old.toml"; }
! migrate_config_backups > "$TMP/error" 2>&1
grep -q 'preserve me' "$CONFIG_DIR/backups/config-old.toml"
[[ -z $(find "$CONFIG_BACKUP_DIR" -maxdepth 1 -name '.migration-*') ]]
unset -f cp

# Locked/unavailable Download leaves old backups and active config intact;
# reading remains available, saving fails, and a later retry migrates successfully.
target=$CONFIG_BACKUP_DIR
printf 'not a directory\n' > "$TMP/unavailable"
CONFIG_BACKUP_DIR="$TMP/unavailable/backups"
config_read_b64 >/dev/null
[[ -f "$CONFIG_DIR/backups/config-old.toml" ]]
payload=$(printf 'replacement\n' | base64 | tr -d '\r\n')
! config_save_b64 "$payload" > "$TMP/error" 2>&1
grep -q '^current$' "$CONFIG_FILE"
[[ -f "$CONFIG_DIR/backups/config-old.toml" ]]
CONFIG_BACKUP_DIR=$target
migrate_config_backups >/dev/null
[[ ! -e "$CONFIG_DIR/backups" ]]
[[ $(find "$CONFIG_BACKUP_DIR" -maxdepth 1 -type d -name 'legacy-*' | wc -l) = 2 ]]

# A configured target inside the source must never trigger recursive copying.
mkdir -p "$CONFIG_DIR/backups"
printf 'safe\n' > "$CONFIG_DIR/backups/config-safe.toml"
CONFIG_BACKUP_DIR="$CONFIG_DIR/backups/nested"
! migrate_config_backups > "$TMP/error" 2>&1
grep -q '^safe$' "$CONFIG_DIR/backups/config-safe.toml"
echo 'Download backups, verified migration, collisions, retries and save failure tests passed.'

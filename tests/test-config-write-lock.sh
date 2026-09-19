#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
MOD="$TMP/module"; mkdir -p "$MOD/config" "$MOD/bin" "$TMP/mockbin"
cp "$ROOT/module/"{common.sh,config_api.sh,settings.conf} "$MOD/"
cat > "$MOD/bin/easytier-core" <<'CORE'
#!/bin/sh
sleep 0.15
exit 0
CORE
cat > "$TMP/mockbin/date" <<'DATE'
#!/bin/sh
if [ "$1" = +%Y%m%d-%H%M%S ]; then echo 20260906-160000; else /bin/date "$@"; fi
DATE
chmod +x "$MOD/bin/easytier-core" "$TMP/mockbin/date"
export MODDIR="$MOD" PATH="$TMP/mockbin:/usr/bin:/bin" READY="$TMP/ready"
export TIERNEST_BACKUP_DIR="$TMP/Download/TierNest/backups"
. "$MOD/common.sh"; . "$MOD/config_api.sh"
printf 'instance_name = "A"\n' > "$CONFIG_FILE"
first=$(create_config_backup)
printf 'instance_name = "B"\n' > "$CONFIG_FILE"
second=$(create_config_backup)
[[ "$first" != "$second" ]]
grep -q '"A"' "$first"; grep -q '"B"' "$second"
# MSYS exposes Windows ACLs as synthesized mode bits. The 0600 assertion still
# runs on Linux/Android; ZIP permissions are checked separately on Windows.
case "$(uname -s)" in
  MINGW*|MSYS*) echo 'Windows: POSIX mode-bit check requires Linux/Android.' ;;
  *) [[ "$(stat -c %a "$first")" = 600 ]] ;;
esac
[[ ! -d "$RUNDIR/config-write.lock" ]]
# Retain the just-created backup even when many entries have the same timestamp.
for _ in $(seq 1 12); do newest=$(create_config_backup); done
[[ -f "$newest" ]]
[[ $(find "$CONFIG_BACKUP_DIR" -name 'config-*.toml' | wc -l) = 10 ]]
cat > "$TMP/runner.sh" <<'RUN'
#!/bin/sh
set -eu
. "$MODDIR/common.sh"
. "$MODDIR/config_api.sh"
hold() { : > "$READY"; while :; do sleep 0.1; done; }
case "$1" in save) config_save_b64 "$2";; hold) config_with_write_lock hold;; esac
RUN
# Independent shell processes perform concurrent save operations; preserve both predecessors.
rm "$CONFIG_BACKUP_DIR"/config-*.toml
printf 'instance_name = "A"\n' > "$CONFIG_FILE"
b=$(printf 'instance_name = "B"\n' | base64 | tr -d '\n')
c=$(printf 'instance_name = "C"\n' | base64 | tr -d '\n')
bash "$TMP/runner.sh" save "$b" > "$TMP/b-result" & pid_b=$!
if command -v busybox >/dev/null 2>&1; then
  busybox ash "$TMP/runner.sh" save "$c" > "$TMP/c-result" & pid_c=$!
else
  # Still use an independent process when BusyBox is unavailable on the host.
  bash "$TMP/runner.sh" save "$c" > "$TMP/c-result" & pid_c=$!
fi
wait "$pid_b"; wait "$pid_c"
[[ $(find "$CONFIG_BACKUP_DIR" -name 'config-*.toml' | wc -l) = 2 ]]
grep -q '"A"' "$CONFIG_BACKUP_DIR"/config-*.toml
cat "$CONFIG_FILE" "$CONFIG_BACKUP_DIR"/config-*.toml | sort > "$TMP/contents"
printf 'instance_name = "A"\ninstance_name = "B"\ninstance_name = "C"\n' | cmp -s - "$TMP/contents"
[[ ! -e "$RUNDIR/config-write.lock" ]]
# Dead owner is recovered. An active owner, or an unpublished owner, is not stolen.
mkdir "$RUNDIR/config-write.lock"; echo 99999999 > "$RUNDIR/config-write.lock/pid"
create_config_backup >/dev/null
[[ ! -e "$RUNDIR/config-write.lock" ]]
mkdir "$RUNDIR/config-write.lock"; echo $$ > "$RUNDIR/config-write.lock/pid"
sleep() { :; }
! create_config_backup > "$TMP/contended" 2>&1
[[ "$(cat "$RUNDIR/config-write.lock/pid")" = "$$" ]]
rm "$RUNDIR/config-write.lock/pid"
! create_config_backup > "$TMP/unpublished" 2>&1
[[ -d "$RUNDIR/config-write.lock" ]]
rmdir "$RUNDIR/config-write.lock"
unset -f sleep
# The actual lock-owning subshell (not its parent's $$) cleans up on TERM.
bash "$TMP/runner.sh" hold & holder=$!
for _ in $(seq 1 100); do [[ -e "$READY" ]] && break; sleep 0.03; done
[[ -e "$READY" ]]
owner=$(cat "$RUNDIR/config-write.lock/pid")
[[ "$owner" != "$holder" ]]
kill -TERM "$owner"
wait "$holder" 2>/dev/null || true
[[ ! -e "$RUNDIR/config-write.lock" ]]
echo 'Config backup uniqueness/concurrent writes/lock recovery tests passed.'

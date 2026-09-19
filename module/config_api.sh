#!/system/bin/sh

CONFIG_BACKUP_DIR=${TIERNEST_BACKUP_DIR:-/sdcard/Download/TierNest/backups}

# Run writers in a subshell so traps/variables never leak to the calling daemon.
# Keep backup + replace in the same critical section. Lock contention fails closed.
config_with_write_lock() (
    umask 077
    config_lock="$RUNDIR/config-write.lock"
    config_wait=0
    while ! mkdir "$config_lock" 2>/dev/null; do
        config_owner=$(cat "$config_lock/pid" 2>/dev/null || true)
        case "$config_owner" in *[!0-9]*|'') config_owner=0;; esac
        if [ "$config_owner" -gt 0 ] && ! kill -0 "$config_owner" 2>/dev/null; then
            # Pin the old directory before re-checking and atomically moving it away.
            # A missing owner is NOT stale: another writer may still be publishing it.
            if mkdir "$config_lock/reaping" 2>/dev/null; then
                config_owner_now=$(cat "$config_lock/pid" 2>/dev/null || true)
                if [ "$config_owner_now" = "$config_owner" ] && ! kill -0 "$config_owner" 2>/dev/null; then
                    config_stale=$(mktemp -d "$RUNDIR/config-stale.XXXXXX") || { rmdir "$config_lock/reaping" 2>/dev/null; exit 1; }
                    if mv "$config_lock" "$config_stale/lock" 2>/dev/null; then
                        rm "$config_stale/lock/pid" 2>/dev/null || true
                        rmdir "$config_stale/lock/reaping" "$config_stale/lock" "$config_stale" 2>/dev/null || true
                        continue
                    fi
                    rmdir "$config_stale" 2>/dev/null || true
                fi
                rmdir "$config_lock/reaping" 2>/dev/null || true
            fi
        fi
        config_wait=$((config_wait + 1))
        if [ "$config_wait" -ge 10 ]; then
            echo "配置正在由其他操作写入，请稍后重试（未改动原配置）" >&2
            exit 1
        fi
        sleep 1
    done
    trap 'rm -f "$config_lock/pid"; rmdir "$config_lock" 2>/dev/null || true' 0
    trap 'exit 1' HUP INT TERM
    config_owner_pid=$$
    # $$ is the parent PID in POSIX subshells; /proc/self is opened by read itself.
    if [ -r /proc/self/stat ]; then read -r config_owner_pid config_proc_rest < /proc/self/stat; fi
    printf '%s\n' "$config_owner_pid" > "$config_lock/pid" || exit 1
    "$@"
)

create_config_backup() { config_with_write_lock create_config_backup_unlocked; }
migrate_config_backups() { config_with_write_lock migrate_config_backups_unlocked; }
config_save_b64() { config_with_write_lock config_save_b64_unlocked "$@"; }
save_topology_locations_b64() { config_with_write_lock save_topology_locations_b64_unlocked "$@"; }

prepare_config_backup_dir() {
    mkdir -p "$CONFIG_BACKUP_DIR" 2>/dev/null && [ -w "$CONFIG_BACKUP_DIR" ] && return 0
    echo "无法写入备份目录：$CONFIG_BACKUP_DIR，请解锁手机并检查存储空间。" >&2
    return 1
}

# Compare bytes and directory entries in both directions; never follow symlinks.
backup_trees_equal() (
    left=$1 right=$2
    [ ! -L "$left" ] && [ ! -L "$right" ] || exit 1
    if [ -f "$left" ]; then
        [ -f "$right" ] && cmp -s "$left" "$right"
        exit $?
    fi
    [ -d "$left" ] && [ -d "$right" ] || exit 1
    for entry in "$left"/* "$left"/.[!.]* "$left"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        backup_trees_equal "$entry" "$right/${entry##*/}" || exit 1
    done
    for entry in "$right"/* "$right"/.[!.]* "$right"/..?*; do
        [ -e "$entry" ] || [ -L "$entry" ] || continue
        [ -e "$left/${entry##*/}" ] || exit 1
    done
)

# Called only on configuration actions, never from the standby watcher. Keep the
# original tree until the complete copy is verified and published in Download.
migrate_config_backups_unlocked() (
    legacy="$CONFIG_DIR/backups"
    [ -d "$legacy" ] || exit 0
    [ ! -L "$legacy" ] || { echo "旧备份目录是符号链接，未迁移。" >&2; exit 1; }
    legacy_entries=$(ls -A "$legacy") || exit 1
    [ -n "$legacy_entries" ] || exit 0
    prepare_config_backup_dir || exit 1
    legacy_real=$(cd "$legacy" && pwd -P) || exit 1
    target_real=$(cd "$CONFIG_BACKUP_DIR" && pwd -P) || exit 1
    case "$target_real/" in "$legacy_real/"*) echo "备份目标不能位于旧备份目录内。" >&2; exit 1;; esac
    staging=$(mktemp -d "$CONFIG_BACKUP_DIR/.migration-XXXXXX") || exit 1
    # Only remove the exact temporary directory allocated under the target.
    trap 'rm -rf "$staging"' 0
    trap 'exit 1' HUP INT TERM
    if ! cp -R "$legacy/." "$staging/" || ! backup_trees_equal "$legacy" "$staging"; then
        echo "旧备份复制或校验失败，原文件已保留。" >&2
        exit 1
    fi
    stamp=$(date +%Y%m%d-%H%M%S)
    index=0
    while :; do
        destination="$CONFIG_BACKUP_DIR/legacy-$stamp-$$-$index"
        [ -e "$destination" ] || [ -L "$destination" ] || break
        index=$((index + 1))
        [ "$index" -lt 1000 ] || exit 1
    done
    mv -n "$staging" "$destination" || exit 1
    [ ! -d "$staging" ] && backup_trees_equal "$legacy" "$destination" || {
        echo "备份发布校验失败，原文件已保留。" >&2; exit 1;
    }
    # Check the resolved source again before deleting the verified original tree.
    [ "$(cd "$legacy" && pwd -P)" = "$legacy_real" ] && [ ! -L "$legacy" ] || exit 1
    rm -r "$legacy" || { echo "备份已迁出，但旧目录未清理：$legacy" >&2; exit 1; }
    echo "migrated=$destination"
)

# Caller holds the write lock. Noclobber also protects pre-existing backup files.
unique_config_backup() (
    backup_source=$1
    backup_prefix=$2
    backup_suffix=$3
    prepare_config_backup_dir || exit 1
    backup_stamp=$(date +%Y%m%d-%H%M%S)
    backup_index=0
    while :; do
        backup_path="$CONFIG_BACKUP_DIR/$backup_prefix-$backup_stamp-$$-$backup_index.$backup_suffix"
        if (set -C; umask 077; : > "$backup_path") 2>/dev/null; then break; fi
        backup_index=$((backup_index + 1))
        [ "$backup_index" -lt 1000 ] || exit 1
    done
    if ! cp "$backup_source" "$backup_path" || ! cmp -s "$backup_source" "$backup_path"; then
        rm "$backup_path"; echo "备份写入或校验失败，未保存配置。" >&2; exit 1
    fi
    # Android shared storage owns the effective mode; chmod may be unsupported.
    chmod 0600 "$backup_path" 2>/dev/null || true
    echo "$backup_path"
)

validate_b64_payload() {
    payload=$1
    [ -n "$payload" ] || {
        echo "配置内容为空" >&2
        return 1
    }
    [ "${#payload}" -le 131072 ] || {
        echo "配置内容超过 128 KiB 限制" >&2
        return 1
    }
    case "$payload" in
        *[!A-Za-z0-9+/=]*)
            echo "配置传输格式无效" >&2
            return 1
            ;;
    esac
}

redact_config_output() {
    sed -E 's/(network_secret[[:space:]]*=[[:space:]]*)"[^"]*"/\1"<redacted>"/g; s/(--network-secret[=[:space:]]+)[^[:space:]]+/\1<redacted>/g'
}

decode_config_payload() {
    payload=$1
    output=$2
    validate_b64_payload "$payload" || return 1
    printf '%s' "$payload" | base64 -d > "$output" 2>/dev/null || {
        echo "配置 Base64 解码失败" >&2
        rm "$output" 2>/dev/null
        return 1
    }
    [ -s "$output" ] || {
        echo "解码后的配置为空" >&2
        rm "$output" 2>/dev/null
        return 1
    }
    chmod 0600 "$output" 2>/dev/null
}

validate_config_file() {
    file=$1
    validation_output=$(mktemp "$RUNDIR/config-validation.XXXXXX") || return 1
    if "$CORE" --check-config --config-file "$file" > "$validation_output" 2>&1; then
        rm "$validation_output" 2>/dev/null
        return 0
    fi
    redact_config_output < "$validation_output" >&2
    rm "$validation_output" 2>/dev/null
    return 1
}

config_read_b64() {
    [ -r "$CONFIG_FILE" ] || {
        echo "配置文件不存在：$CONFIG_FILE" >&2
        return 1
    }
    # Storage may still be locked. Reading stays available; later actions retry.
    migrate_config_backups >/dev/null 2>&1 || true
    base64 "$CONFIG_FILE" 2>/dev/null | tr -d '\r\n'
    echo
}

config_validate_b64() {
    payload=$1
    tmp=$(mktemp "$RUNDIR/config-validate.XXXXXX") || return 1
    decode_config_payload "$payload" "$tmp" || { rm -f "$tmp"; return 1; }
    if validate_config_file "$tmp"; then
        echo "valid=1"
        rm "$tmp" 2>/dev/null
        return 0
    fi
    rm "$tmp" 2>/dev/null
    return 1
}

prune_config_backups() {
    [ -d "$CONFIG_BACKUP_DIR" ] || return 0
    ls -1t "$CONFIG_BACKUP_DIR"/config-*.toml 2>/dev/null | awk -v keep="${1:-}" '$0 != keep {n++; if (n > (keep == "" ? 10 : 9)) print}' | while IFS= read -r old_backup; do
        case "$old_backup" in
            "$CONFIG_BACKUP_DIR"/config-*.toml) rm "$old_backup" 2>/dev/null ;;
        esac
    done
}

create_config_backup_unlocked() {
    [ -r "$CONFIG_FILE" ] || {
        echo "当前配置不存在，无法备份" >&2
        return 1
    }
    migrate_config_backups_unlocked >/dev/null || return 1
    backup=$(unique_config_backup "$CONFIG_FILE" config toml) || return 1
    prune_config_backups "$backup"
    echo "$backup"
}

config_save_b64_unlocked() {
    payload=$1
    if [ -r "$COMMAND_ARGS" ]; then
        echo "当前 command_args 模式已启用；请先移除 command_args，WebUI 配置才会生效。" >&2
        return 1
    fi
    tmp="$CONFIG_DIR/.config.new.$$.toml"
    decode_config_payload "$payload" "$tmp" || { rm -f "$tmp"; return 1; }
    validate_config_file "$tmp" || {
        rm "$tmp" 2>/dev/null
        return 1
    }
    backup=$(create_config_backup_unlocked) || {
        rm "$tmp" 2>/dev/null
        return 1
    }
    chown 0:0 "$tmp" 2>/dev/null || true
    chmod 0600 "$tmp" 2>/dev/null
    mv "$tmp" "$CONFIG_FILE" || return 1
    sync
    echo "saved=$CONFIG_FILE"
    echo "backup=$backup"
}

validate_topology_locations_file() {
    file=$1
    awk -F'|' '
        function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
        }
        /^[[:space:]]*($|#)/ { next }
        {
            count++
            if (count > 256) {
                print "节点位置条目不能超过 256 条"
                exit 1
            }
            if (NF > 5) {
                print "第 " NR " 行字段过多，应为 hostname|location|role|longitude|latitude"
                exit 1
            }
            hostname=trim($1)
            location=trim($2)
            role=trim($3)
            longitude=trim($4)
            latitude=trim($5)
            if (hostname == "") {
                print "第 " NR " 行缺少 hostname"
                exit 1
            }
            if (length(hostname) > 128 || length(location) > 128) {
                print "第 " NR " 行 hostname 或 location 过长"
                exit 1
            }
            if (role !~ /^(|local|gateway|peer|phone|tablet|public|subnet)$/) {
                print "第 " NR " 行 role 无效"
                exit 1
            }
            if ((longitude == "") != (latitude == "")) {
                print "第 " NR " 行经度和纬度必须同时填写或同时留空"
                exit 1
            }
            if (longitude != "") {
                if (longitude !~ /^-?[0-9]+([.][0-9]+)?$/ || latitude !~ /^-?[0-9]+([.][0-9]+)?$/) {
                    print "第 " NR " 行经纬度格式无效"
                    exit 1
                }
                if ((longitude + 0) < -180 || (longitude + 0) > 180 || (latitude + 0) < -90 || (latitude + 0) > 90) {
                    print "第 " NR " 行经纬度超出范围"
                    exit 1
                }
            }
        }
    ' "$file"
}

save_topology_locations_b64_unlocked() {
    payload=$1
    tmp="$RUNDIR/node-locations.$$.tmp"
    decode_config_payload "$payload" "$tmp" || { rm -f "$tmp"; return 1; }
    validation_error=$(validate_topology_locations_file "$tmp" 2>&1)
    validation_status=$?
    if [ "$validation_status" -ne 0 ]; then
        [ -n "$validation_error" ] && echo "$validation_error" >&2
        rm "$tmp" 2>/dev/null
        return 1
    fi

    migrate_config_backups_unlocked >/dev/null || { rm "$tmp"; return 1; }
    backup=""
    if [ -r "$NODE_LOCATIONS_FILE" ]; then
        backup=$(unique_config_backup "$NODE_LOCATIONS_FILE" node-locations conf) || {
            echo "节点位置备份失败" >&2
            rm "$tmp" 2>/dev/null
            return 1
        }
    fi

    chown 0:0 "$tmp" 2>/dev/null || true
    chmod 0600 "$tmp" 2>/dev/null
    mv "$tmp" "$NODE_LOCATIONS_FILE" || return 1
    sync
    echo "saved=$NODE_LOCATIONS_FILE"
    [ -n "$backup" ] && echo "backup=$backup"
}

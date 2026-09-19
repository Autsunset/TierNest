SKIPMOUNT=true
PROPFILE=false
POSTFSDATA=false
LATESTARTSERVICE=true

INSTALL_VERSION=$(sed -n 's/^version=//p' "$MODPATH/module.prop" | head -n 1)
ui_print "***************************************"
ui_print "  TierNest Core $INSTALL_VERSION"
ui_print "  统一升级包 · 自动继承已有配置"
ui_print "***************************************"
ui_print "架构：$ARCH"
ui_print "Android API：$API"

if [ "$ARCH" != "arm64" ]; then
    abort "当前安装包仅支持 arm64-v8a/aarch64。"
fi

FRAMEWORK="Magisk-compatible"
if [ "${KSU:-}" = "true" ]; then
    FRAMEWORK="KernelSU ${KSU_VER:-} (${KSU_VER_CODE:-})"
elif [ "${APATCH:-}" = "true" ]; then
    FRAMEWORK="APatch ${APATCH_VER:-} (${APATCH_VER_CODE:-})"
elif [ -n "${MAGISK_VER:-}" ]; then
    FRAMEWORK="Magisk $MAGISK_VER (${MAGISK_VER_CODE:-})"
fi
ui_print "Root 框架：$FRAMEWORK"

MODULES_ROOT=${TIERNEST_MODULES_ROOT:-/data/adb/modules}
OLD_SELF="$MODULES_ROOT/tiernest"
OLD_EASYTIER="$MODULES_ROOT/easytier_magisk"
SOURCE_CONFIG=""
SOURCE_SETTINGS=""
MIGRATE_OLD_EASYTIER_CONFIG=1
DISABLE_OLD_EASYTIER_MODULE=1
[ -r "$MODPATH/settings.conf" ] && . "$MODPATH/settings.conf"

# An upgrade is never an identity/profile migration. Existing configuration,
# including an empty or temporarily invalid TOML, remains the user's source of truth.
if [ "$OLD_SELF" != "$MODPATH" ] && [ -d "$OLD_SELF/config" ]; then
    SOURCE_CONFIG="$OLD_SELF/config"
elif [ "$MIGRATE_OLD_EASYTIER_CONFIG" = 1 ] && [ -d "$OLD_EASYTIER/config" ]; then
    SOURCE_CONFIG="$OLD_EASYTIER/config"
fi
if [ "$OLD_SELF" != "$MODPATH" ] && [ -f "$OLD_SELF/settings.conf" ]; then
    SOURCE_SETTINGS="$OLD_SELF/settings.conf"
fi

copy_upgrade_file() {
    cp -p "$1" "$2" || abort "继承配置失败，安装已中止，旧模块未修改。"
}

mkdir -p "$MODPATH/config/backups" || abort "无法创建配置备份目录。"
if [ -n "$SOURCE_CONFIG" ] && [ -d "$SOURCE_CONFIG/backups" ]; then
    cp -a "$SOURCE_CONFIG/backups/." "$MODPATH/config/backups/" \
        || abort "继承配置备份失败，安装已中止。"
fi

# Use a unique directory even for repeated upgrades in the same second.
if [ -n "$SOURCE_CONFIG" ] || [ -n "$SOURCE_SETTINGS" ]; then
    UPGRADE_STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown-time)
    UPGRADE_SUFFIX=0
    while :; do
        UPGRADE_BACKUP="$MODPATH/config/backups/upgrade-$UPGRADE_STAMP-$UPGRADE_SUFFIX"
        if mkdir "$UPGRADE_BACKUP" 2>/dev/null; then break; fi
        UPGRADE_SUFFIX=$((UPGRADE_SUFFIX + 1))
        [ "$UPGRADE_SUFFIX" -lt 1000 ] || abort "无法创建升级前备份。"
    done
    if [ -n "$SOURCE_CONFIG" ]; then
        for upgrade_file in config.toml command_args device-profile.txt node-locations.conf \
            route-strategy.state hotspot-client-access.state manual_stop service-mode.state home-network.conf home-detection.conf; do
            if [ -f "$SOURCE_CONFIG/$upgrade_file" ]; then
                copy_upgrade_file "$SOURCE_CONFIG/$upgrade_file" "$UPGRADE_BACKUP/$upgrade_file"
            fi
        done
    fi
    [ -z "$SOURCE_SETTINGS" ] || copy_upgrade_file "$SOURCE_SETTINGS" "$UPGRADE_BACKUP/settings.conf"
fi

if [ -n "$SOURCE_CONFIG" ]; then
    for upgrade_file in config.toml command_args node-locations.conf route-strategy.state \
        hotspot-client-access.state manual_stop service-mode.state home-network.conf home-detection.conf; do
        if [ -f "$SOURCE_CONFIG/$upgrade_file" ]; then
            copy_upgrade_file "$UPGRADE_BACKUP/$upgrade_file" "$MODPATH/config/$upgrade_file"
        fi
    done
    # device-profile.txt and old hotspot-forwarding.state are retired, not active preferences.
    ui_print "已继承原有组网配置、路由/热点偏好、停止状态和历史备份。"
else
    ui_print "首次安装：请在 WebUI 中填写组网配置。"
fi

if [ -n "$SOURCE_SETTINGS" ]; then
    # Merge only settings supported by the new template. New keys keep their defaults;
    # removed controls such as PREFER_BUNDLED_CONFIG cannot force a config reset.
    # Never source the old settings in the installer or evaluate shell expressions.
    awk '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t\r]+$/, "", s); return s }
        NR == FNR {
            lines[++count]=$0
            if ($0 ~ /^[A-Z][A-Z0-9_]*=/) {
                key=$0; sub(/=.*/, "", key); supported[key]=1; linekey[count]=key
            }
            next
        }
        /^[ \t]*[A-Z][A-Z0-9_]*[ \t]*=/ {
            key=$0; sub(/=.*/, "", key); key=trim(key)
            if (!(key in supported)) next
            value=substr($0, index($0, "=")+1)
            sub(/[ \t]+#.*/, "", value); value=trim(value)
            if (value ~ /^"[^"]*"$/ || value ~ /^\047[^\047]*\047$/) value=substr(value, 2, length(value)-2)
            if (value !~ /^[A-Za-z0-9_.:\/@,+-]*$/) {
                print "Unsupported setting syntax: " key > "/dev/stderr"; invalid=1; next
            }
            inherited[key]=value
        }
        END {
            if (invalid) exit 1
            for (i=1; i<=count; i++) {
                key=linekey[i]
                if (key in inherited) print key "=" inherited[key]
                else if (key == "ROUTE_STRATEGY_DEFAULT" &&
                    (inherited["ROUTE_MODE"] == "dedicated" || inherited["SYNC_ANDROID_NETWORK_TABLES"] == "1"))
                    print key "=legacy"
                else print lines[i]
            }
        }
    ' "$MODPATH/settings.conf" "$UPGRADE_BACKUP/settings.conf" > "$MODPATH/settings.conf.upgrade" \
        || abort "旧运行参数无法安全继承，安装已中止，请检查 settings.conf。"
    mv "$MODPATH/settings.conf.upgrade" "$MODPATH/settings.conf" \
        || abort "无法保存继承的运行参数。"
    ui_print "已继承已有运行参数，新参数使用新版默认值。"
fi

# Honor the preserved opt-out without evaluating the merged file as shell code.
case "$(sed -n 's/^DISABLE_OLD_EASYTIER_MODULE=//p' "$MODPATH/settings.conf" | tail -n 1)" in
    0) DISABLE_OLD_EASYTIER_MODULE=0 ;;
    *) DISABLE_OLD_EASYTIER_MODULE=1 ;;
esac

if [ "$DISABLE_OLD_EASYTIER_MODULE" = "1" ] && [ -d "$OLD_EASYTIER" ]; then
    OLD_DISABLE_MARKER="$OLD_EASYTIER/.disabled-by-tiernest"
    if [ ! -f "$OLD_EASYTIER/disable" ]; then
        touch "$OLD_EASYTIER/disable"
        touch "$OLD_DISABLE_MARKER"
        ui_print "已临时禁用旧 easytier_magisk；卸载 TierNest 时会恢复其原状态。"
    elif [ -f "$OLD_DISABLE_MARKER" ]; then
        ui_print "旧 easytier_magisk 仍由 TierNest 保持禁用。"
    else
        ui_print "旧 easytier_magisk 原本已禁用，将保持用户原状态。"
    fi
    pkill -f "$OLD_EASYTIER/easytier-core" 2>/dev/null
fi

touch "$MODPATH/skip_mount"
set_perm "$MODPATH" 0 0 0755
set_perm_recursive "$MODPATH/bin" 0 0 0755 0755
set_perm_recursive "$MODPATH/config" 0 0 0755 0600
set_perm_recursive "$MODPATH/META-INF" 0 0 0755 0644
# Managers may reset extracted files to 0644. Cover every root script, including
# boot and automatic-mode workers, without relying on ZIP bits or a manual list.
for file in \
    "$MODPATH"/*.sh \
    "$MODPATH/bin/easytier-core" \
    "$MODPATH/bin/easytier-cli"; do
    set_perm "$file" 0 0 0755
done
for file in \
    "$MODPATH/settings.conf" \
    "$MODPATH/module.prop" \
    "$MODPATH/README.md" \
    "$MODPATH/LICENSE" \
    "$MODPATH/THIRD_PARTY_NOTICES.md"; do
    [ -f "$file" ] && set_perm "$file" 0 0 0644
done
# Do not chmod/chown webroot here. KernelSU assigns the WebUI SELinux context.

ui_print ""
ui_print "安装目录：/data/adb/modules/tiernest"
ui_print "配置文件：/data/adb/modules/tiernest/config/config.toml"
ui_print "诊断脚本：su -c /data/adb/modules/tiernest/diagnose.sh"
ui_print ""
ui_print "升级已保留原有路由配置，可在 WebUI 中查看当前策略。"
ui_print "普通流量不会被 TierNest 接管。"
ui_print "KernelSU WebUI：模块详情页点击 WebUI 按钮进入。"
ui_print ""
ui_print "安装完成，请重启设备。"

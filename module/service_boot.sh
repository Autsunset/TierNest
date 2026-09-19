#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
. "$MODDIR/hotspot.sh"
. "$MODDIR/tun_firewall.sh"
. "$MODDIR/service_api.sh"
service_user_blocked && exit 0
service_with_lock boot_service_unlocked

#!/system/bin/sh
MODDIR=${0%/*}
output=$("$MODDIR/control.sh" export-log)
echo "TierNest 诊断日志已导出："
echo "$output"
echo "请把这个 txt 文件发送给开发者。"

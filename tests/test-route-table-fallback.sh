#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
MOD="$TMP/module"
MOCK="$TMP/mockbin"
STATE="$TMP/state"
mkdir -p "$MOD/config" "$MOD/logs" "$MOD/run" "$MOCK" "$STATE"
cp "$ROOT/module/common.sh" "$MOD/common.sh"
cp "$ROOT/module/settings.conf" "$MOD/settings.conf"
cp "$ROOT/module/config/config.toml" "$MOD/config/config.toml"
: > "$STATE/rules"
: > "$STATE/routes110"

cat > "$MOCK/ip" <<'MOCKIP'
#!/bin/sh
set -eu
STATE=${TEST_STATE:?}
case "$*" in
  "-4 route show table 20110") echo "ip: invalid argument '20110' to 'table ID'" >&2; exit 1 ;;
  "-4 route show table 110") cat "$STATE/routes110" ;;
  "-4 rule show") cat "$STATE/rules" ;;
  "-4 rule add pref 9980 lookup 110") echo '9980: from all lookup 110' > "$STATE/rules" ;;
  "-4 rule del pref 9980") : > "$STATE/rules" ;;
  "-4 route flush table 110") : > "$STATE/routes110" ;;
  "-4 route flush table 20110") exit 1 ;;
  *) exit 0 ;;
esac
MOCKIP
chmod +x "$MOCK/ip"

export PATH="$MOCK:/usr/bin:/bin" MODDIR="$MOD" TEST_STATE="$STATE"
. "$MOD/common.sh"
[[ "$REQUESTED_ROUTE_TABLE" = 20110 ]]
[[ "$ROUTE_TABLE" = 110 ]]
[[ "$(cat "$ROUTE_TABLE_SELECTION_FILE")" = '20110|110' ]]
grep -q 'using fallback table=110' "$MODULE_LOG"
ensure_policy_rule
grep -q '^9980: from all lookup 110$' "$STATE/rules"
cleanup_route_guard
[[ ! -s "$STATE/rules" ]]
[[ ! -e "$ROUTE_TABLE_SELECTION_FILE" ]]

echo 'Route table fallback test passed.'

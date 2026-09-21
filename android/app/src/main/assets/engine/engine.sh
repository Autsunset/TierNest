#!/system/bin/sh
umask 077
[ "$(id -u)" = 0 ] || { echo 'Root permission required' >&2; exit 1; }
case "$(uname -m)" in aarch64|arm64) ;; *) echo 'The bundled core requires native arm64; translated APK ABI support is insufficient' >&2; exit 1;; esac
TN_ROOT=/data/adb/tiernest-app
TN_RUN="$TN_ROOT/run"
TN_STAGE=$1
TN_BACKUPS=/sdcard/Download/TierNest/backups
[ -d "$TN_STAGE" ] && [ ! -L "$TN_STAGE" ] || exit 1
mkdir -p "$TN_RUN" "$TN_ROOT/bin" || exit 1
chmod 0700 "$TN_ROOT" "$TN_RUN" "$TN_ROOT/bin"
. "$TN_STAGE/engine-lib.sh" || exit 1
. "$TN_STAGE/hotspot-lib.sh" || exit 1

# One command owner. Never steal a live lock or kill an arbitrary PID.
if ! mkdir "$TN_RUN/session.lock" 2>/dev/null; then
    read -r tn_owner tn_identity < "$TN_RUN/session.lock/owner" || exit 1
    case "$tn_owner:$tn_identity" in *[!0-9:]*|:*) exit 1;; esac
    [ "$(pid_identity "$tn_owner")" != "$tn_identity" ] || { echo 'Another TierNest session is active' >&2; exit 1; }
    mv "$TN_RUN/session.lock" "$TN_RUN/stale.$$" || exit 1
    rm -f "$TN_RUN/stale.$$/owner"
    rmdir "$TN_RUN/stale.$$" || exit 1
    mkdir "$TN_RUN/session.lock" || exit 1
fi
printf '%s %s\n' "$$" "$(pid_identity "$$")" > "$TN_RUN/session.lock/owner"
cleanup() {
    cleanup_hotspot
    stop_core
    cleanup_routes
    cleanup_rpc
    rm -f "$TN_ROOT/effective.toml" "$TN_RUN/session.lock/owner"
    rmdir "$TN_RUN/session.lock" 2>/dev/null || true
}
trap cleanup 0
trap 'exit 1' HUP INT TERM
cleanup_hotspot && stop_core && cleanup_routes && cleanup_rpc || exit 1
# Root-owned payloads are installed and verified once per digest. A standby
# identity check must not reread tens of megabytes of binaries every 30 seconds.
if ! cmp -s "$TN_STAGE/SHA256SUMS" "$TN_ROOT/bin/SHA256SUMS" ||
    [ ! -x "$TN_ROOT/bin/easytier-core" ] || [ ! -x "$TN_ROOT/bin/easytier-cli" ] || [ ! -x "$TN_ROOT/bin/home-probe" ]; then
    (cd "$TN_STAGE" && sha256sum -c SHA256SUMS >/dev/null) || { echo 'Core checksum failed' >&2; exit 1; }
    for tn_bin in easytier-core easytier-cli home-probe; do
        cp "$TN_STAGE/$tn_bin" "$TN_ROOT/bin/$tn_bin.new" &&
            chmod 0700 "$TN_ROOT/bin/$tn_bin.new" &&
            mv "$TN_ROOT/bin/$tn_bin.new" "$TN_ROOT/bin/$tn_bin" || exit 1
    done
    (cd "$TN_ROOT/bin" && sha256sum -c "$TN_STAGE/SHA256SUMS" >/dev/null) || exit 1
    cp "$TN_STAGE/SHA256SUMS" "$TN_ROOT/bin/SHA256SUMS" || exit 1
fi
printf '__TN_READY__\n'
while IFS=' ' read -r tn_request tn_action; do
    case "$tn_request" in ''|*[!a-zA-Z0-9]*) break;; esac
    dispatch "$tn_action"
    tn_result=$?
    printf '\n__TN_DONE_%s:%s\n' "$tn_request" "$tn_result"
done
# EOF when the app dies or stops: trap removes the core and owned routes.

#!/usr/bin/env bash
# Real iptables/routing with three simulated peers; no host namespace mutations.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERIAL=${1:?Usage: test-app-hotspot-device.sh authorized-adb-serial}
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
ADB=${ADB:-$SDK/platform-tools/adb}
REMOTE=/data/local/tmp/tn-hotspot-test-$$
cleanup() { "$ADB" -s "$SERIAL" shell su 0 rm -rf "$REMOTE" >/dev/null; }
trap cleanup EXIT
"$ADB" -s "$SERIAL" shell mkdir "$REMOTE"
"$ADB" -s "$SERIAL" push "$ROOT/android/app/src/main/assets/engine/engine-lib.sh" "$ROOT/android/app/src/main/assets/engine/hotspot-lib.sh" \
    "$ROOT/tests/fixtures/app-hotspot-netns.sh" "$REMOTE/" >/dev/null
"$ADB" -s "$SERIAL" shell su 0 unshare -n sh ${TIERNEST_TEST_TRACE:+-x} "$REMOTE/app-hotspot-netns.sh" "$REMOTE"

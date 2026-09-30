#!/usr/bin/env bash
# Test the App's routing helper in a disposable Android network namespace.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERIAL=${1:?Usage: test-app-routes-device.sh authorized-adb-serial}
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
ADB=${ADB:-$SDK/platform-tools/adb}
REMOTE=/data/local/tmp/tn-app-routes-test-$$
cleanup() { "$ADB" -s "$SERIAL" shell su 0 rm -rf "$REMOTE" >/dev/null; }
trap cleanup EXIT
"$ADB" -s "$SERIAL" shell mkdir "$REMOTE"
"$ADB" -s "$SERIAL" push "$ROOT/android/app/src/main/assets/engine/engine-lib.sh" \
    "$ROOT/tests/fixtures/app-routes-netns.sh" "$REMOTE/" >/dev/null
"$ADB" -s "$SERIAL" shell su 0 unshare -n sh "$REMOTE/app-routes-netns.sh" "$REMOTE"

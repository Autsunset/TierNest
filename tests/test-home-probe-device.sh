#!/usr/bin/env bash
# Explicit opt-in test on an authorized, rooted Android test device. All links,
# addresses and rules exist only inside disposable unshare network namespaces.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SERIAL=${1:?Usage: test-home-probe-device.sh adb-serial}
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
ADB=${ADB:-$SDK/platform-tools/adb}
NDK=${ANDROID_NDK_HOME:-$SDK/ndk/28.2.13676358}
case "$("$ADB" -s "$SERIAL" shell uname -m | tr -d '\r')" in
    x86_64) TARGET=x86_64-linux-android;;
    aarch64) TARGET=aarch64-linux-android;;
    *) echo 'Unsupported device ABI' >&2; exit 1;;
esac
TMP=$(mktemp -d)
REMOTE=/data/local/tmp/tn-home-test-$$
trap '"$ADB" -s "$SERIAL" shell su 0 rm -rf "$REMOTE" >/dev/null; rm -rf "$TMP"' EXIT
bash "$ROOT/scripts/build-home-probe.sh" "$TARGET" "$TMP/home-probe"
"$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/${TARGET}26-clang" -Wall -Wextra -Werror -O2 \
    "$ROOT/tests/fixtures/home-http.c" -o "$TMP/home-http"
cp "$ROOT/tests/fixtures/home-probe-netns.sh" "$TMP/run.sh"
"$ADB" -s "$SERIAL" shell mkdir "$REMOTE"
"$ADB" -s "$SERIAL" push "$TMP/." "$REMOTE/" >/dev/null
"$ADB" -s "$SERIAL" shell su 0 chmod 755 "$REMOTE/home-probe" "$REMOTE/home-http"
"$ADB" -s "$SERIAL" shell su 0 unshare -n sh "$REMOTE/run.sh" "$REMOTE"

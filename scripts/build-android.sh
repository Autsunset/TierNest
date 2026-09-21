#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
[[ -d "$ANDROID_HOME/platforms/android-36" ]] || { echo 'Install Android SDK platform 36.' >&2; exit 1; }
python3 "$ROOT/tests/test-app-root-engine.py"
python3 "$ROOT/tests/test-app-hotspot.py"
python3 "$ROOT/tests/test-apk-privacy.py"
cd "$ROOT/android"
./gradlew --no-daemon testReleaseUnitTest lintRelease assembleRelease "$@"
mkdir -p "$ROOT/dist"
APP_VERSION=$(python3 -c 'import json; print(json.load(open("app/build/outputs/apk/release/output-metadata.json"))["elements"][0]["versionName"])')
case "$APP_VERSION" in ''|*[!a-zA-Z0-9._-]*) echo 'Invalid app version' >&2; exit 1;; esac
APP_APK="$ROOT/dist/TierNest-App-v$APP_VERSION.apk"
python3 "$ROOT/scripts/check-apk-privacy.py" app/build/outputs/apk/release/app-release.apk
cp app/build/outputs/apk/release/app-release.apk "$APP_APK"
# Keep the exact R8 map associated with this APK for later exported stack traces.
APP_SHA=$(sha256sum "$APP_APK" | cut -d ' ' -f 1)
SYMBOLS_BASE="${TIERNEST_SYMBOLS_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/TierNest/symbols}"
SYMBOLS="$SYMBOLS_BASE/$APP_VERSION/$APP_SHA"
mkdir -p "$SYMBOLS"
cp app/build/outputs/mapping/release/mapping.txt "$SYMBOLS/mapping.txt"
sha256sum "$APP_APK"

#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
[[ -d "$ANDROID_HOME/platforms/android-36" ]] || { echo 'Install Android SDK platform 36.' >&2; exit 1; }
python3 "$ROOT/tests/test-app-root-engine.py"
cd "$ROOT/android"
./gradlew --no-daemon testReleaseUnitTest lintRelease assembleRelease "$@"
mkdir -p "$ROOT/dist"
APP_VERSION=$(python3 -c 'import json; print(json.load(open("app/build/outputs/apk/release/output-metadata.json"))["elements"][0]["versionName"])')
case "$APP_VERSION" in ''|*[!a-zA-Z0-9._-]*) echo 'Invalid app version' >&2; exit 1;; esac
APP_APK="$ROOT/dist/TierNest-App-v$APP_VERSION.apk"
cp app/build/outputs/apk/release/app-release.apk "$APP_APK"
sha256sum "$APP_APK"

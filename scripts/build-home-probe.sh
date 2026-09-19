#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
NDK=${ANDROID_NDK_HOME:-$SDK/ndk/28.2.13676358}
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
TARGET=${1:-aarch64-linux-android}
OUT=${2:-$ROOT/android/app/build/generated/engineAssets/engine/home-probe}
case "$TARGET" in aarch64-linux-android|x86_64-linux-android) ;; *) echo 'Unsupported target' >&2; exit 1;; esac
mkdir -p "$(dirname "$OUT")"
"$TOOLCHAIN/${TARGET}26-clang" -std=c11 -Wall -Wextra -Werror -O2 -fPIE -pie \
    -ffile-prefix-map="$HOME=/build/user" -ffile-prefix-map="$ROOT=/build/tiernest" \
    -Wl,-z,max-page-size=16384 -Wl,-z,relro,-z,now -o "$OUT" "$ROOT/native/home-probe.c"
"$TOOLCHAIN/llvm-strip" "$OUT"

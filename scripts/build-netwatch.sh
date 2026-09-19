#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SDK=${ANDROID_SDK_ROOT:-${ANDROID_HOME:-"$HOME/Android/Sdk"}}
NDK=${ANDROID_NDK_HOME:-}
if [[ -z "$NDK" && -d "$SDK/ndk" ]]; then
  NDK=$(find "$SDK/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
fi
case "$(uname -s)" in
  Linux*) HOST_TAG=linux-x86_64;; Darwin*) HOST_TAG=darwin-x86_64;; MINGW*|MSYS*) HOST_TAG=windows-x86_64;;
  *) echo 'Unsupported build host; set NETWATCH_CC to an Android NDK compiler.' >&2; exit 1;;
esac
CC=${NETWATCH_CC:-"$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin/aarch64-linux-android26-clang"}
if [[ "$HOST_TAG" = windows-x86_64 && -f "$CC.cmd" ]]; then CC="$CC.cmd"; fi
[[ -x "$CC" ]] || { echo 'Install Android NDK or set ANDROID_NDK_HOME/NETWATCH_CC to build the Wi-Fi listener.' >&2; exit 1; }
mkdir -p "$ROOT/module/bin"
"$CC" -std=c11 -D_GNU_SOURCE -Os -Wall -Wextra -Werror -fPIE -pie -Wl,-s \
  -ffile-prefix-map="$ROOT"=. "$ROOT/native/netwatch.c" -o "$ROOT/module/bin/tiernest-netwatch.tmp"
chmod 0755 "$ROOT/module/bin/tiernest-netwatch.tmp"
mv "$ROOT/module/bin/tiernest-netwatch.tmp" "$ROOT/module/bin/tiernest-netwatch"

#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="${CARGO_BIN_DIR:-$HOME/.cargo/bin}:$PATH"
export ANDROID_HOME=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
export ANDROID_NDK_HOME=${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/28.2.13676358}
TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin"
[[ -x "$TOOLCHAIN/aarch64-linux-android26-clang" ]] || { echo 'Android NDK 28.2.13676358 is required.' >&2; exit 1; }
export CARGO_TARGET_DIR="$ROOT/.cache/vpn-target"
export CARGO_BUILD_JOBS=${CARGO_BUILD_JOBS:-2}
export CARGO_NET_GIT_FETCH_WITH_CLI=true
export PROTOC="$ROOT/.cache/protoc/bin/protoc"
PROTOC_SHA=a7be2928c0454f132c599e25b79b7ad1b57663f2337d7f7e468a1d59b98ec1b0
if [[ ! -x "$PROTOC" ]]; then
    mkdir -p "$ROOT/.cache/protoc"
    curl -fL --retry 2 --connect-timeout 15 --max-time 180 \
        https://github.com/protocolbuffers/protobuf/releases/download/v26.1/protoc-26.1-linux-x86_64.zip \
        -o "$ROOT/.cache/protoc-26.1.zip"
    echo "$PROTOC_SHA  $ROOT/.cache/protoc-26.1.zip" | sha256sum -c -
    unzip -qo "$ROOT/.cache/protoc-26.1.zip" -d "$ROOT/.cache/protoc"
fi
export PROTOC_INCLUDE="$ROOT/.cache/protoc/include"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$TOOLCHAIN/aarch64-linux-android26-clang"
export CC_aarch64_linux_android="$TOOLCHAIN/aarch64-linux-android26-clang"
export AR_aarch64_linux_android="$TOOLCHAIN/llvm-ar"
export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$TOOLCHAIN/x86_64-linux-android26-clang"
export CC_x86_64_linux_android="$TOOLCHAIN/x86_64-linux-android26-clang"
export AR_x86_64_linux_android="$TOOLCHAIN/llvm-ar"
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=16384"
OUT="$ROOT/android/app/build/generated/vpnJniLibs"
for spec in 'aarch64-linux-android arm64-v8a' 'x86_64-linux-android x86_64'; do
    read -r target abi <<< "$spec"
    if [[ "$abi" == arm64-v8a ]]; then triple=aarch64-linux-android; else triple=x86_64-linux-android; fi
    RESOURCE_DIR=$("$TOOLCHAIN/clang" --print-resource-dir)
    export BINDGEN_EXTRA_CLANG_ARGS="--sysroot=$TOOLCHAIN/../sysroot -isystem $RESOURCE_DIR/include -isystem $TOOLCHAIN/../sysroot/usr/include/$triple -D__ANDROID_API__=26"
    cargo +1.95.0 build --manifest-path "$ROOT/native/vpn/Cargo.toml" --locked --release --target "$target"
    mkdir -p "$OUT/$abi"
    cp "$CARGO_TARGET_DIR/$target/release/libtiernest_vpn.so" "$OUT/$abi/"
    "$TOOLCHAIN/llvm-readelf" -h "$OUT/$abi/libtiernest_vpn.so" | sed -n '/Machine:/p'
done
python3 "$ROOT/scripts/prepare-vpn-notices.py"

# EasyTier Android VPN bridge

This LGPL-3.0-only Rust crate links EasyTier **2.6.4**, source commit
`8428a89d2dabc94c97d370ec607c6ca142473626`. It uses the upstream Android mobile
TUN implementation, with Java retaining ownership of each file descriptor.
It exports a small JNI interface and opens no TCP management port.

## Build or modify

On Linux x86_64 install JDK 17, Android SDK 36, NDK `28.2.13676358`, Rust
`1.95.0`, clang/libclang, a C/C++ toolchain, curl, Python 3 and unzip:

```sh
rustup toolchain install 1.95.0 --profile minimal
rustup target add --toolchain 1.95.0 aarch64-linux-android x86_64-linux-android
sdkmanager 'platforms;android-36' 'build-tools;36.0.0' 'ndk;28.2.13676358'
./scripts/build-android.sh
```

`build-vpn-native.sh` fetches and checksum-verifies protoc 26.1, builds both
ABIs from the locked sources, and places `libtiernest_vpn.so` in
`android/app/build/generated/vpnJniLibs/<abi>/`. ELF LOAD segments use 16 KiB
alignment. The Gradle build packages these libraries in the APK. No unpublished
precompiled bridge or signing service is needed.

Bindgen uses the pinned NDK's Clang executable, libclang and explicit Android
header search paths. Host Clang resource headers must not be mixed into this
search: duplicate `stdint.h` guards can leave Android integer types undefined.

Rust and C/C++ source paths are remapped to `/build/user` and `/build/tiernest`
because panic/file/assertion locations survive symbol stripping. The final APK privacy check
rejects developer home paths in either native libraries or DEX files.

To change EasyTier itself, clone the above revision, edit it, replace the
EasyTier dependency in Cargo.toml with a local path, and update Cargo.lock.
Rebuild using the same script. To supply a separately built replacement, place
both ABI libraries in the generated directory and build with `-x prepareVpn`.
The Java interface is defined in `NativeVpn.kt`.

The alpha APK uses a local test signing key, deliberately excluded from source.
Your locally generated key cannot upgrade someone else's signature. Export
configuration first, uninstall that APK, and install your rebuilt APK; no
signature checks inside TierNest restrict a modified build or library. Never
delete the only copy of your network configuration when switching signatures.

See the repository LICENSE, bundled GPL-3.0 and LGPL-3.0 texts, and
THIRD_PARTY_NOTICES.md. Each release provides the TierNest source and locked
upstream references; Cargo retrieves the corresponding upstream sources.

## Scope

Android VpnService authorization is required. Only IPv4 mesh/subnet destinations
are routed; ordinary traffic and IPv6 stay on the physical connection. The app
UID is excluded from its VPN so every native transport socket uses the physical
network. Tests of tunneled traffic must originate in another app UID.
Root mode retains its separate process, TUN and precise policy-route cleanup.

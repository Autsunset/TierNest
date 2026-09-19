# Third-party notices

## EasyTier

TierNest redistributes unmodified `easytier-core` and `easytier-cli` binaries
from the EasyTier v2.6.4 release for Linux aarch64.

- Upstream project: EasyTier/EasyTier
- Upstream version: v2.6.4
- License: GNU Lesser General Public License v3.0 (LGPL-3.0), as provided
  by the pinned v2.6.4 source tree. The earlier Apache-2.0 label was incorrect.
- Corresponding source: https://github.com/EasyTier/EasyTier/tree/v2.6.4
- Upstream release archive SHA-256:
  `39a6b4fa21d9fdc83d3b38c90562f610c0986ecc089c4026c3be22a0ab27c5e5`

TierNest is an independent community project and is not endorsed by the
EasyTier maintainers.

## TierNest Android App dependencies and references

The standalone Android App uses AndroidX / Jetpack Compose (Apache-2.0),
Kotlin and kotlinx.coroutines (Apache-2.0), and tomlj (Apache-2.0, with its
ANTLR runtime dependency under BSD-3-Clause). The build bundles the EasyTier
license and this notice with the APK. EasyTier executables remain separate,
unmodified programs; the app does not link the MoonTier FFI binary.

MoonTier 1.0.0 was inspected as a local functional reference. No MoonTier
source, binary, font, icon or other asset is copied into this project: an
explicit license was not found in the inspected source archive. The MD3 and
HyperOS-inspired themes use Android's system fonts and original layouts;
they do not bundle Google Sans, MiSans or Xiaomi assets.

## interstellar-proxy UI reference

The Android console appearance, glass-surface treatment and grouped preference
navigation are inspired by zn0wii/interstellar-proxy (MIT), inspected at commit
`f87b3e283ede974e2dc0f63d83b3a1bef003df8b`.
Project: https://github.com/zn0wii/interstellar-proxy
Copyright (c) 2026 Ryan Yan. The MIT license is included in the APK at
`assets/licenses/interstellar-proxy-MIT.txt`. TierNest retains its own identity,
EasyTier engine and configuration logic; none of that project's proxy cores,
subscription data or branding assets are bundled.

## KernelSU WebUI JavaScript library

TierNest WebUI bundles `kernelsu` version 3.0.2, distributed under the
Apache License 2.0. It provides the local KernelSU WebUI-to-root bridge.

## smol-toml

TierNest WebUI bundles `smol-toml` version 1.8.0 for TOML parsing and
serialization. It is distributed under the BSD 3-Clause License.

Copyright (c) Squirrel Chat et al., All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

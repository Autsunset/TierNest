#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OUT="$ROOT/android/app/build/generated/engineAssets"
EASYTIER_VERSION=2.6.4 "$ROOT/scripts/fetch-upstream.sh"
mkdir -p "$OUT/engine" "$OUT/licenses"
cp "$ROOT/module/bin/easytier-core" "$ROOT/module/bin/easytier-cli" "$OUT/engine/"
(cd "$OUT/engine" && sha256sum easytier-core easytier-cli > SHA256SUMS)
cp "$ROOT/LICENSE" "$OUT/licenses/TierNest-LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$OUT/licenses/THIRD_PARTY_NOTICES.md"

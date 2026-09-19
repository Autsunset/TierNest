#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
VERSION=${EASYTIER_VERSION:-2.6.4}
CACHE="$ROOT/.cache"
ARCHIVE="$CACHE/Easytier-Magisk-v${VERSION}.zip"
PART="$ARCHIVE.part"
URL="https://github.com/EasyTier/EasyTier/releases/download/v${VERSION}/Easytier-Magisk-v${VERSION}.zip"
EXPECTED_V264="39a6b4fa21d9fdc83d3b38c90562f610c0986ecc089c4026c3be22a0ab27c5e5"

mkdir -p "$CACHE" "$ROOT/module/bin"

download_archive() {
  if curl -fL --retry 2 --connect-timeout 15 --max-time 180 -o "$PART" "$URL"; then
    mv "$PART" "$ARCHIVE"
    return 0
  fi

  rm "$PART" 2>/dev/null || true
  if (echo >/dev/tcp/127.0.0.1/7890) >/dev/null 2>&1; then
    echo "Direct download failed; retrying through 127.0.0.1:7890." >&2
    HTTPS_PROXY=http://127.0.0.1:7890 \
    HTTP_PROXY=http://127.0.0.1:7890 \
    ALL_PROXY=socks5h://127.0.0.1:7890 \
      curl -fL --retry 3 --connect-timeout 15 --max-time 300 -o "$PART" "$URL"
    mv "$PART" "$ARCHIVE"
    return 0
  fi

  echo "Download failed and proxy 127.0.0.1:7890 is unavailable." >&2
  return 1
}

[[ -s "$ARCHIVE" ]] || download_archive

ACTUAL=$(sha256sum "$ARCHIVE" | awk '{print $1}')
if [[ "$VERSION" == "2.6.4" && "$ACTUAL" != "$EXPECTED_V264" ]]; then
  echo "Checksum mismatch for $ARCHIVE" >&2
  echo "expected: $EXPECTED_V264" >&2
  echo "actual:   $ACTUAL" >&2
  exit 1
fi

unzip -p "$ARCHIVE" easytier-core > "$ROOT/module/bin/easytier-core"
unzip -p "$ARCHIVE" easytier-cli > "$ROOT/module/bin/easytier-cli"
chmod 0755 "$ROOT/module/bin/easytier-core" "$ROOT/module/bin/easytier-cli"

file "$ROOT/module/bin/easytier-core"
file "$ROOT/module/bin/easytier-cli"
echo "Upstream EasyTier v$VERSION binaries installed."

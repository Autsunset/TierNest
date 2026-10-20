#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REQUESTED_VERSION=${EASYTIER_VERSION:-}
. "$ROOT/scripts/easytier-release.conf"
if [[ -n "$REQUESTED_VERSION" && "$REQUESTED_VERSION" != "$EASYTIER_VERSION" ]]; then
  echo "This build pins EasyTier $EASYTIER_VERSION; update the release pins to change it." >&2
  exit 1
fi
VERSION=$EASYTIER_VERSION
CACHE="$ROOT/.cache"
ARCHIVE="$CACHE/Easytier-Magisk-v${VERSION}.zip"
PART="$ARCHIVE.part"
URL="https://github.com/EasyTier/EasyTier/releases/download/v${VERSION}/Easytier-Magisk-v${VERSION}.zip"

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
if [[ "$ACTUAL" != "$EASYTIER_ARCHIVE_SHA256" ]]; then
  echo "Checksum mismatch for $ARCHIVE" >&2
  echo "expected: $EASYTIER_ARCHIVE_SHA256" >&2
  echo "actual:   $ACTUAL" >&2
  exit 1
fi

# Never truncate a working payload when extraction fails. Recheck cached
# executables too, so a new release cannot silently reuse an older core.
STAGE=$(mktemp -d "$ROOT/module/bin/.upstream.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
unzip -p "$ARCHIVE" easytier-core > "$STAGE/easytier-core"
unzip -p "$ARCHIVE" easytier-cli > "$STAGE/easytier-cli"
printf '%s  %s\n' "$EASYTIER_CORE_SHA256" "$STAGE/easytier-core" \
  "$EASYTIER_CLI_SHA256" "$STAGE/easytier-cli" | sha256sum -c -
chmod 0755 "$STAGE/easytier-core" "$STAGE/easytier-cli"
for name in easytier-core easytier-cli; do
  if ! cmp -s "$STAGE/$name" "$ROOT/module/bin/$name"; then
    mv "$STAGE/$name" "$ROOT/module/bin/$name"
  fi
  chmod 0755 "$ROOT/module/bin/$name"
done

file "$ROOT/module/bin/easytier-core"
file "$ROOT/module/bin/easytier-cli"
echo "Upstream EasyTier v$VERSION binaries installed."

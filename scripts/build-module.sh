#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if (( $# )); then
  echo 'Usage: scripts/build-module.sh (one universal arm64 package; no device/private arguments)' >&2
  exit 2
fi
bash "$ROOT/scripts/build-webui.sh"
bash "$ROOT/scripts/build-netwatch.sh"
bash "$ROOT/scripts/fetch-upstream.sh"
bash "$ROOT/scripts/validate-module.sh"
"${PYTHON:-python3}" "$ROOT/scripts/package-module.py"

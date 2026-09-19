#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
echo 'TierNest now ships one universal package. Private/device arguments are no longer accepted.' >&2
echo 'Existing device configuration is inherited automatically during upgrade.' >&2
if (( $# )); then
  echo 'Run scripts/build-module.sh without a private configuration or device label.' >&2
  exit 2
fi
exec bash "$ROOT/scripts/build-module.sh"

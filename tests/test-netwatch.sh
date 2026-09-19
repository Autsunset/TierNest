#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ "$(uname -s)" != Linux* ]]; then
  echo 'Native parser regressions require a Linux host; run tests/test-netwatch.sh on Linux before release.'
  exit 0
fi
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
"${CC:-cc}" -std=c11 -D_GNU_SOURCE -Wall -Wextra -Werror -Wno-unused-function \
  "$ROOT/tests/test-netwatch.c" -o "$TMP/test-netwatch"
"$TMP/test-netwatch"

#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT/webui"
if [[ ! -d node_modules ]]; then
  npm install --ignore-scripts
fi
unlink "$ROOT/module/webroot/app.js.map" 2>/dev/null || true
unlink "$ROOT/module/webroot/app.css.map" 2>/dev/null || true
npm run build

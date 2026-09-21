#!/usr/bin/env bash
set -euo pipefail
CI_KEY_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/TierNest/ci-signing"
CI_KEY_FILE="$CI_KEY_DIR/ci.p12"
umask 077
mkdir -p "$CI_KEY_DIR"
if [[ ! -f "$CI_KEY_FILE" ]]; then
    keytool -genkeypair -noprompt -keystore "$CI_KEY_FILE" -storetype PKCS12 \
        -alias tiernest-ci -keyalg RSA -keysize 2048 -validity 3650 \
        -storepass android -keypass android -dname 'CN=TierNest CI,O=TierNest,C=US' >&2
fi
printf '%s\n' "$CI_KEY_FILE"

#!/usr/bin/env bash
# Runtime-only EasyTier legacy aliases; no host network or real core launch.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'find "$TMP" -depth -delete' EXIT
export MODDIR="$TMP/module" TIERNEST_BACKUP_DIR="$TMP/Download/TierNest/backups"
mkdir -p "$MODDIR/config" "$MODDIR/bin"
. "$ROOT/module/common.sh"
. "$ROOT/module/config_api.sh"

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
prefix = '''hostname = "synthetic-node"
rpc_portal = "127.0.0.1:17888"
description = """
[flags]
foreign_network_whitelist = "not a setting"
relay_network_whitelist = "not a setting either"
"""
literal = \'\'\'
[flags]
foreign_network_whitelist = "also text"
\'\'\'
array = ["""[flags]
foreign_network_whitelist = "array text"
"""]
[network_identity]
network_name = "synthetic-network"
network_secret = "synthetic-secret"
'''
(p / 'legacy.toml').write_bytes((prefix + '''[flags] # legacy
# foreign_network_whitelist = "comment"
foreign_network_whitelist = "synthetic-* local"
''').replace('\n', '\r\n').encode())
(p / 'quoted.toml').write_text(prefix + '''[ 'flags' ] # quoted header
'foreign_network_whitelist' = 'synthetic-*'
''')
(p / 'dotted.toml').write_text('''"flags".'foreign_network_whitelist' = "synthetic-*"
hostname = "synthetic-node"
''')
(p / 'modern-first.toml').write_text(prefix + '''["flags"]
"relay_network_whitelist" = "explicit-modern"
foreign_network_whitelist = """
ignored-old
still an old value"""
''')
(p / 'modern-last.toml').write_text(prefix + '''[flags]
foreign_network_whitelist = \'\'\'
ignored-old
\'\'\'
relay_network_whitelist = "explicit-modern"
''')
(p / 'unknown.toml').write_text(prefix + '''[flags]
foreign_network_whitelist = "*"
not_a_real_easytier_flag = true
''')
(p / 'duplicate.toml').write_text('''[flags]
foreign_network_whitelist = "*"
foreign_network_whitelist = "duplicate"
''')
(p / 'untouched.toml').write_text(prefix + '''[not_flags]
foreign_network_whitelist = "not a flags key"
''')
PY

for fixture in legacy quoted dotted modern-first modern-last untouched unknown; do
    cp "$TMP/$fixture.toml" "$TMP/$fixture.original"
    write_core_compatible_config "$TMP/$fixture.toml" "$TMP/$fixture.runtime"
    cmp "$TMP/$fixture.toml" "$TMP/$fixture.original"
    [[ $(stat -c %a "$TMP/$fixture.runtime") == 600 ]]
done
if write_core_compatible_config "$TMP/duplicate.toml" "$TMP/duplicate.runtime" 2>/dev/null; then
    echo 'Duplicate legacy keys unexpectedly accepted' >&2; exit 1
fi
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys, tomllib
p = Path(sys.argv[1])
for name, expected in [('legacy', 'synthetic-* local'), ('quoted', 'synthetic-*'), ('dotted', 'synthetic-*'),
                       ('modern-first', 'explicit-modern'), ('modern-last', 'explicit-modern')]:
    before = tomllib.loads((p / f'{name}.toml').read_text())
    after = tomllib.loads((p / f'{name}.runtime').read_text())
    old = before['flags'].pop('foreign_network_whitelist')
    before['flags'].setdefault('relay_network_whitelist', old)
    assert after == before, name
    assert after['flags']['relay_network_whitelist'] == expected
assert (p / 'untouched.toml').read_bytes() == (p / 'untouched.runtime').read_bytes()
assert 'not_a_real_easytier_flag' in (p / 'unknown.runtime').read_text()
PY

cat > "$CORE" <<'CORE'
#!/usr/bin/env python3
import pathlib, sys, tomllib
args = sys.argv[1:]
data = tomllib.loads(pathlib.Path(args[args.index('--config-file') + 1]).read_text())
unknown = data.get('flags', {}).keys() - {'relay_network_whitelist'}
sys.exit(bool(unknown))
CORE
chmod +x "$CORE"
cp "$TMP/legacy.toml" "$CONFIG_FILE"
validate_config_file "$CONFIG_FILE"
cmp "$CONFIG_FILE" "$TMP/legacy.original"
if validate_config_file "$TMP/unknown.toml" >/dev/null 2>&1; then
    echo 'An arbitrary unknown flag was silently ignored' >&2; exit 1
fi
payload=$(base64 "$TMP/quoted.toml" | tr -d '\r\n')
config_save_b64 "$payload" > "$TMP/save-result"
cmp "$CONFIG_FILE" "$TMP/quoted.toml"
backup=$(sed -n 's/^backup=//p' "$TMP/save-result")
cmp "$backup" "$TMP/legacy.original"
[[ -z $(find "$RUNDIR" -name 'config-validation.*' -print) ]]

# Inspect the exact launch argv without starting processes or touching routes.
workers_blocked() { return 1; }
core_running() { return 1; }
validate_runtime_config() { return 0; }
easytier_app_vpn_active() { return 1; }
ensure_tun_device() { :; }
log_tcp_compatibility() { :; }
get_hostname_arg() { echo synthetic-host; }
set_description() { :; }
framework_name() { echo synthetic-manager; }
sleep() { :; }
core_pid() { echo 4242; }
launch_detached() { printf '%s\n' "$@" > "$TMP/launched"; }
capture_start() { start_core_unlocked || return 1; wait; }
capture_start
python3 - "$TMP" <<'PY'
from pathlib import Path
import sys, tomllib
p = Path(sys.argv[1]); args = (p / 'launched').read_text().splitlines()
config = Path(args[args.index('-c') + 1])
assert config == p / 'module/run/core-config.toml'
assert tomllib.loads(config.read_text())['flags']['relay_network_whitelist'] == 'synthetic-*'
assert args[args.index('--rpc-portal') + 1] == '127.0.0.1:17888'
PY
cmp "$CONFIG_FILE" "$TMP/quoted.toml"
for rpc_args in '--rpc-portal 127.0.0.1:18888' '--rpc-portal=127.0.0.1:18888' \
    '-r 127.0.0.1:18888' '-r127.0.0.1:18888'; do
    printf '%s\n' "--network-name synthetic $rpc_args" > "$COMMAND_ARGS"
    cp "$COMMAND_ARGS" "$TMP/command.original"
    [[ $(get_rpc_portal) == 127.0.0.1:18888 ]]
    capture_start
    [[ $(grep -c '18888' "$TMP/launched") == 1 ]]
    [[ $(grep -c '17888' "$TMP/launched") == 0 ]]
    cmp "$COMMAND_ARGS" "$TMP/command.original"
done
printf '%s\n' '--network-name synthetic' > "$COMMAND_ARGS"
capture_start
grep -A 1 -- '^--rpc-portal$' "$TMP/launched" | grep -q '^127.0.0.1:17888$'
printf '%s\n' '--network-name synthetic --rpc-portal 0.0.0.0:18888' > "$COMMAND_ARGS"
[[ $(get_rpc_portal) == 127.0.0.1:18888 ]]
[[ $(get_rpc_portal listen) == 0.0.0.0:18888 ]]
capture_start
grep -q '^0.0.0.0:18888$' "$TMP/launched"
printf '%s\n' '--network-name synthetic --rpc-portal 18888' > "$COMMAND_ARGS"
[[ $(get_rpc_portal) == 127.0.0.1:18888 ]]
[[ $(get_rpc_portal listen) == 18888 ]]
capture_start
grep -A 1 -- '^--rpc-portal$' "$TMP/launched" | grep -q '^18888$'
rm "$COMMAND_ARGS"
sed 's/127.0.0.1:17888/0.0.0.0:17888/' "$TMP/quoted.toml" > "$CONFIG_FILE"
[[ $(get_rpc_portal) == 127.0.0.1:17888 ]]
capture_start
grep -A 1 -- '^--rpc-portal$' "$TMP/launched" | grep -q '^0.0.0.0:17888$'

# EasyTier 2.7 serializes route proxy_cidrs as comma-separated real->mapped
# strings. The old array representation and unmapped routes remain accepted.
cat > "$CLI" <<'CLI'
#!/bin/sh
cat "${0%/*}/routes.json"
CLI
chmod +x "$CLI"
cat > "$BINDIR/routes.json" <<'JSON'
[
  {"ipv4":"10.77.0.9/32","proxy_cidrs":"192.168.80.0/24->198.51.100.0/24,203.0.113.0/24"},
  {"proxy_cidrs":["172.16.0.0/16 -> 10.88.0.0/16","10.99.0.0/24"]},
  {"proxy_cidrs":"192.168.90.0/24->198.51.101.0/24,192.168.91.0/24->198.51.102.0/24"}
]
JSON
cat > "$TMP/routes.expected" <<'CIDRS'
10.77.0.9/32
198.51.100.0/24
203.0.113.0/24
10.88.0.0/16
10.99.0.0/24
198.51.101.0/24
198.51.102.0/24
CIDRS
cli_route_cidrs > "$TMP/routes.actual"
cmp "$TMP/routes.expected" "$TMP/routes.actual"
printf '[]\n' > "$BINDIR/routes.json"
if cli_route_cidrs > "$TMP/routes.actual"; then
    echo 'Empty routes unexpectedly reported a CIDR' >&2; exit 1
fi
[[ ! -s "$TMP/routes.actual" ]]
echo 'PASS: mapped proxy routes keep only exposed destinations and retain ordinary CIDRs'

if [[ -n ${TIERNEST_TEST_CORE:-} ]]; then
    CORE=$TIERNEST_TEST_CORE
    for fixture in legacy quoted dotted modern-first modern-last; do
        validate_config_file "$TMP/$fixture.toml"
    done
    if validate_config_file "$TMP/unknown.toml" > "$TMP/unknown-result" 2>&1; then
        echo 'Real core accepted unknown flag' >&2; exit 1
    fi
    echo 'PASS: real EasyTier core validates runtime aliases and rejects unknown flags'
fi
echo 'PASS: runtime-only aliases, byte-preserving saves/backups, RPC launch arguments and modern-field precedence'

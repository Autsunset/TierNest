#!/usr/bin/env python3
"""Stateful routing/cleanup tests. Every ip invocation is intercepted; no host routes change."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'android/app/src/main/assets/engine/engine-lib.sh'

MOCK_IP = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['MOCK_STATE'])
s = json.loads(p.read_text())
a = sys.argv[1:]
s['calls'].append(a.copy())
if a and a[0] == '-4': a.pop(0)
def done(code=0, output=''):
    p.write_text(json.dumps(s))
    if output: print(output)
    sys.exit(code)
def val(key): return a[a.index(key)+1]
if a[:2] == ['link', 'show']: done()
if '-o' in a and 'addr' in a: done(output='7: tiernest0 inet 10.77.0.2/24 scope global tiernest0')
if a[:2] == ['rule', 'show']:
    done(output='\n'.join(f"{r[0]}: from all lookup {r[1]}" for r in s['rules']))
if a[:2] == ['rule', 'add']:
    if os.environ.get('FAIL_RULE'): done(1)
    s['rules'].append([int(val('pref')), int(val('lookup'))]); done()
if a[:2] == ['rule', 'del']:
    rule=[int(val('pref')), int(val('lookup'))]
    if rule in s['rules']: s['rules'].remove(rule); done()
    done(2)
if a[:1] == ['route']:
    table=val('table')
    routes=s['routes'].setdefault(table, {})
    if a[1] == 'show':
        out=[]
        for cidr, spec in routes.items():
            if 'exact' in a and val('exact') != cidr: continue
            if 'proto' in a and val('proto') != spec['proto']: continue
            out.append(f"{cidr} dev {spec['dev']} proto {spec['proto']} scope link")
        done(output='\n'.join(out))
    cidr=a[a.index('table')+2]
    if a[1] == 'replace':
        if os.environ.get('FAIL_CIDR') == cidr: done(1)
        routes[cidr]={'dev':val('dev'),'proto':val('proto')}; done()
    if a[1] == 'del':
        if cidr in routes and routes[cidr] == {'dev':val('dev'),'proto':val('proto')}:
            del routes[cidr]; done()
        done(2)
done(5, 'Unexpected mock ip command: ' + repr(a))
'''

MOCK_IPTABLES = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p=Path(os.environ['MOCK_STATE']); s=json.loads(p.read_text())
a=sys.argv[1:]; a=a[2:] if a[:1] == ['-w'] else a
s['calls'].append(['iptables']+a)
chains=s.setdefault('chains', {}); hooks=s.setdefault('hooks', [])
def done(code=0):
    p.write_text(json.dumps(s)); sys.exit(code)
op, name=a[:2]
if os.environ.get('FAIL_RPC_RULE') and op == '-A': done(1)
if op == '-S': done(0 if name in chains else 1)
if op == '-N':
    if name in chains: done(1)
    chains[name]=[]; done()
if op == '-A': chains[name].append(a[2:]); done()
if op == '-I': hooks.append(a[3:]); done()
if op == '-C': done(0 if a[2:] in hooks else 1)
if op == '-D':
    if a[2:] not in hooks: done(1)
    hooks.remove(a[2:]); done()
if op == '-F': chains[name]=[]; done()
if op == '-X': del chains[name]; done()
done(5)
'''


class EngineTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for folder in ['bin', 'run', 'stage', 'backups']:
            (self.root / folder).mkdir()
        self.state_file = self.root / 'state.json'
        self.write_state({'rules': [[0, 255], [9980, 99]], 'routes': {'20110': {'203.0.113.0/24': {'dev': 'foreign0', 'proto': 'static'}}}, 'calls': []})
        ip = self.root / 'bin/ip'
        ip.write_text(MOCK_IP)
        ip.chmod(0o755)
        iptables = self.root / 'bin/iptables'
        iptables.write_text(MOCK_IPTABLES)
        iptables.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}", MOCK_STATE=str(self.state_file))
        (self.root / 'stage/routes.txt').write_text('10.77.0.0/24\n198.51.100.0/24\n')

    def tearDown(self): self.tmp.cleanup()
    def state(self): return json.loads(self.state_file.read_text())
    def write_state(self, state): self.state_file.write_text(json.dumps(state))

    def run_shell(self, script, *, alive=True, extra=None):
        setup = f"TN_ROOT='{self.root}'; TN_RUN='{self.root}/run'; TN_STAGE='{self.root}/stage'; TN_BACKUPS='{self.root}/backups'; . '{LIB}'\n"
        if alive: setup += 'core_alive() { return 0; }\n'
        result = subprocess.run(['sh', '-c', setup + script], env=dict(self.env, **(extra or {})), capture_output=True, text=True, timeout=15)
        return result

    def test_collision_and_exact_cleanup(self):
        result = self.run_shell('sync_routes && cleanup_routes')
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.state()
        self.assertEqual(state['rules'], [[0, 255], [9980, 99]])
        self.assertEqual(state['routes']['20111'], {})
        self.assertIn('203.0.113.0/24', state['routes']['20110'])
        self.assertFalse(any('flush' in c for c in state['calls']))
        self.assertIn(['-4', 'rule', 'add', 'pref', '9979', 'lookup', '20111'], state['calls'])

    def test_partial_failure_rolls_back_only_our_changes(self):
        result = self.run_shell('sync_routes', extra={'FAIL_CIDR': '198.51.100.0/24'})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state()['routes']['20111'], {})
        self.assertIn('203.0.113.0/24', self.state()['routes']['20110'])
        self.assertFalse((self.root / 'run/lease').exists())

    def test_rule_failure_rolls_back_routes(self):
        self.assertNotEqual(self.run_shell('sync_routes', extra={'FAIL_RULE': '1'}).returncode, 0)
        self.assertEqual(self.state()['routes']['20111'], {})

    def test_stale_routes_withdrawn(self):
        self.assertEqual(self.run_shell('sync_routes').returncode, 0)
        (self.root / 'stage/routes.txt').write_text('10.77.0.0/24\n')
        self.assertEqual(self.run_shell('sync_routes').returncode, 0)
        self.assertNotIn('198.51.100.0/24', self.state()['routes']['20111'])

    def test_dangerous_destinations_rejected_before_mutation(self):
        for cidr in ['0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1', '127.0.0.1/32', '224.0.0.0/4', '10.1.2.999/24', '::/0', '10.1.0.0/24;id']:
            (self.root / 'stage/routes.txt').write_text(cidr + '\n')
            self.assertNotEqual(self.run_shell('sync_routes').returncode, 0, cidr)
        self.assertFalse(any('add' in c or 'replace' in c for c in self.state()['calls']))

    def test_cleanup_preserves_replaced_rule_and_route(self):
        self.assertEqual(self.run_shell('sync_routes').returncode, 0)
        state = self.state()
        state['rules'][-1] = [9979, 77]
        state['routes']['20111']['198.51.100.0/24'] = {'dev': 'foreign0', 'proto': 'static'}
        self.write_state(state)
        self.assertEqual(self.run_shell('cleanup_routes').returncode, 0)
        self.assertIn([9979, 77], self.state()['rules'])
        self.assertEqual(self.state()['routes']['20111']['198.51.100.0/24']['dev'], 'foreign0')

    def test_backup_bytes_and_unique_names(self):
        content = b'# synthetic\r\nnetwork_secret = "synthetic-test"\r\n'
        (self.root / 'stage/backup.toml').write_bytes(content)
        a = self.run_shell('backup_file')
        b = self.run_shell('backup_file')
        self.assertEqual(a.returncode, 0, a.stderr)
        self.assertEqual(b.returncode, 0, b.stderr)
        self.assertNotEqual(a.stdout.strip(), b.stdout.strip())
        self.assertEqual(Path(a.stdout.strip()).read_bytes(), content)
        self.assertEqual(Path(b.stdout.strip()).read_bytes(), content)

    def test_foreign_default_route_withdraws_our_lookup(self):
        self.assertEqual(self.run_shell('sync_routes').returncode, 0)
        state = self.state()
        state['routes']['20111']['default'] = {'dev': 'foreign0', 'proto': 'static'}
        self.write_state(state)
        self.assertNotEqual(self.run_shell('sync_routes').returncode, 0)
        self.assertNotIn([9979, 20111], self.state()['rules'])
        self.assertIn('default', self.state()['routes']['20111'])

    def test_backup_failure_does_not_change_original(self):
        (self.root / 'stage/backup.toml').write_text('synthetic-original')
        result = self.run_shell('TN_BACKUPS=/dev/null/unwritable; backup_file')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.root / 'stage/backup.toml').read_text(), 'synthetic-original')

    def test_pid_reuse_never_kills_unrelated_process(self):
        process = subprocess.Popen(['sleep', '30'])
        try:
            (self.root / 'run/core.pid').write_text(f'{process.pid} 0\n')
            self.assertEqual(self.run_shell('stop_core', alive=False).returncode, 0)
            self.assertIsNone(process.poll())
        finally: process.terminate(); process.wait()

    def test_snapshot_comparison_rejects_symlinks_and_missing_files(self):
        a = self.root / 'a'; b = self.root / 'b'
        a.mkdir(); b.mkdir()
        (a / 'config').write_text('synthetic')
        (b / 'config').write_text('synthetic')
        self.assertEqual(self.run_shell(f"tree_equal '{a}' '{b}'").returncode, 0)
        (b / 'config').unlink()
        (b / 'config').symlink_to(a / 'config')
        self.assertNotEqual(self.run_shell(f"tree_equal '{a}' '{b}'").returncode, 0)

    def test_rpc_only_allows_root_and_cleanup_is_scoped(self):
        self.assertEqual(self.run_shell('protect_rpc').returncode, 0)
        state = self.state()
        self.assertEqual(state['chains']['TNAPP_RPC'], [['-m', 'owner', '--uid-owner', '0', '-j', 'RETURN'], ['-j', 'REJECT']])
        self.assertEqual(state['hooks'], [['-o', 'lo', '-p', 'tcp', '-d', '127.0.0.1/32', '--dport', '15888', '-j', 'TNAPP_RPC']])
        self.assertEqual(self.run_shell('cleanup_rpc').returncode, 0)
        self.assertEqual(self.state()['chains'], {})
        self.assertEqual(self.state()['hooks'], [])
        self.assertFalse(any(c[:3] == ['iptables', '-F', 'OUTPUT'] for c in self.state()['calls']))

    def test_rpc_chain_collision_never_flushes_foreign_chain(self):
        state = self.state(); state['chains'] = {'TNAPP_RPC': [['foreign-rule']]}; self.write_state(state)
        self.assertNotEqual(self.run_shell('protect_rpc').returncode, 0)
        self.assertEqual(self.run_shell('cleanup_rpc').returncode, 0)
        self.assertEqual(self.state()['chains']['TNAPP_RPC'], [['foreign-rule']])

    def test_partial_rpc_setup_can_be_cleaned(self):
        self.assertNotEqual(self.run_shell('protect_rpc', extra={'FAIL_RPC_RULE': '1'}).returncode, 0)
        self.assertEqual(self.run_shell('cleanup_rpc').returncode, 0)
        self.assertEqual(self.state()['chains'], {})

if __name__ == '__main__': unittest.main(verbosity=2)

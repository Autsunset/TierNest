#!/usr/bin/env python3
"""Stateful hotspot forwarding tests. Every ip/iptables/dumpsys invocation is
intercepted; the host network is never touched."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'android/app/src/main/assets/engine/engine-lib.sh'
HOTSPOT = ROOT / 'android/app/src/main/assets/engine/hotspot-lib.sh'

MOCK_IP = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['MOCK_STATE'])
s = json.loads(p.read_text())
a = sys.argv[1:]
if a and a[0] == '-4': a.pop(0)
s['calls'].append(a.copy())
def done(code=0, output=''):
    p.write_text(json.dumps(s))
    if output: print(output)
    sys.exit(code)
def val(key): return a[a.index(key)+1]
if a[:2] == ['link', 'show']:
    iface = val('dev')
    if iface in s['links'] and s['links'][iface]:
        done(output=f"31: {iface}: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP")
    done(output=f"31: {iface}: <BROADCAST,MULTICAST> mtu 1500 state DOWN")
if '-o' in a and 'addr' in a:
    iface = val('dev')
    done(output=f"31: {iface} inet {s['addrs'][iface]} scope global {iface}")
if a[:2] == ['rule', 'show']:
    done(output='\n'.join(s['rules']))
def rule_text(args):
    parts = [f"{val('pref')}: from all"]
    if 'to' in a: parts.append(f"to {val('to')}")
    if 'iif' in a: parts.append(f"iif {val('iif')}")
    parts.append(f"lookup {val('lookup')}")
    return ' '.join(parts)
if a[:2] == ['rule', 'add']:
    if os.environ.get('FAIL_RULE_ADD'): done(1)
    s['rules'].append(rule_text(a)); done()
if a[:2] == ['rule', 'del']:
    if 'iif' in a and 'to' in a and 'lookup' in a:
        text = rule_text(a)
        if text in s['rules']: s['rules'].remove(text); done()
        done(2)
    pref = val('pref')
    for text in s['rules']:
        if text.startswith(f"{pref}:"): s['rules'].remove(text); done()
    done(2)
if a[:2] == ['route', 'show']:
    if 'default' in a: done(output='\n'.join(s['default_routes']))
    table = val('table'); routes = s['routes'].get(table, {})
    out = []
    for cidr, spec in routes.items():
        if 'exact' in a and val('exact') != cidr: continue
        if 'proto' in a and str(spec.get('proto')) != val('proto'): continue
        line = f"{cidr} dev {spec['dev']} proto {spec.get('proto')}"
        if spec.get('src'): line += f" src {spec['src']}"
        out.append(line)
    done(output='\n'.join(out))
if a[:1] == ['route']:
    table = val('table')
    cidr = a[a.index('table')+2]
    if a[1] in ('add', 'replace'):
        if a[1] == 'add' and os.environ.get('FAIL_ROUTE_ADD'): done(1)
        routes = s['routes'].setdefault(table, {})
        routes[cidr] = {'dev': val('dev'), 'proto': val('proto'), 'src': val('src') if 'src' in a else None}
        done()
    if a[1] == 'del':
        routes = s['routes'].get(table, {})
        if cidr in routes and routes[cidr]['dev'] == val('dev') and str(routes[cidr]['proto']) == val('proto'):
            del routes[cidr]
            if not routes: del s['routes'][table]
            done()
        done(2)
done(5, 'Unexpected mock ip command: ' + repr(a))
'''

MOCK_IPTABLES = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['MOCK_STATE']); s = json.loads(p.read_text())
a = sys.argv[1:]
if a[:1] == ['-w']: a = a[2:]
table = 'filter'
if a[:1] == ['-t']: table = a[1]; a = a[2:]
s['calls'].append(['iptables', '-t', table] + a.copy())
chains = s.setdefault('chains', {}).setdefault(table, {})
def done(code=0):
    p.write_text(json.dumps(s)); sys.exit(code)
op, name = a[0], a[1]
args = a[2:]
if op == '-I' and args and args[0] == '1': args = args[1:]
joined = ' '.join(args)
BUILTINS = ('FORWARD', 'POSTROUTING', 'PREROUTING', 'INPUT', 'OUTPUT')
if op == '-S':
    if name not in chains: done(1)
    lines = [(f"-P {name} ACCEPT" if name in BUILTINS else f"-N {name}")]
    lines += [f"-A {name} " + ' '.join(rule) for rule in chains[name]]
    print('\n'.join(lines)); done()
if op == '-N':
    if name in chains: done(1)
    chains[name] = []; done()
if op in ('-A', '-I'):
    if os.environ.get('FAIL_IPT_APPEND') and os.environ['FAIL_IPT_APPEND'] in joined: done(1)
    chains.setdefault(name, []).append(args); done()
if op == '-C': done(0 if args in chains.get(name, []) else 1)
if op == '-D':
    if os.environ.get('FAIL_IPT_DELETE'): done(1)
    if name in chains and args in chains[name]:
        chains[name].remove(args); done()
    done(1)
if op == '-F': chains[name] = []; done()
if op == '-X':
    if name not in chains or chains[name]: done(1)
    for tbl in s['chains'].values():
        for rules in tbl.values():
            if any(r[-2:] == ['-j', name] for r in rules): done(1)
    del chains[name]; done()
done(5)
'''

MOCK_DUMPSYS = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
s = json.loads(Path(os.environ['MOCK_STATE']).read_text())
sys.stdout.write(s.get('dumpsys', ''))
'''

LIVE_DUMP = 'Tether state:\nap0 - TetheredState - lastError = 0\nUpstream wanted: true\n'


class HotspotTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        for folder in ['bin', 'run', 'stage', 'backups']:
            (self.root / folder).mkdir()
        self.state_file = self.root / 'state.json'
        self.write_state(self.base_state())
        for name, mock in [('ip', MOCK_IP), ('iptables', MOCK_IPTABLES), ('dumpsys', MOCK_DUMPSYS)]:
            binary = self.root / 'bin' / name
            binary.write_text(mock)
            binary.chmod(0o755)
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}", MOCK_STATE=str(self.state_file))
        self.query('on')
        (self.root / 'stage/hotspot-proxies').write_text('203.0.113.0/24\n')
        (self.root / 'run/lease').write_text('20110 9980\n')
        (self.root / 'run/routes').write_text('10.77.0.0/24\n198.51.100.0/24\n')

    def tearDown(self): self.tmp.cleanup()
    def state(self): return json.loads(self.state_file.read_text())
    def write_state(self, state): self.state_file.write_text(json.dumps(state))
    def query(self, value): (self.root / 'stage/hotspot-query').write_text(value + '\n')

    def base_state(self):
        return {'links': {'ap0': True},
                'addrs': {'ap0': '192.168.77.1/24', 'tiernest0': '10.77.0.2/24'},
                'default_routes': ['default via 192.0.2.1 dev wlan0'],
                'dumpsys': LIVE_DUMP,
                'rules': [],
                'routes': {'20110': {'10.77.0.0/24': {'dev': 'tiernest0', 'proto': '186'},
                                     '198.51.100.0/24': {'dev': 'tiernest0', 'proto': '186'}}},
                'chains': {'filter': {'FORWARD': []}, 'nat': {'POSTROUTING': []}}, 'calls': []}

    def run_shell(self, script, *, alive=True, forward=True, extra=None):
        setup = (f"TN_ROOT='{self.root}'; TN_RUN='{self.root}/run'; TN_STAGE='{self.root}/stage'; "
                 f"TN_BACKUPS='{self.root}/backups'; . '{LIB}'; . '{HOTSPOT}'\n"
                 f"core_alive() {{ return {0 if alive else 1}; }}\n"
                 f"hs_forward_ready() {{ return {0 if forward else 1}; }}\n")
        return subprocess.run(['sh', '-c', setup + script], env=dict(self.env, **(extra or {})),
                              capture_output=True, text=True, timeout=15)

    def enable(self, **kwargs):
        return self.run_shell('sync_hotspot', **kwargs)

    def assert_baseline_chains(self, chains):
        # Real iptables keeps builtin chains forever; custom chains need -X.
        self.assertEqual(chains, {'filter': {'FORWARD': []}, 'nat': {'POSTROUTING': []}})

    def assert_active(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('hotspot_state=active', result.stdout)

    def test_off_touches_nothing(self):
        self.query('off')
        result = self.enable()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('hotspot_state=disabled', result.stdout)
        self.assertEqual(self.state()['calls'], [])
        self.assertEqual(self.state()['routes'].keys(), {'20110'})

    def test_on_rules_targets_and_precise_return(self):
        self.assert_active(self.enable())
        state = self.state()
        self.assertEqual(state['chains']['nat']['TNAPP_HSN'], [
            ['-s', '192.168.77.0/24', '-d', '10.77.0.0/24', '-o', 'tiernest0', '-j', 'MASQUERADE'],
            ['-s', '192.168.77.0/24', '-d', '198.51.100.0/24', '-o', 'tiernest0', '-j', 'MASQUERADE']])
        rules = state['chains']['filter']['TNAPP_HSF']
        self.assertIn(['-i', 'ap0', '-o', 'tiernest0', '-s', '192.168.77.0/24', '-d', '10.77.0.0/24', '-j', 'ACCEPT'], rules)
        self.assertIn(['-i', 'ap0', '-o', 'tiernest0', '-s', '192.168.77.0/24', '-d', '198.51.100.0/24', '-j', 'ACCEPT'], rules)
        self.assertIn(['-i', 'tiernest0', '-o', 'ap0', '-d', '192.168.77.0/24', '-m', 'conntrack',
                       '--ctstate', 'ESTABLISHED,RELATED', '-j', 'ACCEPT'], rules)
        self.assertIn(['-i', 'tiernest0', '-o', 'ap0', '-j', 'DROP'], rules)
        self.assertIn(['-i', 'ap0', '-o', 'tiernest0', '-j', 'DROP'], rules)
        self.assertIn(['-s', '192.168.77.0/24', '-o', 'tiernest0', '-j', 'TNAPP_HSN'],
                      state['chains']['nat']['POSTROUTING'])
        self.assertIn(['-i', 'ap0', '-o', 'tiernest0', '-j', 'TNAPP_HSF'], state['chains']['filter']['FORWARD'])
        self.assertIn(['-i', 'tiernest0', '-o', 'ap0', '-j', 'TNAPP_HSF'], state['chains']['filter']['FORWARD'])
        for rule in state['chains']['nat']['TNAPP_HSN']:
            self.assertNotIn('0.0.0.0/0', rule)
        # The return path uses its own table with a precise iif-scoped rule, not
        # the overlay lease rule (table 20110 / pref 9980).
        self.assertIn('9890: from all to 192.168.77.0/24 iif tiernest0 lookup 20130', state['rules'])
        self.assertEqual(state['routes']['20130']['192.168.77.0/24']['dev'], 'ap0')
        self.assertEqual(state['routes']['20130']['192.168.77.0/24']['proto'], '186')
        self.assertIn('hotspot_cidr=192.168.77.0/24', self.run_shell('cat "$TN_RUN/hotspot.status"').stdout)

    def test_repeat_sync_is_idempotent(self):
        self.assert_active(self.enable())
        before = len(self.state()['calls'])
        self.assert_active(self.enable())
        for call in self.state()['calls'][before:]:
            self.assertNotEqual(call[:2], ['route', 'add'], call)
            self.assertNotEqual(call[:2], ['rule', 'add'], call)
            if call[0] == 'iptables':
                self.assertNotIn(call[3], ('-A', '-I', '-N'), call)
        self.assertEqual(len(self.state()['chains']['nat']['TNAPP_HSN']), 2)

    def test_off_cleans_all_state(self):
        self.assert_active(self.enable())
        self.query('off')
        result = self.enable()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('hotspot_state=disabled', result.stdout)
        state = self.state()
        self.assertEqual(state['rules'], [])
        self.assertEqual(state['routes'].keys(), {'20110'})
        self.assert_baseline_chains(state['chains'])
        for name in ['hotspot.rules', 'hotspot.return', 'hotspot.chains', 'hotspot.applied']:
            self.assertFalse((self.root / 'run' / name).exists(), name)

    def test_fresh_process_cleans_from_journal(self):
        self.assert_active(self.enable())
        result = self.run_shell('cleanup_hotspot')
        self.assertEqual(result.returncode, 0, result.stderr)
        state = self.state()
        self.assertEqual(state['rules'], [])
        self.assertEqual(state['routes'].keys(), {'20110'})
        self.assert_baseline_chains(state['chains'])
        for name in ['hotspot.rules', 'hotspot.return', 'hotspot.chains', 'hotspot.applied']:
            self.assertFalse((self.root / 'run' / name).exists(), name)

    def test_hotspot_disappeared_waits(self):
        self.assert_active(self.enable())
        # A valid tether section with no live client entry waits for the hotspot.
        state = self.base_state()
        state['dumpsys'] = 'Tether state:\nUpstream wanted: false\n'
        self.write_state(state)
        result = self.enable()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('hotspot_state=waiting_hotspot', result.stdout)
        self.assertEqual(self.state()['rules'], [])
        self.assert_baseline_chains(self.state()['chains'])
        self.assertNotIn('20130', self.state()['routes'])
        # A missing tether dump entirely is reported as unavailable, not active.
        state['dumpsys'] = ''; self.write_state(state)
        self.assertIn('hotspot_state=unavailable', self.enable().stdout)
        self.assert_baseline_chains(self.state()['chains'])

    def test_subnet_change_reapplies(self):
        self.assert_active(self.enable())
        state = self.base_state(); state['addrs']['ap0'] = '192.168.78.1/24'; self.write_state(state)
        self.assert_active(self.enable())
        state = self.state()
        self.assertIn('9890: from all to 192.168.78.0/24 iif tiernest0 lookup 20130', state['rules'])
        self.assertNotIn('9890: from all to 192.168.77.0/24 iif tiernest0 lookup 20130', state['rules'])
        self.assertEqual(state['routes']['20130'].keys(), {'192.168.78.0/24'})
        self.assertIn(['-s', '192.168.78.0/24', '-d', '10.77.0.0/24', '-o', 'tiernest0', '-j', 'MASQUERADE'],
                      state['chains']['nat']['TNAPP_HSN'])

    def test_uplink_wlan_never_selected(self):
        state = self.base_state()
        state['dumpsys'] = 'Tether state:\nwlan0 - TetheredState - lastError = 0\nUpstream wanted: true\n'
        state['addrs']['wlan0'] = '192.0.2.2/24'
        self.write_state(state)
        self.assertEqual(self.run_shell('hs_detect').stdout, '')
        result = self.enable()
        self.assertIn('hotspot_state=waiting_hotspot', result.stdout)
        self.assertEqual(self.state()['rules'], [])
        # A tethered ap0 next to the uplink wlan0 still selects only ap0.
        state['dumpsys'] = ('Tether state:\nap0 - TetheredState - lastError = 0\n'
                            'wlan0 - TetheredState - lastError = 0\nUpstream wanted: true\n')
        self.write_state(state)
        self.assertEqual(self.run_shell('hs_detect').stdout.strip(), 'ap0 192.168.77.0/24 192.168.77.1')

    def test_proxy_overlap_conflict(self):
        state = self.base_state(); state['dumpsys'] = LIVE_DUMP; self.write_state(state)
        (self.root / 'stage/hotspot-proxies').write_text('192.168.77.0/24\n')
        result = self.enable()
        self.assertIn('hotspot_state=conflict', result.stdout)
        self.assertEqual(self.state()['rules'], [])
        self.assert_baseline_chains(self.state()['chains'])
        (self.root / 'stage/hotspot-proxies').write_text('192.168.0.0/16\n')
        self.assertIn('hotspot_state=conflict', self.enable().stdout)
        self.assert_baseline_chains(self.state()['chains'])
        # A missing proxy inventory is treated as a conflict, never as "no proxies".
        (self.root / 'stage/hotspot-proxies').unlink()
        self.assertIn('hotspot_state=conflict', self.enable().stdout)
        self.assert_baseline_chains(self.state()['chains'])

    def test_overlay_overlap_conflict(self):
        (self.root / 'run/routes').write_text('10.77.0.0/24\n192.168.77.0/24\n')
        state = self.base_state()
        state['routes']['20110']['192.168.77.0/24'] = {'dev': 'tiernest0', 'proto': '186'}
        self.write_state(state)
        result = self.enable()
        self.assertIn('hotspot_state=conflict', result.stdout)
        self.assertEqual(self.state()['rules'], [])
        self.assert_baseline_chains(self.state()['chains'])

    def test_foreign_chains_never_deleted(self):
        state = self.base_state()
        state['chains']['filter']['TNAPP_HSF'] = [['foreign-rule']]
        state['chains']['nat']['TNAPP_HSN'] = [['other-foreign']]
        self.write_state(state)
        result = self.enable()
        self.assertIn('hotspot_state=error', result.stdout)
        final = self.state()
        self.assertEqual(final['chains']['filter']['TNAPP_HSF'], [['foreign-rule']])
        self.assertEqual(final['chains']['nat']['TNAPP_HSN'], [['other-foreign']])
        self.assertEqual(final['chains']['filter']['FORWARD'], [])
        self.assertEqual(final['chains']['nat']['POSTROUTING'], [])
        self.assertEqual(final['rules'], [])
        self.assertFalse(any(c[0] == 'iptables' and '-F' in c for c in final['calls']))

    def test_install_failure_rolls_back(self):
        result = self.enable(extra={'FAIL_ROUTE_ADD': '1'})
        self.assertIn('hotspot_state=error', result.stdout)
        state = self.state()
        self.assertEqual(state['rules'], [])
        self.assertNotIn('20130', state['routes'])
        self.assert_baseline_chains(state['chains'])
        result = self.enable(extra={'FAIL_IPT_APPEND': 'MASQUERADE'})
        self.assertIn('hotspot_state=error', result.stdout)
        state = self.state()
        self.assertEqual(state['rules'], [])
        self.assertNotIn('20130', state['routes'])
        self.assert_baseline_chains(state['chains'])
        for name in ['hotspot.rules', 'hotspot.return', 'hotspot.chains', 'hotspot.applied']:
            self.assertFalse((self.root / 'run' / name).exists(), name)

    def test_delete_failure_keeps_journal(self):
        self.assert_active(self.enable())
        self.query('off')
        result = self.enable(extra={'FAIL_IPT_DELETE': '1'})
        self.assertEqual(result.returncode, 1)
        for name in ['hotspot.rules', 'hotspot.return', 'hotspot.chains']:
            self.assertTrue((self.root / 'run' / name).exists(), name)
        self.assertIn('hotspot_state=error', (self.root / 'run/hotspot.status').read_text())

    def test_foreign_routes_and_rules_preserved(self):
        state = self.base_state()
        state['routes']['20130'] = {'203.0.113.0/24': {'dev': 'foreign0', 'proto': 'static'}}
        state['rules'] = ['9890: from all iif wlan0 lookup 5000']
        self.write_state(state)
        self.assert_active(self.enable())
        state = self.state()
        # Allocation avoided the occupied table and preference, and kept them.
        self.assertIn('9889: from all to 192.168.77.0/24 iif tiernest0 lookup 20131', state['rules'])
        self.assertIn('9890: from all iif wlan0 lookup 5000', state['rules'])
        self.assertEqual(state['routes']['20130']['203.0.113.0/24']['dev'], 'foreign0')
        self.assertEqual(state['routes']['20131']['192.168.77.0/24']['dev'], 'ap0')
        self.query('off')
        self.assertEqual(self.enable().returncode, 0)
        final = self.state()
        self.assertIn('9890: from all iif wlan0 lookup 5000', final['rules'])
        self.assertEqual(final['routes']['20130']['203.0.113.0/24']['dev'], 'foreign0')
        self.assertNotIn('20131', final['routes'])

    def test_cleanup_preserves_replacements_and_foreign_rules_added_later(self):
        self.assert_active(self.enable())
        state = self.state()
        state['routes']['20130']['192.168.77.0/24'] = {'dev': 'foreign0', 'proto': 'static'}
        state['rules'] = ['9890: from all to 192.168.77.0/24 iif tiernest0 lookup 5000']
        state['chains']['filter']['TNAPP_HSF'].append(['-j', 'RETURN'])
        self.write_state(state)
        result = self.run_shell('cleanup_hotspot')
        self.assertNotEqual(result.returncode, 0)
        final = self.state()
        self.assertEqual(final['routes']['20130']['192.168.77.0/24']['dev'], 'foreign0')
        self.assertEqual(final['rules'], state['rules'])
        self.assertEqual(final['chains']['filter']['TNAPP_HSF'], [['-j', 'RETURN']])
        self.assertEqual(final['chains']['filter']['FORWARD'], [])
        self.assertTrue((self.root / 'run/hotspot.rules').exists())
        self.assertIn('hotspot_state=error', (self.root / 'run/hotspot.status').read_text())

    def test_old_module_hotspot_rules_are_refused_without_taking_ownership(self):
        state = self.base_state()
        state['chains']['filter']['TN_HS_OUT_FWD'] = [['-j', 'RETURN']]
        self.write_state(state)
        result = self.run_shell('check_modules')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state()['chains'], state['chains'])
        self.assertIn('old module', result.stderr)

    def test_malformed_query_never_runs_shell_or_changes_rules(self):
        for query in ['on extra', 'on;id', 'unknown']:
            self.query(query)
            self.assertNotEqual(self.enable().returncode, 0)
            self.assertEqual(self.state()['calls'], [])

    def test_too_many_targets_rejected(self):
        targets = [f'198.51.100.{i}/32' for i in range(1, 130)]
        (self.root / 'run/routes').write_text('\n'.join(['10.77.0.0/24'] + targets) + '\n')
        state = self.base_state()
        for target in targets:
            state['routes']['20110'][target] = {'dev': 'tiernest0', 'proto': '186'}
        self.write_state(state)
        result = self.enable()
        self.assertIn('hotspot_state=too_many_routes', result.stdout)
        self.assertEqual(self.state()['rules'], [])
        self.assertNotIn('20130', self.state()['routes'])
        self.assert_baseline_chains(self.state()['chains'])

    def test_dump_history_and_error_ifaces_ignored(self):
        state = self.base_state()
        state['addrs']['ap1'] = '192.168.79.1/24'
        state['addrs']['wlan1'] = '192.168.80.1/24'
        state['dumpsys'] = ('Tether state:\n'
                            'ap0 - TetheredState - lastError = 0\n'
                            'ap1 - TetheredState - lastError = 3\n'
                            'Upstream wanted: true\n'
                            'Hardware offload: disabled\n'
                            '\n'
                            'Log:\n'
                            '08-01 12:00:00 wlan1 - TetheredState - lastError = 0\n')
        self.write_state(state)
        self.assertEqual(self.run_shell('hs_detect').stdout.strip(), 'ap0 192.168.77.0/24 192.168.77.1')

    def test_cleanup_never_pref_only_never_flush_never_sysctl(self):
        self.assert_active(self.enable())
        self.query('off')
        self.assertEqual(self.enable().returncode, 0)
        for call in self.state()['calls']:
            if call[:3] == ['rule', 'del', 'pref']:
                self.assertTrue(('iif' in call and 'to' in call and 'lookup' in call), call)
            if call[0] == 'iptables':
                self.assertNotIn('-F', call, call)
            self.assertNotIn('sysctl', call)
            self.assertNotIn('/proc/sys', call)
            if call[:3] == ['route', 'del', 'table']:
                self.assertIn('proto', call)
                self.assertIn('dev', call)


if __name__ == '__main__': unittest.main(verbosity=2)

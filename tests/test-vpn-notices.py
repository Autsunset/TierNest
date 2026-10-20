#!/usr/bin/env python3
"""Check Android-only notice collection and stale generated-file cleanup."""
import contextlib
import io
import json
from pathlib import Path
import runpy
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class VpnNoticesTest(unittest.TestCase):
    def test_both_android_targets_are_merged_offline_without_stale_notices(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script = root / 'scripts/prepare-vpn-notices.py'
            script.parent.mkdir()
            shutil.copy2(ROOT / 'scripts/prepare-vpn-notices.py', script)
            output = root / 'android/app/build/generated/vpnNotices/licenses/rust'
            output.mkdir(parents=True)
            (output / 'removed-package.txt').write_text('obsolete')
            packages = {}
            for name in ('shared', 'arm-only', 'x86-only'):
                source = root / 'sources' / name
                source.mkdir(parents=True)
                (source / 'LICENSE').write_text('Synthetic license: ' + name)
                packages[name] = dict(id=name, name=name, version='1.0.0', license='MIT',
                    manifest_path=str(source / 'Cargo.toml'), source='registry+synthetic',
                    repository='https://example.invalid/synthetic')
            targets = []

            def metadata(command, **kwargs):
                self.assertIn('--locked', command)
                self.assertIn('--offline', command)
                target = command[command.index('--filter-platform') + 1]
                targets.append(target)
                unique = {'aarch64-linux-android': 'arm-only', 'x86_64-linux-android': 'x86-only'}[target]
                return json.dumps({'packages': [packages['shared'], packages[unique]]}).encode()

            with patch('subprocess.check_output', side_effect=metadata), contextlib.redirect_stdout(io.StringIO()):
                runpy.run_path(str(script), run_name='__main__')
            self.assertEqual(['aarch64-linux-android', 'x86_64-linux-android'], targets)
            self.assertFalse((output / 'removed-package.txt').exists())
            notices = json.loads((output / 'dependencies.json').read_text())
            self.assertEqual(['arm-only', 'shared', 'x86-only'], [p['name'] for p in notices])
            self.assertNotIn(directory, json.dumps(notices))
            for notice in notices:
                self.assertEqual(1, len(notice['license_files']))
                self.assertEqual('Synthetic license: ' + notice['name'],
                                 (output / notice['license_files'][0]).read_text())


if __name__ == '__main__':
    unittest.main()

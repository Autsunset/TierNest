#!/usr/bin/env python3
"""Exercise the real upstream installer with small, offline release fixtures."""
import hashlib
import os
from pathlib import Path
import re
import shlex
import shutil
import stat
import subprocess
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PAYLOADS = {
    'easytier-core': b'synthetic EasyTier 2.7.0 core\n',
    'easytier-cli': b'synthetic EasyTier 2.7.0 cli\n',
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


class UpstreamReleaseTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix='tiernest upstream test ')
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for directory in ['scripts', 'module/bin', '.cache', 'mockbin']:
            (self.root / directory).mkdir(parents=True)
        shutil.copy2(ROOT / 'scripts/fetch-upstream.sh', self.root / 'scripts/fetch-upstream.sh')
        self.env = os.environ.copy()
        self.env.pop('EASYTIER_VERSION', None)
        self.env['PATH'] = str(self.root / 'mockbin') + os.pathsep + self.env['PATH']
        self.stub('curl', '#!/bin/sh\necho "Unexpected network download in offline test" >&2\nexit 97\n')
        self.archive = self.root / '.cache/Easytier-Magisk-v2.7.0.zip'
        for name in PAYLOADS:
            target = self.root / 'module/bin' / name
            target.write_bytes(b'previous working payload: ' + name.encode())
            target.chmod(0o755)
            os.utime(target, ns=(1_600_000_000_000_000_000,) * 2)
        self.before = self.snapshot()
        self.release()

    def stub(self, name, source):
        target = self.root / 'mockbin' / name
        target.write_text(source)
        target.chmod(0o755)

    def release(self, payloads=None):
        with zipfile.ZipFile(self.archive, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in (PAYLOADS if payloads is None else payloads).items():
                archive.writestr(name, data)
        (self.root / 'scripts/easytier-release.conf').write_text(
            'EASYTIER_VERSION=2.7.0\n'
            f'EASYTIER_REVISION={"a" * 40}\n'
            f'EASYTIER_ARCHIVE_SHA256={sha256(self.archive.read_bytes())}\n'
            f'EASYTIER_CORE_SHA256={sha256(PAYLOADS["easytier-core"])}\n'
            f'EASYTIER_CLI_SHA256={sha256(PAYLOADS["easytier-cli"])}\n'
        )

    def run_fetch(self, **environment):
        return subprocess.run(
            ['bash', str(self.root / 'scripts/fetch-upstream.sh')],
            cwd=self.root, env={**self.env, **environment},
            capture_output=True, text=True, timeout=20,
        )

    def snapshot(self):
        return {
            name: (target.read_bytes(), target.stat().st_mtime_ns, stat.S_IMODE(target.stat().st_mode))
            for name in PAYLOADS
            for target in [self.root / 'module/bin' / name]
        }

    def assert_preserved(self, result):
        self.assertNotEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual(self.before, self.snapshot(), 'Failed installs must preserve both working binaries')
        self.assertEqual([], list((self.root / 'module/bin').glob('.upstream.*')))

    def test_verified_release_replaces_stale_cached_binaries(self):
        result = self.run_fetch()
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        for name, data in PAYLOADS.items():
            target = self.root / 'module/bin' / name
            self.assertEqual(data, target.read_bytes())
            if os.name == 'posix':
                self.assertEqual(0o755, stat.S_IMODE(target.stat().st_mode))
        self.assertEqual([], list((self.root / 'module/bin').glob('.upstream.*')))

    def test_repeated_identical_release_preserves_binary_mtime(self):
        first = self.run_fetch()
        self.assertEqual(0, first.returncode, first.stdout + first.stderr)
        for name in PAYLOADS:
            os.utime(self.root / 'module/bin' / name, ns=(1_600_000_001_000_000_000,) * 2)
        installed = self.snapshot()
        second = self.run_fetch(EASYTIER_VERSION='2.7.0')
        self.assertEqual(0, second.returncode, second.stdout + second.stderr)
        self.assertEqual(installed, self.snapshot())

    def test_archive_checksum_mismatch_preserves_installed_pair(self):
        self.archive.write_bytes(self.archive.read_bytes() + b'changed archive')
        result = self.run_fetch()
        self.assert_preserved(result)
        self.assertIn('Checksum mismatch', result.stderr)

    def test_payload_checksum_mismatch_preserves_installed_pair(self):
        for name in PAYLOADS:
            with self.subTest(payload=name):
                self.release({**PAYLOADS, name: b'wrong release payload'})
                self.assert_preserved(self.run_fetch())

    def test_missing_second_payload_preserves_installed_pair(self):
        self.release({'easytier-core': PAYLOADS['easytier-core']})
        self.assert_preserved(self.run_fetch())

    def test_partial_second_extraction_preserves_installed_pair(self):
        unzip = shutil.which('unzip')
        self.assertIsNotNone(unzip)
        self.stub('unzip',
            '#!/bin/sh\n'
            'if [ "$3" = easytier-cli ]; then printf "partial cli"; exit 23; fi\n'
            f'exec {shlex.quote(unzip)} "$@"\n')
        self.assert_preserved(self.run_fetch())

    def test_version_override_cannot_downgrade_the_pinned_release(self):
        result = self.run_fetch(EASYTIER_VERSION='2.6.4')
        self.assert_preserved(result)
        self.assertIn('pins EasyTier 2.7.0', result.stderr)


class ReleaseSourceTest(unittest.TestCase):
    def test_repository_sources_share_release_pins(self):
        pins = dict(line.split('=', 1) for line in (ROOT / 'scripts/easytier-release.conf').read_text().splitlines()
                    if line and not line.startswith('#'))
        self.assertEqual('2.7.0', pins['EASYTIER_VERSION'])
        revision = pins['EASYTIER_REVISION']
        self.assertRegex(revision, r'^[0-9a-f]{40}$')
        for name in ['ARCHIVE', 'CORE', 'CLI']:
            self.assertRegex(pins[f'EASYTIER_{name}_SHA256'], r'^[0-9a-f]{64}$')

        cargo = (ROOT / 'native/vpn/Cargo.toml').read_text()
        dependencies = re.findall(r'(?m)^[\w-]+\s*=\s*\{[^\n]*git\s*=\s*"https://github.com/EasyTier/EasyTier.git"[^\n]*\}', cargo)
        self.assertTrue(dependencies, 'VPN library must use a revision-pinned EasyTier dependency')
        for dependency in dependencies:
            self.assertRegex(dependency, rf'\brev\s*=\s*"{revision}"')

        lock = (ROOT / 'native/vpn/Cargo.lock').read_text()
        easytier = re.search(r'(?ms)^\[\[package\]\]\nname = "easytier"\n(.*?)(?=^\[\[package\]\]|\Z)', lock)
        self.assertIsNotNone(easytier)
        self.assertIn(f'version = "{pins["EASYTIER_VERSION"]}"', easytier[1])
        sources = re.findall(r'^source = "(git\+https://github.com/EasyTier/EasyTier.git[^"]+)"', lock, re.M)
        self.assertTrue(sources)
        self.assertEqual({f'git+https://github.com/EasyTier/EasyTier.git?rev={revision}#{revision}'}, set(sources))

        gradle = (ROOT / 'android/app/build.gradle.kts').read_text()
        prepare = gradle.split('val prepareEngine by', 1)[1].split('tasks.named("preBuild")', 1)[0]
        self.assertIn('scripts/prepare-android-engine.sh', prepare)
        self.assertIn('scripts/fetch-upstream.sh', prepare)
        self.assertIn('scripts/easytier-release.conf', prepare)
        for entry in ['scripts/build-module.sh', 'scripts/prepare-android-engine.sh']:
            self.assertIn('bash "$ROOT/scripts/fetch-upstream.sh"', (ROOT / entry).read_text())


if __name__ == '__main__':
    unittest.main()

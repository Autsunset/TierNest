#!/usr/bin/env python3
import hashlib
import importlib.util
from pathlib import Path
import struct
import tempfile
import unittest
from unittest import mock
import zipfile

spec = importlib.util.spec_from_file_location('artifact', Path(__file__).resolve().parents[1] / 'scripts/verify-android-artifact.py')
artifact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifact)
PAYLOADS = {
    'easytier-core': b'synthetic pinned core\n',
    'easytier-cli': b'synthetic pinned cli\n',
    'home-probe': b'synthetic locally built probe\n',
}


def manifest(payloads):
    return ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in payloads.items())


class ArtifactTest(unittest.TestCase):
    def errors(self, mode='release', **changes):
        data = dict(package='com.tiernest.app', version='0.2.0-rc06', code=16, signer='release-cert', debuggable=False)
        if mode == 'ci': data.update(package='com.tiernest.app.ci', version='0.2.0-rc06-ci', signer='ci-cert')
        data.update(changes)
        return artifact.identity_errors(**data, mode=mode, expected_version='0.2.0-rc06', expected_code=16, release_cert='release-cert')

    def test_distribution_identity_and_ci_are_both_valid_but_distinct(self):
        self.assertEqual([], self.errors())
        self.assertEqual([], self.errors('ci'))
        self.assertTrue(self.errors('ci', package='com.tiernest.app'))
        self.assertTrue(self.errors('ci', signer='release-cert'))
        self.assertTrue(self.errors(signer='ci-cert'))

    def test_stale_or_relabelled_artifacts_are_rejected(self):
        self.assertTrue(self.errors(version='0.2.0-alpha10'))
        self.assertTrue(self.errors(code=10))
        self.assertTrue(self.errors('ci', version='0.2.0-rc06'))
        self.assertTrue(self.errors(debuggable=True))

    def elf(self, alignment=16384, offset=0, address=0):
        data = bytearray(120)
        data[:6] = b'\x7fELF\x02\x01'
        struct.pack_into('<Q', data, 32, 64)
        struct.pack_into('<HH', data, 54, 56, 1)
        struct.pack_into('<IIQQQQQQ', data, 64, 1, 5, offset, address, 0, 4096, 4096, alignment)
        return data

    def test_elf_checks_actual_load_segment_alignment(self):
        self.assertEqual([], artifact.elf_errors(self.elf()))
        self.assertTrue(artifact.elf_errors(self.elf(alignment=4096)))
        self.assertTrue(artifact.elf_errors(self.elf(address=4096)))
        self.assertEqual([], artifact.elf_errors(self.elf(offset=16384, address=32768)))

    def test_truncated_and_non_elf_inputs_are_rejected(self):
        self.assertTrue(artifact.elf_errors(b'not an ELF'))
        self.assertTrue(artifact.elf_errors(self.elf()[:80]))

    def inspect_payloads(self, payloads=None, sums=None):
        payloads = PAYLOADS if payloads is None else payloads
        with tempfile.TemporaryDirectory(prefix='tiernest-apk-pins-') as directory:
            root = Path(directory)
            (root / 'android/app').mkdir(parents=True)
            (root / 'scripts').mkdir()
            (root / 'android/app/build.gradle.kts').write_text('versionCode = 17\nversionName = "0.2.0-rc07"\n')
            signer = 'a' * 64
            (root / 'android/release-cert.sha256').write_text(signer + '\n')
            (root / 'scripts/easytier-release.conf').write_text(
                'EASYTIER_VERSION=2.7.0\n'
                f'EASYTIER_CORE_SHA256={hashlib.sha256(PAYLOADS["easytier-core"]).hexdigest()}\n'
                f'EASYTIER_CLI_SHA256={hashlib.sha256(PAYLOADS["easytier-cli"]).hexdigest()}\n'
            )
            apk = root / 'fixture.apk'
            with zipfile.ZipFile(apk, 'w', zipfile.ZIP_DEFLATED) as archive:
                for name, data in payloads.items():
                    archive.writestr('assets/engine/' + name, data)
                archive.writestr('assets/engine/SHA256SUMS', manifest(payloads) if sums is None else sums)
                for abi in ['arm64-v8a', 'x86_64']:
                    archive.writestr(f'lib/{abi}/libtiernest_vpn.so', self.elf())
            signed = f'Signer #1 certificate SHA-256 digest: {signer}\n'
            badging = ("package: name='com.tiernest.app' versionCode='17' versionName='0.2.0-rc07'\n"
                       "sdkVersion:'26'\ntargetSdkVersion:'36'\n")
            with mock.patch.object(artifact, 'ROOT', root), \
                    mock.patch.object(artifact.subprocess, 'check_output', side_effect=[signed, badging]), \
                    mock.patch.object(artifact.subprocess, 'run') as zipalign:
                try:
                    result = artifact.inspect(apk, root / 'mock-sdk', 'release')
                except ValueError:
                    zipalign.assert_not_called()
                    raise
                zipalign.assert_called_once()
                return result

    def test_apk_root_payloads_match_both_manifest_and_repository_pins(self):
        self.assertEqual('0.2.0-rc07', self.inspect_payloads()['version'])

    def test_self_consistent_stale_root_core_or_cli_is_rejected(self):
        for name in ['easytier-core', 'easytier-cli']:
            with self.subTest(payload=name), self.assertRaisesRegex(ValueError, 'pinned'):
                self.inspect_payloads({**PAYLOADS, name: b'synthetic stale release'})

    def test_apk_manifest_tampering_is_still_rejected(self):
        sums = manifest(PAYLOADS).replace(hashlib.sha256(PAYLOADS['easytier-core']).hexdigest(), '0' * 64)
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            self.inspect_payloads(sums=sums)

    def test_home_probe_is_locally_built_but_must_match_its_manifest(self):
        rebuilt = {**PAYLOADS, 'home-probe': b'synthetic rebuilt probe\n'}
        self.assertEqual('0.2.0-rc07', self.inspect_payloads(rebuilt)['version'])
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            self.inspect_payloads(rebuilt, sums=manifest(PAYLOADS))

    def test_duplicate_incomplete_and_unexpected_manifest_entries_are_rejected(self):
        cases = [
            (manifest(PAYLOADS) + manifest({'easytier-core': PAYLOADS['easytier-core']}), 'duplicate'),
            (manifest({name: data for name, data in PAYLOADS.items() if name != 'easytier-cli'}), 'incomplete'),
            (manifest(PAYLOADS) + manifest({'unexpected': b'extra'}), 'unexpected'),
        ]
        for sums, error in cases:
            with self.subTest(error=error), self.assertRaisesRegex(ValueError, error):
                self.inspect_payloads(sums=sums)


if __name__ == '__main__':
    unittest.main()

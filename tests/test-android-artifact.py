#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location('artifact', Path(__file__).resolve().parents[1] / 'scripts/verify-android-artifact.py')
artifact = importlib.util.module_from_spec(spec)
spec.loader.exec_module(artifact)


class ArtifactTest(unittest.TestCase):
    def errors(self, mode='release', **changes):
        data = dict(package='com.tiernest.app', version='0.2.0-rc01', code=11, signer='release-cert', debuggable=False)
        if mode == 'ci': data.update(package='com.tiernest.app.ci', version='0.2.0-rc01-ci', signer='ci-cert')
        data.update(changes)
        return artifact.identity_errors(**data, mode=mode, expected_version='0.2.0-rc01', expected_code=11, release_cert='release-cert')

    def test_distribution_identity_and_ci_are_both_valid_but_distinct(self):
        self.assertEqual([], self.errors())
        self.assertEqual([], self.errors('ci'))
        self.assertTrue(self.errors('ci', package='com.tiernest.app'))
        self.assertTrue(self.errors('ci', signer='release-cert'))
        self.assertTrue(self.errors(signer='ci-cert'))

    def test_stale_or_relabelled_artifacts_are_rejected(self):
        self.assertTrue(self.errors(version='0.2.0-alpha10'))
        self.assertTrue(self.errors(code=10))
        self.assertTrue(self.errors('ci', version='0.2.0-rc01'))
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


if __name__ == '__main__':
    unittest.main()

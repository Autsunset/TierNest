#!/usr/bin/env python3
import importlib.util
import io
from pathlib import Path
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("privacy", Path(__file__).resolve().parents[1] / "scripts/check-apk-privacy.py")
privacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(privacy)


class PrivacyTests(unittest.TestCase):
    def scan(self, files):
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as archive:
            for name, data in files.items():
                archive.writestr(name, data)
        buffer.seek(0)
        return privacy.findings(buffer, [b"/home/synthetic-builder"])

    def test_stripped_native_panic_paths_are_still_rejected(self):
        hits = self.scan({"lib/arm64-v8a/libtiernest_vpn.so": b"\x7fELF\0/home/synthetic-builder/.cargo/crate/src/lib.rs\0"})
        self.assertIn(("lib/arm64-v8a/libtiernest_vpn.so", "developer filesystem path"), hits)

    def test_other_developers_and_dex_paths_are_rejected(self):
        self.assertTrue(self.scan({"classes.dex": b"/Users/synthetic-other/project/Main.kt"}))

    def test_portable_paths_and_verified_upstream_paths_are_allowed(self):
        self.assertEqual([], self.scan({"lib/x86_64/libtiernest_vpn.so": b"/build/user/.cargo/crate/src/lib.rs",
            "assets/engine/easytier-core": b"/home/upstream-runner/work/core"}))

    def test_runtime_backups_and_private_keys_are_rejected(self):
        self.assertTrue(self.scan({"assets/backups/config.toml": b"fixture"}))
        self.assertTrue(self.scan({"assets/signing.txt": b"-----BEGIN PRIVATE KEY-----"}))


if __name__ == "__main__":
    unittest.main()

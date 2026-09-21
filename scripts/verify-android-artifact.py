#!/usr/bin/env python3
"""Reject incorrectly identified/signed Android artifacts before distribution."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def identity_errors(package, version, code, signer, debuggable, mode, expected_version, expected_code, release_cert):
    errors = []
    expected_package = 'com.tiernest.app.ci' if mode == 'ci' else 'com.tiernest.app'
    expected_name = expected_version + ('-ci' if mode == 'ci' else '')
    if package != expected_package: errors.append('application ID does not match build mode')
    if version != expected_name or code != expected_code: errors.append('APK version does not match source')
    if debuggable: errors.append('release artifact is debuggable')
    if mode == 'release' and signer != release_cert: errors.append('distribution signing certificate changed')
    if mode == 'ci' and signer == release_cert: errors.append('CI artifact used the distribution identity')
    return errors


def elf_errors(data):
    if len(data) < 64 or data[:6] != b'\x7fELF\x02\x01': return ['expected little-endian ELF64']
    phoff = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    if size < 56 or not count or phoff + size * count > len(data): return ['invalid ELF program headers']
    load_segments = 0
    for i in range(count):
        kind, _, offset, address, _, _, _, alignment = struct.unpack_from('<IIQQQQQQ', data, phoff + size * i)
        if kind == 1:
            load_segments += 1
            if alignment < 16384 or (address - offset) % 16384: return ['ELF load segment is not 16 KiB aligned']
    return [] if load_segments else ['ELF has no load segments']


def inspect(apk, sdk, mode):
    build_tools = sdk / 'build-tools/36.0.0'
    signed = subprocess.check_output([str(build_tools / 'apksigner'), 'verify', '--print-certs', str(apk)], text=True)
    signers = re.findall(r'Signer #\d+ certificate SHA-256 digest: ([a-fA-F0-9]{64})', signed)
    if len(signers) != 1: raise ValueError('Expected exactly one current APK signing certificate')
    signer = signers[0].lower()
    badging = subprocess.check_output([str(build_tools / 'aapt'), 'dump', 'badging', str(apk)], text=True)
    package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
    if not package: raise ValueError('Could not read APK package identity')
    source = (ROOT / 'android/app/build.gradle.kts').read_text()
    expected_code = int(re.search(r'versionCode = (\d+)', source)[1])
    expected_version = re.search(r'versionName = "([^"]+)"', source)[1]
    release_cert = (ROOT / 'android/release-cert.sha256').read_text().strip()
    errors = identity_errors(package[1], package[3], int(package[2]), signer,
        'application-debuggable' in badging, mode, expected_version, expected_code, release_cert)
    if "sdkVersion:'26'" not in badging: errors.append('minimum Android API changed')
    if "targetSdkVersion:'36'" not in badging: errors.append('target Android API changed')
    with zipfile.ZipFile(apk) as archive:
        native = [n for n in archive.namelist() if n.startswith('lib/') and n.endswith('.so')]
        if {n.split('/')[1] for n in native} != {'arm64-v8a', 'x86_64'}: errors.append('expected both supported native ABIs')
        for name in native:
            errors.extend(f'{name}: {error}' for error in elf_errors(archive.read(name)))
        payloads = set()
        for line in archive.read('assets/engine/SHA256SUMS').decode().splitlines():
            digest, name = line.split()
            if name in payloads: errors.append('duplicate Root payload checksum')
            payloads.add(name)
            if name not in {'easytier-core', 'easytier-cli', 'home-probe'}: errors.append('unexpected Root payload')
            elif hashlib.sha256(archive.read('assets/engine/' + name)).hexdigest() != digest: errors.append('Root payload checksum mismatch')
        if payloads != {'easytier-core', 'easytier-cli', 'home-probe'}: errors.append('incomplete Root payload manifest')
    if errors: raise ValueError('; '.join(errors))
    subprocess.run([str(build_tools / 'zipalign'), '-c', '-P', '16', '4', str(apk)], check=True)
    return {'mode': mode, 'application_id': package[1], 'version': package[3], 'version_code': int(package[2]),
            'apk_sha256': hashlib.sha256(apk.read_bytes()).hexdigest(), 'signer_sha256': signer,
            'debuggable': False, 'native_abis': ['arm64-v8a', 'x86_64'], 'page_alignment': 16384}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    parser.add_argument('--mode', choices=['release', 'ci'], default='release')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    sdk = Path(os.environ.get('ANDROID_HOME', os.environ.get('ANDROID_SDK_ROOT', str(Path.home() / 'Android/Sdk'))))
    result = inspect(args.apk, sdk, args.mode)
    if args.report: args.report.write_text(json.dumps(result, indent=2) + '\n')
    print('Verified APK identity, signing certificate, release flags, native ABIs and 16 KiB alignment')


if __name__ == '__main__':
    main()

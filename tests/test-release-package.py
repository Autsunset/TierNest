#!/usr/bin/env python3
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import stat
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('tiernest_packager', ROOT/'scripts/package-module.py')
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)

with tempfile.TemporaryDirectory(prefix='tiernest-release-') as directory:
    sandbox = Path(directory).resolve()
    shutil.copytree(ROOT/'module', sandbox/'module', ignore=shutil.ignore_patterns('run', 'logs'))
    packager.ROOT = sandbox
    packager.MODULE = sandbox/'module'
    for relative in ['config/backups/private.toml', 'config/command_args', 'config/service-mode.state',
                     'config/home-network.conf', 'config/home-detection.conf', 'config/manual_stop', 'run/session', 'logs/runtime.log']:
        path = packager.MODULE/relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('private-runtime-sentinel', encoding='utf-8')
    with contextlib.redirect_stdout(io.StringIO()):
        output = packager.package_module()
        first = output.read_bytes()
        packager.package_module()
    assert output.read_bytes() == first, 'Packaging should be reproducible'
    assert output.with_suffix('.zip.sha256').read_text().split()[0] == hashlib.sha256(first).hexdigest()
    with zipfile.ZipFile(output) as archive:
        assert archive.testzip() is None
        for info in archive.infolist():
            assert not info.filename.startswith(('run/', 'logs/', 'config/backups/'))
            assert b'private-runtime-sentinel' not in archive.read(info)
        assert 'config/command_args' not in archive.namelist()
        assert 'config/home-detection.conf' not in archive.namelist()
        assert stat.S_IMODE(archive.getinfo('bin/tiernest-netwatch').external_attr >> 16) == 0o755
        assert stat.S_IMODE(archive.getinfo('customize.sh').external_attr >> 16) == 0o755
        assert stat.S_IMODE(archive.getinfo('bin/easytier-core').external_attr >> 16) == 0o755
        assert stat.S_IMODE(archive.getinfo('settings.conf').external_attr >> 16) == 0o644

    template = (packager.MODULE/'config/config.toml').read_text(encoding='utf-8')
    for field in ['hostname = "private-device"\n', 'ipv4 = "10.1.2.3/24"\n']:
        (packager.MODULE/'config/config.toml').write_text(field+template, encoding='utf-8')
        try:
            packager.package_module()
        except ValueError:
            pass
        else:
            raise AssertionError('Packager accepted a private identity')
    (packager.MODULE/'config/config.toml').write_text(template.replace('network_secret = ""', 'network_secret = "private-secret"'), encoding='utf-8')
    try:
        packager.package_module()
    except ValueError:
        pass
    else:
        raise AssertionError('Packager accepted a network secret')
    (packager.MODULE/'config/config.toml').write_text(template, encoding='utf-8')
    (packager.MODULE/'config/device-profile.txt').write_text('profile=old-device\n')
    try:
        packager.package_module()
    except ValueError:
        pass
    else:
        raise AssertionError('Packager accepted a device profile')
print('Universal release integrity, permissions, reproducibility and private-data exclusions passed.')

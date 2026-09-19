#!/usr/bin/env python3
"""Package the validated universal module without device identities or runtime state."""
import hashlib
import os
from pathlib import Path
import re
import stat
import tempfile
import tomllib
import zipfile

ROOT = Path(__file__).resolve().parent.parent
MODULE = ROOT / 'module'


def package_module():
    props = dict(line.split('=', 1) for line in (MODULE / 'module.prop').read_text(encoding='utf-8').splitlines() if '=' in line)
    version = props['version']
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+-et[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('Only an unlabelled universal release version is supported')
    if props['id'] != 'tiernest' or props['name'] != 'TierNest Core':
        raise ValueError('Universal module identity was changed')
    config = tomllib.loads((MODULE / 'config/config.toml').read_text(encoding='utf-8'))
    identity = config.get('network_identity', {})
    if (config.get('hostname') or config.get('ipv4') or config.get('peer') or
            identity.get('network_name') != 'default' or identity.get('network_secret')):
        raise ValueError('The universal package must contain only the unconfigured template')
    if (MODULE / 'config/device-profile.txt').exists():
        raise ValueError('Device-specific profiles are retired')
    if any(line.strip() and not line.lstrip().startswith('#') for line in
           (MODULE / 'config/node-locations.conf').read_text(encoding='utf-8').splitlines()):
        raise ValueError('The universal package cannot contain private node annotations')

    allowed_config = {'config.toml', 'command_args_sample', 'node-locations.conf'}
    allowed_roots = {'bin', 'config', 'META-INF', 'webroot'}
    root_files = {'module.prop', 'settings.conf', 'skip_mount', 'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md'}
    entries = []
    for path in sorted(MODULE.rglob('*')):
        rel = path.relative_to(MODULE)
        if not path.is_file() or path.is_symlink():
            continue
        if len(rel.parts) == 1:
            if path.name not in root_files and path.suffix != '.sh':
                continue
        elif rel.parts[0] not in allowed_roots:
            continue
        elif rel.parts[0] == 'config' and (len(rel.parts) != 2 or path.name not in allowed_config):
            continue
        if path.name.endswith('.map') or path.name == '.DS_Store':
            continue
        entries.append((path, rel.as_posix()))

    out_dir = ROOT / 'dist'
    out_dir.mkdir(exist_ok=True)
    output = out_dir / f'TierNest-v{version}-arm64.zip'
    handle, temporary = tempfile.mkstemp(prefix='.tiernest-', suffix='.zip', dir=out_dir)
    os.close(handle)
    try:
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            for path, name in entries:
                info = zipfile.ZipInfo(name, date_time=(2026, 9, 12, 0, 0, 0))
                info.create_system = 3
                executable = name.endswith('.sh') or name.startswith('bin/') or name.endswith('/update-binary')
                info.external_attr = (stat.S_IFREG | (0o755 if executable else 0o644)) << 16
                info.compress_type = zipfile.ZIP_DEFLATED
                archive.writestr(info, path.read_bytes())
        with zipfile.ZipFile(temporary) as archive:
            if archive.testzip() is not None:
                raise ValueError('ZIP integrity check failed')
            required = {'module.prop', 'customize.sh', 'service.sh', 'common.sh', 'config/config.toml',
                        'bin/easytier-core', 'bin/easytier-cli', 'bin/tiernest-netwatch', 'META-INF/com/google/android/update-binary'}
            if not required.issubset(archive.namelist()):
                raise ValueError('Required module entries missing')
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix('.zip.sha256').write_text(f'{digest}  {output.name}\n', encoding='utf-8')
    print(output)
    print(f'SHA256 {digest}')
    return output


if __name__ == '__main__':
    package_module()

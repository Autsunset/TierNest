#!/usr/bin/env python3
"""Observe an already connected test VPN using a synthetic HTTP subnet target.

Requires an explicitly selected, authorized rooted test device for /proc metrics.
Does not change connection settings or install/stop applications. This measures
traffic continuity and process resources, not real-device standby battery use.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('serial')
    parser.add_argument('--package', default='com.tiernest.app.ci')
    parser.add_argument('--seconds', type=int, default=1800)
    parser.add_argument('--interval', type=int, default=10)
    parser.add_argument('--target', default='198.51.100.9')
    parser.add_argument('--port', type=int, default=32980)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[a-zA-Z0-9_.]+', args.package): parser.error('Invalid package')
    if not re.fullmatch(r'[0-9.]+', args.target): parser.error('Use a numeric IPv4 test target')
    if not (1 <= args.port <= 65535 and args.seconds > 0 and args.interval > 0): parser.error('Invalid timing or port')
    sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Android/Sdk')))
    adb = [str(sdk / 'platform-tools/adb'), '-s', args.serial]

    def shell(command):
        return subprocess.check_output(adb + ['shell', command], text=True, timeout=8).strip()

    samples = []
    started = time.monotonic()
    try:
        while True:
            sample = {'seconds': round(time.monotonic() - started, 2), 'http_ok': False}
            output = b''
            try:
                response = subprocess.run(adb + ['shell', f'toybox nc -w 3 -W 3 -q 2 {args.target} {args.port}'],
                    input=b'GET / HTTP/1.0\r\nHost: fixture\r\n\r\n', capture_output=True, timeout=6)
                output = response.stdout
                sample['probe_exit'] = response.returncode
            except subprocess.TimeoutExpired as error:
                # Preserve received data so a hung probe's connection teardown
                # is not silently confused with missing application data.
                sample['probe_timeout'] = True
                output = error.stdout or b''
            except subprocess.SubprocessError:
                sample['probe_error'] = True
            header, _, body = output.partition(b'\r\n\r\n')
            sample['http_ok'] = b' 200 ' in header.split(b'\r\n')[0] and body == b'TIERNEST_STABLE_OK\n'
            try:
                pid = int(shell('pidof ' + args.package).split()[0])
                status = shell(f'cat /proc/{pid}/status')
                sample.update(pid=pid, fds=int(shell(f'ls /proc/{pid}/fd | wc -l')),
                    threads=int(re.search(r'^Threads:\s+(\d+)', status, re.M)[1]),
                    rss_kib=int(re.search(r'^VmRSS:\s+(\d+)', status, re.M)[1]))
            except (subprocess.SubprocessError, ValueError, IndexError, TypeError):
                sample['sample_error'] = True
            samples.append(sample)
            elapsed = time.monotonic() - started
            if elapsed >= args.seconds: break
            time.sleep(min(args.interval, args.seconds - elapsed))
    finally:
        successful = [s for s in samples if 'pid' in s]
        result = {'package': args.package, 'duration_seconds': round(time.monotonic() - started, 2),
            'samples': samples, 'http_failures': sum(not s['http_ok'] for s in samples),
            'probe_timeouts': sum(bool(s.get('probe_timeout')) for s in samples),
            'probe_failures': sum(s.get('probe_exit', 1) != 0 for s in samples),
            'process_ids': sorted({s['pid'] for s in successful}),
            'resources': {key: {'min': min(s[key] for s in successful), 'max': max(s[key] for s in successful),
                'first': successful[0][key], 'last': successful[-1][key]} for key in ['fds', 'threads', 'rss_kib']} if successful else {}}
        args.output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({k: v for k, v in result.items() if k != 'samples'}, indent=2))
    if result['http_failures'] or result['probe_failures'] or len(result['process_ids']) != 1 or len(successful) != len(samples):
        raise SystemExit(1)


if __name__ == '__main__':
    main()

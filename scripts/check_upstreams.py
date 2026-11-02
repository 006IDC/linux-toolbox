#!/usr/bin/env python3
"""Check provenance and lock integrity; --network downloads but never runs tools."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--network', action='store_true')
    args = p.parse_args()
    upstreams = json.loads((ROOT/'upstreams.json').read_text())['upstreams']
    rows = [line.split('\t') for line in (ROOT/'tools.lock.tsv').read_text().splitlines() if not line.startswith('#')]
    seen = set()
    for row in rows:
        assert len(row) == 11, row[0]
        ident, title, kind, arch, key, ref, source, digest, entry, root, effects = row
        assert (ident, arch) not in seen
        seen.add((ident, arch))
        assert re.fullmatch(r'[a-z][a-z0-9-]*', ident)
        assert re.fullmatch(r'[a-f0-9]{64}', digest)
        assert root in ('0', '1') and title and effects
        u = upstreams[key]
        assert (ROOT/u['license_file']).is_file()
        assert re.fullmatch(r'[a-f0-9]{40}', u['commit'])
        if kind == 'bundled':
            assert source == 'vendor/jcnf/swap.sh'
            assert hashlib.sha256((ROOT/source).read_bytes()).hexdigest() == digest
            continue
        allowed = (f"https://raw.githubusercontent.com/{u['repository']}/{u['commit']}/", f"https://github.com/{u['repository']}/releases/download/{ref}/", f"https://codeload.github.com/{u['repository']}/tar.gz/{u['commit']}")
        assert source.startswith(allowed), source
        if not args.network:
            continue
        with tempfile.TemporaryDirectory(prefix='006box-check-') as tmp:
            f = Path(tmp)/'payload'
            subprocess.run(['curl', '--proto', '=https', '--proto-redir', '=https', '-fsSL', '--connect-timeout', '15', '--max-time', '300', '--retry', '2', source, '-o', str(f)], check=True)
            assert hashlib.sha256(f.read_bytes()).hexdigest() == digest, ident
            if kind == 'bash':
                if sys.platform.startswith('linux'):
                    subprocess.run(['bash', '-n', str(f)], check=True)
                else:
                    print(f'{ident}: upstream Bash syntax is checked by Linux CI (host may have Bash 3)')
            elif kind == 'tar-bash':
                with tarfile.open(f) as t:
                    assert all(not (m.issym() or m.islnk()) and not m.name.startswith('/') and '..' not in Path(m.name).parts for m in t.getmembers())
                    assert t.getmember(entry).isfile()
            elif kind == 'zip-bin':
                with zipfile.ZipFile(f) as z:
                    assert entry in z.namelist() and z.getinfo(entry).file_size > 0
            elif kind == 'binary':
                assert f.read_bytes()[:4] == b'\x7fELF'
            else:
                raise AssertionError(kind)
        print(f'{ident}/{arch}: fixed source and SHA256 verified')
    print(f'PASS: {len(rows)} locked entries; {len(upstreams)} credited upstream projects')


if __name__ == '__main__':
    main()

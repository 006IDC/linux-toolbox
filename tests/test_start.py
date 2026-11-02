"""Bootstrap failures and argument forwarding, with synthetic release downloads."""
import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
RELEASE_DIGEST = '1179fffeea6190922a0047acb59ce18e3480eaf04c56a417fbccd51e57f10a79'


class StartTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='006box-bootstrap-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.bin = self.base/'bin'
        self.bin.mkdir()
        self.marker = self.base/'executed'
        self.archive = self.base/'release.tgz'
        self.payload = b'#!/usr/bin/env bash\nprintf "%s\\n" "$@" > "$START_MARKER"\nprintf "%s\\n" "$0" > "$ENTRY_MARKER"\nexit "${CHILD_EXIT:-0}"\n'
        self.make_archive()
        self.start = self.base/'start.sh'
        self.start.write_text((ROOT/'start.sh').read_text().replace(RELEASE_DIGEST, hashlib.sha256(self.archive.read_bytes()).hexdigest()))
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', START_PAYLOAD=str(self.archive), START_MARKER=str(self.marker), ENTRY_MARKER=str(self.base/'entry-path'))
        self.stub('uname', 'echo Linux')
        self.stub('curl', '[[ ${CURL_FAIL:-0} == 0 ]] || exit "$CURL_FAIL"\nwhile [[ $# -gt 0 ]]; do if [[ $1 == -o ]]; then cp "$START_PAYLOAD" "$2"; exit $?; fi; shift; done\nexit 2')

    def make_archive(self):
        with tarfile.open(self.archive, 'w:gz') as t:
            entry = tarfile.TarInfo('006idc-linux-toolbox-0.1.0/toolbox.sh')
            entry.size = len(self.payload)
            t.addfile(entry, io.BytesIO(self.payload))

    def stub(self, name, body):
        p = self.bin/name
        p.write_text('#!/usr/bin/env bash\n'+body+'\n')
        p.chmod(0o700)

    def run_start(self, *args, **changes):
        return subprocess.run(['bash', str(self.start), *args], cwd=self.base, env=dict(self.env, **changes), text=True, capture_output=True)

    def test_archive_success_preserves_literal_arguments_and_exit(self):
        r = self.run_start('show', 'a b', '$(touch injected)', CHILD_EXIT='23')
        self.assertEqual(r.returncode, 23, r.stderr)
        self.assertEqual(self.marker.read_text().splitlines(), ['show', 'a b', '$(touch injected)'])
        self.assertFalse((self.base/'injected').exists())
        self.assertFalse(Path((self.base/'entry-path').read_text().strip()).exists(), 'temporary bundle must be removed')

    def test_failed_download_does_not_start(self):
        r = self.run_start(CURL_FAIL='22')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('下载失败', r.stderr)
        self.assertFalse(self.marker.exists())

    def test_tampered_archive_is_not_extracted(self):
        self.archive.write_bytes(b'changed-download')
        self.stub('tar', 'touch "$START_MARKER"; exit 99')
        r = self.run_start()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('SHA256', r.stderr)
        self.assertFalse(self.marker.exists())

    def test_empty_archive_is_rejected(self):
        self.archive.write_bytes(b'')
        r = self.run_start()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('为空', r.stderr)
        self.assertFalse(self.marker.exists())

    def test_non_linux_is_rejected_before_download(self):
        self.stub('uname', 'echo Darwin')
        self.stub('curl', 'touch "$START_MARKER"; exit 22')
        r = self.run_start()
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.marker.exists())


if __name__ == '__main__':
    unittest.main()

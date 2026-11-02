"""Behavioral tests with synthetic downloads; never change the host system."""
import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='006box-test-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.repo = self.base/'repo with spaces'
        shutil.copytree(ROOT, self.repo, ignore=shutil.ignore_patterns('.git', '__pycache__', 'dist'))
        self.bin = self.base/'bin'
        self.bin.mkdir()
        self.marker = self.base/'executed'
        self.payload = self.base/'payload'
        self.payload.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$@" > "$MARKER"\nexit "${CHILD_EXIT:-0}"\n')
        self.env = dict(os.environ, PATH=f'{self.bin}:{os.environ["PATH"]}', MARKER=str(self.marker), FIXTURE_PAYLOAD=str(self.payload))
        self.stub('uname', 'case "$1" in -s) echo Linux;; -m) echo "${FAKE_ARCH:-x86_64}";; *) echo test-kernel;; esac')
        self.env['CURL_MARKER'] = str(self.base/'curl-called')
        self.stub('curl', ': > "$CURL_MARKER"\n[[ ${CURL_FAIL:-0} == 0 ]] || exit "$CURL_FAIL"\nwhile [[ $# -gt 0 ]]; do if [[ $1 == -o ]]; then cp "$FIXTURE_PAYLOAD" "$2"; exit $?; fi; shift; done\nexit 2')
        self.rows = [x.split('\t') for x in (self.repo/'tools.lock.tsv').read_text().splitlines() if not x.startswith('#')]
        for row in self.rows:
            row[7] = hashlib.sha256(self.payload.read_bytes()).hexdigest()
        self.save_rows()

    def stub(self, name, body):
        p = self.bin/name
        p.write_text('#!/usr/bin/env bash\n'+body+'\n')
        p.chmod(0o700)

    def save_rows(self):
        (self.repo/'tools.lock.tsv').write_text('\n'.join('\t'.join(r) for r in self.rows)+'\n')

    def run_box(self, *args, **changes):
        env = dict(self.env, **changes)
        return subprocess.run(['bash', str(self.repo/'toolbox.sh'), *args], env=env, cwd=self.base, text=True, capture_output=True)

    def test_listing_is_offline_and_attributes_sources(self):
        r = self.run_box('list', CURL_FAIL='22')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('mirrors', r.stdout)
        self.assertIn('NextTrace', r.stdout)
        self.assertFalse(self.marker.exists())

    def test_noninteractive_requires_confirmation(self):
        r = self.run_box('run', 'yabs')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('--yes', r.stderr)
        self.assertFalse(self.marker.exists())

    def test_download_failure_never_executes(self):
        r = self.run_box('run', 'yabs', '--yes', CURL_FAIL='22')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('下载失败', r.stderr)
        self.assertFalse(self.marker.exists())

    def test_tampered_download_never_executes(self):
        self.payload.write_text('#!/bin/bash\ntouch "$MARKER"\n')
        r = self.run_box('run', 'yabs', '--yes')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('SHA256', r.stderr)
        self.assertFalse(self.marker.exists())

    def test_empty_download_never_executes(self):
        self.payload.write_bytes(b'')
        r = self.run_box('run', 'yabs', '--yes')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.marker.exists())

    def test_arguments_are_literal_and_upstream_exit_propagates(self):
        r = self.run_box('run', 'yabs', '--yes', '--', 'a b', '$(touch injection)', '; touch injection', CHILD_EXIT='23')
        self.assertEqual(r.returncode, 23, r.stderr)
        self.assertEqual(self.marker.read_text().splitlines(), ['a b', '$(touch injection)', '; touch injection'])
        self.assertFalse((self.base/'injection').exists())

    def test_verify_does_not_execute(self):
        r = self.run_box('verify', 'yabs')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn('未执行', r.stdout)
        self.assertFalse(self.marker.exists())

    def test_bad_syntax_is_rejected_even_with_matching_hash(self):
        self.payload.write_text('#!/bin/bash\nif broken\n')
        for row in self.rows:
            row[7] = hashlib.sha256(self.payload.read_bytes()).hexdigest()
        self.save_rows()
        r = self.run_box('run', 'yabs', '--yes')
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.marker.exists())

    def test_upstream_arguments_require_separator(self):
        r = self.run_box('run', 'yabs', '--yes', '-h')
        self.assertEqual(r.returncode, 2)
        self.assertFalse(self.marker.exists())

    def test_unknown_and_injection_ids_are_rejected(self):
        for name in ('missing', '../yabs', '$(touch injection)', '-yabs'):
            r = self.run_box('run', name, '--yes')
            self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.marker.exists())

    @unittest.skipIf(os.geteuid() == 0, 'Requires a regular user')
    def test_root_operation_does_not_elevate_automatically(self):
        r = self.run_box('run', 'mirrors', '--yes')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('sudo', r.stderr)
        self.assertFalse(self.marker.exists())

    def test_architecture_is_checked_before_binary_download(self):
        r = self.run_box('run', 'nexttrace', '--yes', FAKE_ARCH='mips')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('当前架构不支持', r.stderr)
        self.assertFalse(Path(self.env['CURL_MARKER']).exists())
        self.assertFalse(self.marker.exists())

    def test_binary_dispatch_on_both_architectures(self):
        for arch in ('x86_64', 'aarch64'):
            r = self.run_box('run', 'nexttrace', '--yes', '--', '--help', FAKE_ARCH=arch)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(self.marker.read_text().splitlines(), ['--help'])

    def test_privacy_mode_is_added_for_ipquality(self):
        r = self.run_box('run', 'ipquality', '--yes', '--', '-j')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.marker.read_text().splitlines(), ['-p', '-j'])

    def test_tar_source_runs_with_sibling_files_available(self):
        script = self.payload.read_bytes()
        archive = self.base/'source.tgz'
        with tarfile.open(archive, 'w:gz') as t:
            member = tarfile.TarInfo('acme-fixture/acme.sh')
            member.size = len(script)
            t.addfile(member, io.BytesIO(script))
        for row in self.rows:
            if row[0] == 'acme':
                row[7] = hashlib.sha256(archive.read_bytes()).hexdigest()
                row[8] = 'acme-fixture/acme.sh'
        self.save_rows()
        r = self.run_box('run', 'acme', '--yes', '--', '--help', FIXTURE_PAYLOAD=str(archive))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.marker.read_text().splitlines(), ['--help'])

    def test_zip_extracts_only_exact_executable(self):
        archive = self.base/'binary.zip'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr('goecs', self.payload.read_bytes())
            z.writestr('../unwanted', 'must never extract')
        for row in self.rows:
            if row[0] == 'ecs': row[7] = hashlib.sha256(archive.read_bytes()).hexdigest()
        self.save_rows()
        r = self.run_box('run', 'ecs', '--yes', '--', '-h', FIXTURE_PAYLOAD=str(archive))
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.marker.read_text().splitlines(), ['-h'])
        self.assertFalse((self.base/'unwanted').exists())

    def test_darwin_is_blocked_before_network_or_execution(self):
        self.stub('uname', 'echo Darwin')
        r = self.run_box('run', 'yabs', '--yes')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('Linux', r.stderr)
        self.assertFalse(self.marker.exists())


if __name__ == '__main__':
    unittest.main()

"""Real release download and interactive menu exit through a Linux pseudo-terminal."""
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import time

root = Path(__file__).resolve().parents[1]
master, slave = pty.openpty()
command = ['bash', str(root/'start.sh')]
sha = os.environ.get('GITHUB_SHA', '')
if os.environ.get('GITHUB_EVENT_NAME') in ('push', 'workflow_dispatch') and re.fullmatch(r'[a-f0-9]{40}', sha):
    # Exercise the actual GitHub URL + process-substitution command at this commit.
    command = ['bash', '-c', f'bash <(curl -fsSL https://raw.githubusercontent.com/006IDC/linux-toolbox/{sha}/start.sh)']
child = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, cwd='/tmp')
os.close(slave)
output = bytearray()
sent_exit = False
deadline = time.monotonic() + 240
try:
    while time.monotonic() < deadline:
        if select.select([master], [], [], 1)[0]:
            try:
                data = os.read(master, 65536)
            except OSError:
                break
            if not data:
                break
            output.extend(data)
            if '选择：'.encode() in output and not sent_exit:
                os.write(master, b'0\n')
                sent_exit = True
        elif child.poll() is not None:
            break
    if child.poll() is None:
        child.wait(timeout=5)
    assert child.returncode == 0, output.decode(errors='replace')
    assert sent_exit, output.decode(errors='replace')
    assert '开源整合项目'.encode() in output
    assert 'LinuxMirrors'.encode() in output
    print('PASS: fixed release fetched, verified, interactive menu opened and exited using a terminal')
finally:
    if child.poll() is None:
        child.terminate()
        child.wait(timeout=10)
    os.close(master)

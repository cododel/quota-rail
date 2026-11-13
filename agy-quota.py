"""Read Antigravity's documented statusLine quota without submitting a prompt."""
import json
import os
import pty
import select
import shlex
import signal
import struct
import subprocess
import sys
import tempfile
import time
import fcntl
import termios

BUCKETS = ('gemini-5h', 'gemini-weekly', '3p-5h', '3p-weekly')


def capture(path):
    payload = json.load(sys.stdin)
    quota = payload.get('quota') or {}
    # Never persist account, transcript, workspace, or other session metadata.
    clean = {key: {field: value for field, value in quota[key].items()
                   if field in ('remaining_fraction', 'reset_time', 'disabled')}
             for key in BUCKETS if isinstance(quota.get(key), dict)}
    with open(path + '.next', 'w') as output:
        json.dump(clean, output)
    os.replace(path + '.next', path)


def read_quota(executable):
    parent_pid = os.getppid()
    with tempfile.TemporaryDirectory(prefix='projector-quota-') as directory:
        path = os.path.join(directory, 'quota.json')
        command = shlex.join([sys.executable, os.path.abspath(__file__), '--capture', path])
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        process = None
        try:
            process = subprocess.Popen([
                executable, '--settings', json.dumps({
                    'statusLine': {'type': 'command', 'command': command, 'enabled': True}
                })
            ], stdin=slave, stdout=slave, stderr=slave, cwd=directory, start_new_session=True)
            os.close(slave)
            slave = None
            deadline = time.monotonic() + 25
            while time.monotonic() < deadline and process.poll() is None and os.getppid() == parent_pid:
                if select.select([master], [], [], 0.2)[0]:
                    try:
                        os.read(master, 65536)
                    except OSError:
                        break
                try:
                    with open(path) as source:
                        quota = json.load(source)
                    if all(key in quota for key in BUCKETS):
                        return quota
                except (OSError, ValueError):
                    pass
            return {}
        finally:
            if slave is not None:
                os.close(slave)
            if process is not None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
            os.close(master)


def terminate(_signal, _frame):
    raise SystemExit(1)


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, terminate)
    if len(sys.argv) == 3 and sys.argv[1] == '--capture':
        capture(sys.argv[2])
    else:
        try:
            print(json.dumps(read_quota(sys.argv[1])))
        except (OSError, ValueError):
            print('{}')

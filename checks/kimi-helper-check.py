import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
import time


binary = str(Path(sys.argv[1]).resolve())
fixture = """#!/usr/bin/python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, os, signal, sys, time
from pathlib import Path

assert sys.argv[1:] == [
    'web', '--no-open', '--host', '127.0.0.1', '--port', '0', '--log-level', 'silent'
]
mode = os.environ['KIMI_FIXTURE_MODE']
root = Path(os.environ['KIMI_FIXTURE_DIR'])
if mode in ('startup_timeout', 'timeout'):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
signal.alarm(15)

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        assert self.path == '/api/v1/oauth/usage'
        assert self.headers.get('Authorization') == 'Bearer fixture-token'
        (root / 'request').touch()
        if mode == 'timeout':
            time.sleep(60)
        if mode == 'slow':
            time.sleep(5.25)
        if mode == 'parent_exit':
            time.sleep(0.35)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{"data":{"kind":"ok","quota":{"usages":{}}}}')

server = HTTPServer(('127.0.0.1', 0), Handler)
port = server.server_address[1]
(root / 'server.json').write_text(json.dumps({'pid': os.getpid(), 'port': port}))
if mode != 'startup_timeout':
    print(f'  Local: http://127.0.0.1:{port}/#token=fixture-token', flush=True)
server.serve_forever()
"""


def wait_until(condition, timeout=5):
    deadline = time.monotonic() + timeout
    while not condition():
        assert time.monotonic() < deadline, 'Fixture did not reach the expected state'
        time.sleep(0.02)


def still_running(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    return True


def stopped(server):
    if still_running(server['pid']):
        return False
    with socket.socket() as conn:
        return conn.connect_ex(('127.0.0.1', server['port'])) != 0


with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    executable = root / 'kimi'
    executable.write_text(fixture)
    executable.chmod(0o700)
    for mode in ('ok', 'slow', 'startup_timeout', 'timeout', 'missing', 'parent_exit'):
        case = root / mode
        case.mkdir()
        environment = dict(os.environ, KIMI_FIXTURE_MODE=mode, KIMI_FIXTURE_DIR=str(case))
        if mode == 'parent_exit':
            # The parent exits while the quota request is in flight. The helper must still reap Kimi.
            launch = """
from pathlib import Path
import os, subprocess, sys, time
with open(os.devnull, 'wb') as sink:
    helper = subprocess.Popen(sys.argv[1:], stdout=subprocess.PIPE, stderr=sink)
    root = Path(os.environ['KIMI_FIXTURE_DIR'])
    (root / 'helper-pid').write_text(str(helper.pid))
    request = root / 'request'
    end = time.monotonic() + 4
    while not request.exists() and time.monotonic() < end and helper.poll() is None:
        time.sleep(0.02)
    os._exit(0 if request.exists() else 1)
"""
            subprocess.run([sys.executable, '-c', launch, binary, '--kimi-quota-helper',
                            str(executable)], env=environment, timeout=8, check=True)
            server = json.loads((case / 'server.json').read_text())
            helper_pid = int((case / "helper-pid").read_text())
            wait_until(lambda: stopped(server) and not still_running(helper_pid))
            continue

        flag = '--kimi-quota-helper' if mode == 'slow' else '--check-kimi-helper'
        process = subprocess.run([binary, flag,
                                  str(root / 'missing-kimi' if mode == 'missing' else executable)],
                                 capture_output=True, env=environment, timeout=12, check=True)
        if mode in ('ok', 'slow'):
            assert json.loads(process.stdout)['data']['kind'] == 'ok'
            assert b'fixture-token' not in process.stdout
        else:
            assert process.stdout == b''
        if mode != 'missing':
            assert (case / 'request').exists() == (mode != 'startup_timeout')
            assert stopped(json.loads((case / 'server.json').read_text())), mode

print('PASS: Kimi helper response, slow read, startup and request timeouts, launch failure, and parent exit')

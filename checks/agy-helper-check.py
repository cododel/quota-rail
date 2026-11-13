import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    pidfile = root / 'pid'
    fake = root / 'fake-agy'
    fake.write_text('''#!/usr/bin/python3
import json, os, subprocess, sys, time
from pathlib import Path
Path(%r).write_text(str(os.getpid()))
settings=json.loads(sys.argv[sys.argv.index('--settings')+1])
quota={key:{'remaining_fraction':0.5,'reset_time':'2030-01-01T00:00:00Z'} for key in ('gemini-5h','gemini-weekly','3p-5h','3p-weekly')}
subprocess.run(settings['statusLine']['command'], shell=True, input=json.dumps({'quota':quota,'email':'private@example.invalid','transcript_path':'private'}).encode(), check=True)
time.sleep(60)
''' % str(pidfile))
    fake.chmod(0o700)
    result = subprocess.run([binary, '--check-antigravity-fixture', str(fake), '5'],
                            capture_output=True, timeout=10, check=True)
    assert result.stdout.strip() == b'50 50'
    output = root / 'capture.json'
    bucket = {'remaining_fraction': 0.5, 'reset_time': '2099-01-01T00:00:00Z', 'email': 'private'}
    payload = {'quota': {key: bucket for key in ('gemini-5h', 'gemini-weekly', '3p-5h', '3p-weekly')},
               'transcript_path': 'private'}
    subprocess.run([binary, '--capture-antigravity-quota', str(output)],
                   input=json.dumps(payload).encode(), timeout=5, check=True)
    assert b'private' not in output.read_bytes()
    pid=int(pidfile.read_text())
    try:
        os.kill(pid,0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError('CLI process was not reaped')
    fake.write_text('#!/bin/sh\necho $$ > ' + str(pidfile) + '\nexec /bin/sleep 60\n')
    result = subprocess.run([binary, '--check-antigravity-fixture', str(fake), '0.5'],
                            capture_output=True, timeout=5)
    assert result.returncode == 1
    try:
        os.kill(int(pidfile.read_text()), 0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError('timed-out CLI process was not reaped')
    print('PASS: statusLine payload capture, metadata exclusion, CLI cleanup on success and timeout')

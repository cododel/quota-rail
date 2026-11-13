import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys

helper = Path(__file__).resolve().parent.parent / 'agy-quota.py'
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
    result = subprocess.run([sys.executable, str(helper), str(fake)], capture_output=True, timeout=10, check=True)
    data=json.loads(result.stdout)
    assert sorted(data) == ['3p-5h','3p-weekly','gemini-5h','gemini-weekly']
    assert b'private' not in result.stdout
    pid=int(pidfile.read_text())
    try:
        os.kill(pid,0)
    except ProcessLookupError:
        pass
    else:
        raise AssertionError('CLI process was not reaped')
    print('PASS: statusLine payload capture, metadata exclusion, CLI cleanup')

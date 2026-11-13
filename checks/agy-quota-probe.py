import os, pty, subprocess, tempfile, time, json, sys, select, signal, shlex
if len(sys.argv)>1 and sys.argv[1]=='capture':
    data=json.load(sys.stdin)
    with open(sys.argv[2], 'w') as f: json.dump({'quota': data.get('quota'), 'state':data.get('agent_state')},f)
    sys.exit()
with tempfile.TemporaryDirectory() as d:
    out=d+'/quota.json'
    command=shlex.join(['/usr/bin/python3',os.path.abspath(__file__),'capture',out])
    master,slave=pty.openpty()
    p=subprocess.Popen([os.path.expanduser('~/.local/bin/agy'),'--settings',json.dumps({'statusLine':{'type':'command','command':command,'enabled':True}})],stdin=slave,stdout=slave,stderr=slave,cwd=d,start_new_session=True)
    os.close(slave)
    try:
        deadline=time.monotonic()+35
        while time.monotonic()<deadline and p.poll() is None:
            if select.select([master],[],[],.2)[0]:
                try: os.read(master,65536)
                except OSError: break
            if os.path.exists(out):
                try: data=json.load(open(out))
                except (ValueError,OSError): continue
                if data.get('quota'):
                    print(json.dumps(data));break
        else: print('No quota received')
    finally:
        if p.poll() is None:
            os.killpg(p.pid,signal.SIGTERM)
            try:p.wait(timeout=3)
            except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
        os.close(master)

"""Run demand SQL against a new disposable local PostgreSQL cluster; never loads .env."""
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
binary = Path('C:/Program Files/PostgreSQL/18/bin')
folder = Path(tempfile.mkdtemp(prefix='demand-sql-', dir=root / '.test_local_scope'))
with socket.socket() as probe:
    probe.bind(('127.0.0.1', 0))
    port = probe.getsockname()[1]

def run(name, *args, **kwargs):
    with (folder / 'commands.log').open('ab') as log:
        return subprocess.run([str(binary / (name+'.exe')), *map(str,args)], check=True,
                              creationflags=subprocess.CREATE_NO_WINDOW, stdout=log, stderr=log,
                              timeout=120, **kwargs)

started = False
try:
    run('initdb', '-D', folder/'data', '-U', 'postgres', '-A', 'trust', '--no-locale', '-E', 'UTF8')
    run('pg_ctl', '-D', folder/'data', '-l', folder/'server.log', '-o', f'-h 127.0.0.1 -p {port}', '-w', 'start')
    started = True
    run('createdb', '-h','127.0.0.1','-p',port,'-U','postgres','demand_test')
    env = dict(os.environ, DEMAND_TEST_DSN=f'postgresql+psycopg2://postgres@127.0.0.1:{port}/demand_test')
    result = subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_demand_postgres.py'], cwd=root, env=env)
    if result.returncode:
        raise SystemExit(result.returncode)
finally:
    if started:
        run('pg_ctl','-D',folder/'data','-m','fast','-w','stop')

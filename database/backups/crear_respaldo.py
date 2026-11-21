"""Full encrypted local PostgreSQL backups, schemas and private document archive.

Run from any directory. Keys remain in .local. --verify-restore restores into
new uniquely named temporary databases, never over the application databases.
"""
import argparse
from datetime import datetime,timezone,timedelta
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from uuid import uuid4
import zipfile
from contextlib import contextmanager

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'.local/backup-tools'))
from cryptography.fernet import Fernet
from dotenv import load_dotenv
from sqlalchemy import create_engine,text
from sqlalchemy.engine import make_url


def run(binary,args,env,*,data=None):
    result=subprocess.run([str(binary),*args],input=data,env=env,capture_output=True,
        creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
    if result.returncode:
        (ROOT/'.local/backup-error.log').write_bytes(result.stderr)
        raise RuntimeError('La herramienta PostgreSQL falló; revisar .local/backup-error.log.')
    return result.stdout


def write_verified(path,data):
    with path.open('xb') as stream:
        stream.write(data);stream.flush();os.fsync(stream.fileno())
    if path.read_bytes()!=data:raise RuntimeError('El archivo escrito no coincide con el verificado.')


def restore_check(dump,url,bin_folder,args,env):
    name='verify_backup_'+uuid4().hex[:12]
    assert re.fullmatch(r'verify_backup_[0-9a-f]{12}',name) and name not in ('barbarito','fact_api_demo')
    admin=create_engine(url.set(database='postgres'),isolation_level='AUTOCOMMIT')
    created=False
    try:
        with admin.connect() as connection:connection.exec_driver_sql('CREATE DATABASE "'+name+'"')
        created=True
        run(bin_folder/'pg_restore.exe',[*args,'--dbname',name,'--no-owner','--no-acl','--exit-on-error'],env,data=dump)
        restored=create_engine(url.set(database=name))
        try:
            with restored.connect() as connection:
                tables=connection.execute(text("SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'")).scalar_one()
        finally:restored.dispose()
        return {'restauracion':'Correcta en base temporal independiente','tablas_restauradas':tables}
    finally:
        if created:
            with admin.connect() as connection:connection.exec_driver_sql('DROP DATABASE "'+name+'" WITH (FORCE)')
        admin.dispose()


@contextmanager
def backup_lock():
    """Only one publisher may prepare a generation in this workspace."""
    path=ROOT/'.local/backup.lock'
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('a+b') as stream:
        if stream.tell()==0:stream.write(b'0');stream.flush()
        stream.seek(0)
        if os.name=='nt':
            import msvcrt
            msvcrt.locking(stream.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(stream.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:yield
        finally:
            stream.seek(0)
            if os.name=='nt':msvcrt.locking(stream.fileno(),msvcrt.LK_UNLCK,1)
            else:fcntl.flock(stream.fileno(),fcntl.LOCK_UN)


def main_locked():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify-restore',action='store_true')
    options=parser.parse_args()
    load_dotenv(ROOT/'backend/.env')
    url=make_url(os.environ.get('DATABASE_MIGRATION_URL') or os.environ['DATABASE_URL'])
    if url.host not in ('localhost','127.0.0.1','::1') or url.database!='barbarito':
        raise SystemExit('Solo se permite la conexión local barbarito.')
    key=ROOT/'.local/database-backup.key'
    if not key.is_file():raise SystemExit('Falta la clave privada existente. No crear otra para respaldos anteriores.')
    cipher=Fernet(key.read_bytes().strip())
    now=datetime.now(timezone(timedelta(hours=-5)))
    generation=now.strftime('%Y-%m-%d-%H%M%S')+'-'+uuid4().hex[:8]
    folder=ROOT/'database/backups'
    stage=ROOT/'.local/backup-staging'/generation
    stage.mkdir(parents=True,exist_ok=False)
    publications=[]
    binaries=Path(os.getenv('POSTGRES_BIN','C:/Program Files/PostgreSQL/18/bin'))
    env={**os.environ,'PGPASSWORD':url.password or ''}
    args=['-h',url.host,'-p',str(url.port or 5432),'-U',url.username,'--no-password']
    manifest={'fecha':now.isoformat(),'generacion':generation,'formato':'PostgreSQL custom + documentos ZIP, cifrados con Fernet',
        'clave':'Exclusivamente .local/database-backup.key; no publicada','bases':[]}
    for database in ('barbarito','fact_api_demo'):
        dump=run(binaries/'pg_dump.exe',[*args,'-Fc','--no-owner','--no-acl',database],env)
        run(binaries/'pg_restore.exe',['--file',os.devnull],env,data=dump)
        encrypted=cipher.encrypt(dump)
        if cipher.decrypt(encrypted)!=dump:raise RuntimeError('No coincide el descifrado.')
        name=f'{database.replace("_","-")}-completo-{generation}.dump.enc'
        temporary=stage/name;write_verified(temporary,encrypted)
        publications.append((temporary,folder/name))
        schema=run(binaries/'pg_dump.exe',[*args,'--schema-only','--no-owner','--no-acl',database],env)
        schema_path=ROOT/'database'/('schema.sql' if database=='barbarito' else 'fact_api_schema.sql')
        schema=schema.decode('utf-8').replace('\r\n','\n').rstrip().encode('utf-8')+b'\n'
        temporary_schema=stage/(database+'-schema.sql');temporary_schema.write_bytes(schema)
        publications.append((temporary_schema,schema_path))
        metadata={'base':database,'archivo':name,'bytes_cifrados':len(encrypted),
            'sha256_cifrado':hashlib.sha256(encrypted).hexdigest(),'lectura_pg_restore':'Correcta',
            'descifrado':'Comparado byte a byte','roles_y_privilegios':False}
        if options.verify_restore:metadata.update(restore_check(dump,url,binaries,args,env))
        manifest['bases'].append(metadata)
        print('Respaldo cifrado verificado:',database,flush=True)
    app_data=Path(os.getenv('APP_DATA_DIR') or ROOT/'backend/instance')
    if not app_data.is_absolute():app_data=ROOT/'backend'/app_data
    storage=Path(os.getenv('FACT_API_DOCUMENTS_DIR') or app_data/'fact_api_documents')
    if not storage.is_absolute():storage=ROOT/'backend'/storage
    if (os.getenv('FACT_API_DOCUMENTS_DIR') or os.getenv('APP_DATA_DIR')) and not storage.is_dir():
        raise RuntimeError('La carpeta configurada de documentos no existe; no publicar un respaldo incompleto.')
    roots={'barbarito_documents':storage,'fact_api_private':ROOT/'services/fact_api/storage/app/private/barbarito'}
    stream=io.BytesIO();count=0
    with zipfile.ZipFile(stream,'w',compression=zipfile.ZIP_DEFLATED) as archive:
        for prefix,source in roots.items():
            if not source.exists():continue
            for file in sorted(source.rglob('*')):
                if file.is_file() and file.suffix.lower() in ('.pdf','.xml','.zip'):
                    archive.write(file,(Path(prefix)/file.relative_to(source)).as_posix());count+=1
    plain=stream.getvalue()
    with zipfile.ZipFile(io.BytesIO(plain)) as archive:
        if archive.testzip() is not None:raise RuntimeError('Archivo de documentos no válido.')
    encrypted=cipher.encrypt(plain)
    assert cipher.decrypt(encrypted)==plain
    name=f'fact-api-documentos-{generation}.zip.enc'
    temporary=stage/name;write_verified(temporary,encrypted);publications.append((temporary,folder/name))
    manifest['documentos']={'archivo':name,'archivos':count,'bytes_cifrados':len(encrypted),
        'sha256_cifrado':hashlib.sha256(encrypted).hexdigest(),'verificacion':'ZIP CRC y descifrado correctos'}
    manifest['archivo']=manifest['bases'][0]['archivo']
    pointer=stage/'respaldo.json'
    write_verified(pointer,(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n').encode())
    # Unique generation files cannot overwrite an earlier known-good set. The
    # manifest pointer is replaced atomically only after all verification succeeds.
    for source,target in publications:source.replace(target)
    pointer.replace(folder/'respaldo.json')
    print('Documentos privados cifrados:',count,flush=True)


if __name__=='__main__':
    with backup_lock():main_locked()

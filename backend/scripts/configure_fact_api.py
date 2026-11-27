"""Install local DEMO databases/config without printing secrets or altering sales."""
import base64
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys
from dotenv import load_dotenv, set_key
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

ROOT=Path(__file__).resolve().parents[2]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--queue-only',action='store_true',help='Aplicar solo las tablas/configuración de Barbarito.')
    args=parser.parse_args()
    load_dotenv(ROOT/'backend/.env')
    url=make_url(os.environ['DATABASE_MIGRATION_URL'])
    app_url=make_url(os.environ['DATABASE_URL'])
    if url.host not in ('localhost','127.0.0.1','::1') or url.database!=app_url.database or url.host!=app_url.host:
        raise SystemExit('Se requiere conexión administrativa a la misma base local.')
    service=ROOT/'services/fact_api'
    env_path=service/'.env'
    from dotenv import dotenv_values
    existing=dotenv_values(env_path) if env_path.exists() else {}
    password=existing.get('DB_PASSWORD') or secrets.token_urlsafe(32)
    token=existing.get('BARBARITO_TOKEN') or secrets.token_urlsafe(40)
    migration=(ROOT/'database/migrations/20261121_fact_api_queue.sql').read_text(encoding='utf-8')
    engine=create_engine(url)
    with engine.begin() as conn:
        conn.exec_driver_sql(migration.replace('BEGIN;','').replace('COMMIT;',''))
        scaling=(ROOT/'database/migrations/20261121_fact_api_autoscale.sql').read_text(encoding='utf-8')
        conn.exec_driver_sql(scaling.replace('BEGIN;','').replace('COMMIT;',''))
        funciones = (ROOT/'database/migrations/20261127_funciones_facturacion.sql').read_text(encoding='utf-8')
        conn.exec_driver_sql(funciones.replace('BEGIN;', '').replace('COMMIT;', ''),
                             execution_options={'no_parameters': True})
        conn.execute(text('''INSERT INTO fact_api_config
            (id_local,activo,empresa,serie_factura,serie_boleta,tasa_igv)
            SELECT id_local,true,CAST(:empresa AS jsonb),'F'||lpad(id_local::text,3,'0'),
                'B'||lpad(id_local::text,3,'0'),18 FROM local WHERE estado_registro=1 AND id_local<1000
            ON CONFLICT(id_local) DO NOTHING'''),
            {'empresa':json.dumps({'nombre':'BARBARIAN · DEMOSTRACIÓN','ruc':'00000000000'})})
    if args.queue_only:
        print('Cola y escalado automático preparados en PostgreSQL local.');return
    with create_engine(url.set(database='postgres'),isolation_level='AUTOCOMMIT').connect() as conn:
        if not conn.execute(text("SELECT 1 FROM pg_roles WHERE rolname='fact_api_demo'")).scalar():
            # Generated URL-safe password has no quote characters.
            conn.exec_driver_sql("CREATE ROLE fact_api_demo LOGIN PASSWORD '"+password+"'")
        if not conn.execute(text("SELECT 1 FROM pg_database WHERE datname='fact_api_demo'")).scalar():
            conn.exec_driver_sql('CREATE DATABASE fact_api_demo OWNER fact_api_demo')
    values={'APP_NAME':'FactApiBarbarito','APP_ENV':'local','APP_DEBUG':'false',
        'APP_KEY':existing.get('APP_KEY') or 'base64:'+base64.b64encode(secrets.token_bytes(32)).decode(),
        'APP_URL':'http://127.0.0.1:8091','LOG_CHANNEL':'single','LOG_LEVEL':'warning',
        'DB_CONNECTION':'pgsql','DB_HOST':url.host,'DB_PORT':str(url.port or 5432),
        'DB_DATABASE':'fact_api_demo','DB_USERNAME':'fact_api_demo','DB_PASSWORD':password,
        'SESSION_DRIVER':'file','CACHE_STORE':'file','QUEUE_CONNECTION':'sync',
        'BARBARITO_DEMO_ONLY':'true','BARBARITO_TOKEN':token}
    env_path.touch(exist_ok=True)
    for key,value in values.items():set_key(str(env_path),key,value)
    for key,value in {'FACT_API_URL':'http://127.0.0.1:8091','FACT_API_TOKEN':token,
                       'FACT_API_MODE':'DEMO'}.items():
        set_key(str(ROOT/'backend/.env'),key,value)
    php=ROOT/'.local/php/php.exe'
    if not php.exists():raise SystemExit('Instala PHP 8.2+; configuración y migración Barbarito preparadas.')
    ini=php.parent/'php.ini'
    data=ini.read_text(encoding='utf-8')
    if '\nextension=pdo_pgsql' not in data:
        with ini.open('a',encoding='utf-8') as stream:stream.write('\nextension=pdo_pgsql\n')
    for command in (['config:clear'],['migrate','--force']):
        result=subprocess.run([str(php),str(service/'artisan'),*command],cwd=service,
                              capture_output=True,text=True,encoding='utf-8',errors='replace')
        print(result.stdout)
        if result.returncode:
            # Laravel may include connection details in errors; save privately, do not print.
            (ROOT/'.local/fact_api_migration_error.log').write_text(result.stdout+result.stderr,encoding='utf-8')
            raise SystemExit('Revisar registro local privado de migración fact_api.')
    print('Cola PostgreSQL, configuración por locales y fact_api DEMO preparados. Sin emisión SUNAT.')


if __name__=='__main__':main()

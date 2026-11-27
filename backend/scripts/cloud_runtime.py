"""Single-container Railway runtime. Private Laravel bridge + durable workers.

No local .env, database dump, certificate or personal data is copied to production.
Only explicitly listed additive application migrations run; Laravel owns its schema.
"""
import base64
import json
import os
from pathlib import Path
import secrets
import signal
import subprocess
import sys
import time
from urllib.request import Request, urlopen

from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import DBAPIError

ROOT=Path(__file__).resolve().parents[2]
LARAVEL=ROOT/'services/fact_api'


def laravel_environment(values):
    """PHP dotenv does not support Python dotenv's single-quote escaping."""
    lines=[]
    for key,value in values.items():
        value=str(value)
        if any(ord(character)<32 and character not in '\n\r\t\f\v' for character in value):
            raise ValueError('Unsupported control character in managed Laravel settings.')
        escaped=value.replace('\\','\\\\').replace('"','\\"').replace('$','\\$')
        for original,replacement in (('\n','\\n'),('\r','\\r'),('\t','\\t'),('\f','\\f'),('\v','\\v')):
            escaped=escaped.replace(original,replacement)
        lines.append(key+'="'+escaped+'"')
    return '\n'.join(lines)+'\n'


def prepare_settings(env, data_root):
    if env.get('FACT_API_MODE','DEMO')!='DEMO':
        raise ValueError('Bundled runtime only supports DEMO.')
    url=make_url(env.get('DATABASE_URL','').replace('postgres://','postgresql://',1))
    if url.get_backend_name()!='postgresql' or not url.database or not url.host:
        raise ValueError('A PostgreSQL DATABASE_URL is required.')
    folder=Path(data_root).resolve()/'fact_api'
    folder.mkdir(parents=True,exist_ok=True)
    path=folder/'runtime-secrets.json'
    if path.exists():
        try:
            stored=json.loads(path.read_text(encoding='utf-8'))
            if len(stored['token'])<32 or not stored['app_key'].startswith('base64:'):
                raise ValueError()
        except (ValueError,KeyError,TypeError,AttributeError):
            raise ValueError('Persistent runtime secrets are invalid; they were not replaced.') from None
    else:
        stored={'token':secrets.token_urlsafe(40),'app_key':'base64:'+base64.b64encode(secrets.token_bytes(32)).decode()}
        descriptor=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        with os.fdopen(descriptor,'w',encoding='utf-8') as stream:
            json.dump(stored,stream);stream.flush();os.fsync(stream.fileno())
    token=(env.get('FACT_API_TOKEN') or stored['token']).strip()
    # Railway values sometimes contain pasted .env quotes. Laravel's env()
    # removes these wrappers; Python must use the same actual Bearer token.
    while len(token)>=2 and token[0] in ('"',"'") and token[-1]==token[0]:
        token=token[1:-1]
    if len(token)<32:raise ValueError('FACT_API_TOKEN must have at least 32 characters.')
    env['FACT_API_TOKEN']=token
    env['FACT_API_URL']='http://127.0.0.1:8091'
    env['FACT_API_MODE']='DEMO'
    env.setdefault('FACT_API_DOCUMENTS_DIR',str(Path(data_root).resolve()/'fact_api_documents'))
    env.setdefault('FACT_API_MIN_WORKERS','1')
    env.setdefault('FACT_API_MAX_WORKERS','2')
    storage=folder/'laravel_storage'
    values={'APP_NAME':'FactApiBarbarito','APP_ENV':'production','APP_DEBUG':'false',
        'APP_KEY':stored['app_key'],'APP_URL':'http://127.0.0.1:8091',
        'DB_CONNECTION':'pgsql','DB_HOST':url.host,'DB_PORT':str(url.port or 5432),
        'DB_DATABASE':url.database,'DB_USERNAME':url.username or '', 'DB_PASSWORD':url.password or '',
        'DB_SEARCH_PATH':'fact_api','DB_SSLMODE':url.query.get('sslmode','prefer'),
        'SESSION_DRIVER':'file','CACHE_STORE':'file','QUEUE_CONNECTION':'sync',
        'LOG_CHANNEL':'single','LOG_LEVEL':'error','LARAVEL_STORAGE_PATH':str(storage),
        'BARBARITO_DEMO_ONLY':'true','BARBARITO_TOKEN':token}
    return {'laravel':values,'storage':storage,'data':folder,'database':url}


def migrate_application(url):
    # Public business tables and private Laravel schema have independent namespaces.
    engine=create_engine(url)
    phase = 'connect'
    try:
        with engine.begin() as connection:
            phase = 'migration lock'
            connection.execute(text("SELECT pg_advisory_xact_lock(hashtext('barbarito-cloud-fact-setup'))"))
            connection.exec_driver_sql('SET LOCAL search_path TO public')
            phase = 'fact_api schema'
            connection.exec_driver_sql('CREATE SCHEMA IF NOT EXISTS fact_api')
            phase = 'unit catalog check'
            existe_catalogo = connection.execute(text("SELECT to_regclass('public.unidad_medida')")).scalar()
            if not existe_catalogo or not connection.execute(text(
                'SELECT EXISTS (SELECT 1 FROM public.unidad_medida)'
            )).scalar():
                phase = '20261010_unidades_unece.sql'
                migration = (ROOT/'database/migrations/20261010_unidades_unece.sql').read_text(encoding='utf-8')
                connection.exec_driver_sql(migration.replace('BEGIN;', '').replace('COMMIT;', ''), execution_options={'no_parameters': True})
            for name in ('20261118_clientes.sql','20261121_fact_api_queue.sql','20261121_fact_api_autoscale.sql','20261124_ai_quotas.sql', '20261126_motivos_recepcion.sql', '20261126_motivos_movimiento.sql', '20261126_estandar_unidades.sql', '20261117_medidas_menaje.sql', '20261117_dimensiones_rectangulares_menaje.sql', '20261126_unidades_menaje.sql', '20261127_acceso_perfil_locales.sql', '20261127_funciones_alcance_local.sql', '20261127_capacidades_perfil.sql', '20261127_configuracion_operativa.sql', '20261127_funciones_autenticacion.sql', '20261127_funciones_auditoria.sql', '20261127_acciones_permiso.sql', '20261127_funciones_stock_local.sql', '20261127_funcion_categorias_carta.sql', '20261127_funciones_medidas_menaje.sql', '20261127_funciones_editor_presentaciones.sql', '20261127_reglas_sesion_perfil.sql', '20261127_funciones_admin_categorias_carta.sql', '20261127_reglas_medidas_menaje.sql', '20261127_funciones_carta_restantes.sql', '20261127_funciones_catalogos_repositorio.sql', '20261127_funciones_catalogos_stock.sql', '20261127_funciones_catalogos_eliminacion.sql', '20261127_funciones_clientes.sql', '20261127_clientes_contacto.sql', '20261127_clientes_compartidos.sql', '20261127_clientes_direccion.sql', '20261127_funciones_compras.sql', '20261127_funciones_facturacion.sql', '20261127_funcion_health.sql', '20261127_funciones_inventarios_consultas.sql', '20261127_funciones_inventarios.sql', '20261127_funciones_movimientos.sql', '20261127_funciones_produccion.sql', '20261127_funciones_promociones.sql', '20261127_funciones_recepciones.sql', '20261127_funciones_recetas.sql', '20261127_funciones_salon.sql', '20261127_funciones_usuarios.sql', '20261127_integraciones_entrada.sql', '20261127_integraciones_claves.sql', '20261127_integraciones_claves_por_programa.sql', '20261127_integraciones_permisos_historial.sql', '20261127_integraciones_trabajos.sql'):
                phase = name
                migration=(ROOT/'database/migrations'/name).read_text(encoding='utf-8')
                connection.exec_driver_sql(migration.replace('BEGIN;','').replace('COMMIT;',''), execution_options={'no_parameters': True})
            phase = 'unit catalog initialization check'
            if not connection.execute(text("SELECT to_regclass('public.unidad_medida_catalogo_inicializado')")).scalar():
                phase = '20261126_catalogo_unidades.sql'
                migration = (ROOT/'database/migrations/20261126_catalogo_unidades.sql').read_text(encoding='utf-8')
                connection.exec_driver_sql(migration.replace('BEGIN;', '').replace('COMMIT;', ''), execution_options={'no_parameters': True})
            phase = '20261127_funciones_catalogos.sql'
            funciones = (ROOT/'database/migrations/20261127_funciones_catalogos.sql').read_text(encoding='utf-8')
            connection.exec_driver_sql(funciones.replace('BEGIN;', '').replace('COMMIT;', ''), execution_options={'no_parameters': True})
            phase = 'fact_api local defaults'
            connection.execute(text('''INSERT INTO fact_api_config
                (id_local,activo,empresa,serie_factura,serie_boleta,tasa_igv)
                SELECT id_local,true,CAST(:company AS jsonb),'F'||lpad(id_local::text,3,'0'),
                    'B'||lpad(id_local::text,3,'0'),18 FROM local
                WHERE estado_registro=1 AND id_local BETWEEN 1 AND 999
                ON CONFLICT(id_local) DO NOTHING'''),
                {'company':json.dumps({'nombre':'BARBARIAN','ruc':'00000000000'})})
    except DBAPIError as error:
        sqlstate = getattr(error.orig, 'pgcode', None) or getattr(error.orig, 'sqlstate', None)
        if not isinstance(sqlstate, str) or len(sqlstate) != 5 or not sqlstate.isascii() or not sqlstate.isalnum():
            sqlstate = 'unknown'
        print(f'PostgreSQL startup failed at {phase} (SQLSTATE {sqlstate}).', file=sys.stderr, flush=True)
        raise
    finally:
        engine.dispose()


def configure_laravel(settings):
    storage=settings['storage']
    for name in ('app/private','framework/cache/data','framework/sessions','framework/views','logs'):
        (storage/name).mkdir(parents=True,exist_ok=True)
    env_path=LARAVEL/'.env'
    # This file is generated entirely from managed settings, never edited in place.
    content=laravel_environment(settings['laravel'])
    descriptor=os.open(env_path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(descriptor,'w',encoding='utf-8',newline='\n') as stream:
        stream.write(content)
    # PHP-FPM runs as www-data, while the process supervisor and Flask run as root.
    import pwd
    account=pwd.getpwnam('www-data')
    os.chown(env_path,account.pw_uid,account.pw_gid);os.chmod(env_path,0o600)
    for directory in (storage,LARAVEL/'bootstrap/cache'):
        os.chown(directory,account.pw_uid,account.pw_gid)
        for path in directory.rglob('*'):os.chown(path,account.pw_uid,account.pw_gid)
    # Clear inherited Railway DB_URL etc: only the selected Laravel settings apply.
    php_env={key:value for key,value in os.environ.items() if not key.startswith(('DB_','DATABASE_','APP_','BARBARITO_'))}
    php_env.update(settings['laravel'])
    for command in ('package:discover','config:clear','migrate'):
        arguments=['php','artisan',command,'--no-interaction']
        if command=='migrate':arguments.append('--force')
        result=subprocess.run(arguments,cwd=LARAVEL,env=php_env,capture_output=True,timeout=150)
        if result.returncode:
            log=settings['data']/'migration-error.log'
            log.write_bytes(result.stdout+b'\n'+result.stderr);os.chmod(log,0o600)
            raise RuntimeError('Laravel setup failed; see private migration-error.log.')
    # Artisan may have created cache/log files as root during the migration.
    for directory in (storage,LARAVEL/'bootstrap/cache'):
        for path in directory.rglob('*'):os.chown(path,account.pw_uid,account.pw_gid)


def wait_bridge(token,processes):
    for _ in range(60):
        if any(process.poll() is not None for process in processes):raise RuntimeError('Private PHP bridge exited.')
        try:
            request=Request('http://127.0.0.1:8091/api/barbarito/health',headers={'Authorization':'Bearer '+token})
            with urlopen(request,timeout=2) as response:
                if json.load(response).get('modo')=='DEMO':return
        except (OSError,ValueError):pass
        time.sleep(.5)
    raise RuntimeError('Private PHP bridge did not become ready.')


def main():
    if os.environ.get('FACT_API_BUNDLED')!='1':
        os.execvp('gunicorn',['gunicorn','--config','gunicorn.conf.py','wsgi:app'])
    data=Path(os.environ.get('APP_DATA_DIR','/data')).resolve()
    settings=prepare_settings(os.environ,data)
    print('fact_api: preparing isolated DEMO storage and migrations.',flush=True)
    migrate_application(settings['database'])
    print('fact_api: application migrations and local configurations ready.',flush=True)
    configure_laravel(settings)
    print('fact_api: native Laravel migrations ready in fact_api schema.',flush=True)
    children=[];stopping=False;worker=None;web=None
    def stop(*_):
        nonlocal stopping
        stopping=True
    signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
    try:
        children.append(subprocess.Popen(['php-fpm8.2','--nodaemonize','--fpm-config',str(ROOT/'deploy/php-fpm.conf')]))
        children.append(subprocess.Popen(['nginx','-c',str(ROOT/'deploy/fact-api-nginx.conf'),'-g','daemon off;']))
        wait_bridge(os.environ['FACT_API_TOKEN'],children)
        worker=subprocess.Popen([sys.executable,str(ROOT/'backend/scripts/run_fact_api_supervisor.py'),'--wait-for-leader'])
        children.append(worker)
        children.append(subprocess.Popen([sys.executable, str(ROOT/'backend/scripts/run_integraciones_worker.py')]))
        web=subprocess.Popen(['gunicorn','--config','gunicorn.conf.py','wsgi:app'])
        children.append(web)
        print('fact_api: private DEMO bridge ready; durable workers and public web started.',flush=True)
        while not stopping:
            if any(process.poll() is not None for process in children):raise RuntimeError('A runtime child exited; restart required.')
            time.sleep(.5)
    finally:
        # Stop accepting public work first; keep the private bridge up for workers.
        if web and web.poll() is None:web.terminate()
        if worker and worker.poll() is None:
            worker.terminate()
            try:worker.wait(timeout=65)
            except subprocess.TimeoutExpired:worker.kill()
        for process in reversed(children):
            if process.poll() is None:process.terminate()
        for process in children:
            try:process.wait(timeout=35 if process is web else 10)
            except subprocess.TimeoutExpired:process.kill()


if __name__=='__main__':
    try:main()
    except Exception as error:
        # Never echo a DB URL, provider response or credentials into public deploy logs.
        print('fact_api startup failed ('+type(error).__name__+'); inspect private runtime diagnostics.',file=sys.stderr)
        sys.exit(1)

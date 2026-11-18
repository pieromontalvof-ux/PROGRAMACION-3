"""Apply the customer directory migration to an explicitly local database."""
import os
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url

def main():
    root=Path(__file__).resolve().parents[1]
    load_dotenv(root/'.env')
    value=os.getenv('DATABASE_MIGRATION_URL','')
    if not value:raise SystemExit('Configura DATABASE_MIGRATION_URL con permisos de migracion.')
    url=make_url(value)
    if url.host not in ('127.0.0.1','localhost','::1'):
        raise SystemExit('Este comando solo admite la base local.')
    engine=create_engine(url)
    try:
        with engine.begin() as connection:
            for filename in ('20261118_clientes.sql',):
                sql=(root.parent/'database'/'migrations'/filename).read_text(encoding='utf-8')
                # Keep both migrations in one transaction.
                sql=sql.replace('BEGIN;','').replace('COMMIT;','')
                connection.exec_driver_sql(sql)
            role=connection.execute(__import__('sqlalchemy').text('SELECT current_user')).scalar_one()
            app_url=make_url(os.environ.get('DATABASE_URL',value))
            if app_url.database!=url.database or app_url.host!=url.host:
                raise RuntimeError('La conexion de migracion debe apuntar a la misma base local.')
            app_role=app_url.username
            if app_role and app_role!=role:
                quoted=connection.dialect.identifier_preparer.quote(app_role)
                connection.exec_driver_sql(f'GRANT SELECT,INSERT,UPDATE ON cliente_comercial TO {quoted}')
        print('Directorio de clientes listo.')
    except Exception:
        raise SystemExit('No se aplico la migracion: revisa los permisos de DATABASE_MIGRATION_URL.') from None
    finally:engine.dispose()

if __name__=='__main__':main()

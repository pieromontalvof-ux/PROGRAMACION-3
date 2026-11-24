"""Apply the additive token ledger, without printing database credentials."""
import os
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url


def main():
    root = Path(__file__).resolve().parents[2]
    load_dotenv(root / 'backend/.env')
    application = make_url(os.environ['DATABASE_URL'])
    migration = make_url(os.getenv('DATABASE_MIGRATION_URL') or os.environ['DATABASE_URL'])
    if (application.host, application.port, application.database) != (migration.host, migration.port, migration.database):
        raise ValueError('La conexión administrativa debe apuntar a la misma base de la aplicación.')
    engine = create_engine(migration)
    sql = (root / 'database/migrations/20261124_ai_quotas.sql').read_text(encoding='utf-8')
    with engine.begin() as connection:
        connection.exec_driver_sql(sql.replace('BEGIN;', '').replace('COMMIT;', ''))
        role = engine.dialect.identifier_preparer.quote(application.username)
        connection.exec_driver_sql(f'GRANT SELECT, INSERT, UPDATE ON public.ia_cuota_config, public.ia_cuota_usuario, public.ia_consumo, public.ia_cuota_auditoria TO {role}')
        connection.exec_driver_sql(f'GRANT DELETE ON public.ia_cuota_usuario TO {role}')
        connection.exec_driver_sql(f'GRANT USAGE ON SEQUENCE public.ia_cuota_auditoria_id_seq TO {role}')
    engine.dispose()
    print('Migración de cuotas aplicada. Límites conservados; instalación inicial desactivada.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('No se pudo aplicar la migración (' + type(error).__name__ + '). Revisa la conexión administrativa y sus permisos.')
        raise SystemExit(1)

"""Apply supplier invoice fields to the configured local database."""
import os
from pathlib import Path
from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.engine import make_url


def main():
    root = Path(__file__).resolve().parents[1]
    load_dotenv(root / '.env')
    value = os.getenv('DATABASE_MIGRATION_URL', '')
    if not value:
        raise SystemExit('Configura DATABASE_MIGRATION_URL.')
    url = make_url(value)
    app_url = make_url(os.environ['DATABASE_URL'])
    if url.host not in ('localhost', '127.0.0.1', '::1') or app_url.database != url.database or app_url.host != url.host:
        raise SystemExit('Las conexiones deben apuntar a la misma base local.')
    engine = create_engine(url)
    try:
        with engine.begin() as conn:
            sql = (root.parent / 'database/migrations/20261118_facturas_proveedores.sql').read_text(encoding='utf-8')
            conn.exec_driver_sql(sql.replace('BEGIN;', '').replace('COMMIT;', ''))
        print('Datos de proveedores y facturas de recepción preparados.')
    except Exception:
        raise SystemExit('No se aplicó la migración. Revisa la conexión administrativa local.') from None
    finally:
        engine.dispose()


if __name__ == '__main__':
    main()

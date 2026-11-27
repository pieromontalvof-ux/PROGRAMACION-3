"""Read-only status check. --examples queues one existing sale/purchase per store."""
import argparse
from pathlib import Path
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import create_app
from app.core.extensions import db
from sqlalchemy import func, select
from app.modules.facturacion.service import enqueue_source
from app.modules.facturacion.transport import call


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--examples',action='store_true');args=parser.parse_args()
    print('Servicio:',call('health'))
    with create_app().app_context():
        if args.examples:
            sources=db.session.execute(select(func.public.facturacion_fuentes_ejemplo().table_valued('origin', 'id_local', 'source'))).mappings().all()
            for row in sources:
                identity=enqueue_source(row['origin'],row['source'],row['id_local'])
                print('Encolada:',row['origin'],'local',row['id_local'],'operación',identity)
            db.session.commit()
        rows=db.session.execute(select(func.public.facturacion_conteo_estados().table_valued('id_local', 'origen', 'estado', 'cantidad'))).mappings().all()
        for row in rows:print(dict(row))


if __name__=='__main__':main()

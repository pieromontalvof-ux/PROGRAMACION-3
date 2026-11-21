"""Read-only status check. --examples queues one existing sale/purchase per store."""
import argparse
from pathlib import Path
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import create_app
from app.core.extensions import db
from sqlalchemy import text
from app.modules.facturacion.service import enqueue_source
from app.modules.facturacion.transport import call


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--examples',action='store_true');args=parser.parse_args()
    print('Servicio:',call('health'))
    with create_app().app_context():
        if args.examples:
            sources=db.session.execute(text('''SELECT 'VENTA' AS origin,id_local,max(id_cobro) AS source
                FROM salon_cobro WHERE NOT(comprobante ? 'anulacion') GROUP BY id_local
                UNION ALL SELECT 'COMPRA',o.id_local,max(f.id_factura_recepcion)
                FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
                WHERE datos_factura IS NOT NULL GROUP BY o.id_local''')).mappings().all()
            for row in sources:
                identity=enqueue_source(row['origin'],row['source'],row['id_local'])
                print('Encolada:',row['origin'],'local',row['id_local'],'operación',identity)
            db.session.commit()
        rows=db.session.execute(text('SELECT id_local,origen,estado,count(*) AS cantidad FROM fact_api_operacion GROUP BY id_local,origen,estado ORDER BY 1,2')).mappings().all()
        for row in rows:print(dict(row))


if __name__=='__main__':main()

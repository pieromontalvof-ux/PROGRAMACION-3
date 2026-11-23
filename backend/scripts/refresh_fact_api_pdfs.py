"""Refresh only completed sales' PDF representations, retaining number/source/UUID.

Default is a count-only dry run; --apply downloads the current native templates.
Historical files remain private on disk; no charge or native document is created.
"""
import argparse
from pathlib import Path
import sys
from uuid import uuid4
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from app import create_app
from app.core.extensions import db
from sqlalchemy import text
from app.modules.facturacion.transport import call
from app.modules.facturacion.worker import persist_pdf


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    with create_app().app_context():
        jobs=[dict(r) for r in db.session.execute(text("""SELECT o.* FROM fact_api_operacion o
            JOIN fact_api_documento d USING(id_operacion)
            WHERE o.origen='VENTA' AND o.estado='COMPLETADO' AND NOT o.obsoleto
            ORDER BY o.creado_en""")).mappings()]
        db.session.commit()
        print('Ventas con PDF disponibles:',len(jobs),flush=True)
        if not args.apply:return
        if call('health').get('modo')!='DEMO':raise RuntimeError('Se requiere DEMO.')
        for job in jobs:
            identity=str(job['id_operacion'])
            # A unique immutable directory for this representation, never overwrite old bytes.
            job['lease_token']=str(uuid4())
            files=[persist_pdf(job,fmt,call(f'documents/{identity}/pdf?format={fmt}',binary=True))
                   for fmt in ('A4','80mm')]
            eligible=db.session.execute(text("""SELECT id_operacion FROM fact_api_operacion
                WHERE id_operacion=:id AND estado='COMPLETADO' AND NOT obsoleto FOR UPDATE"""),{'id':identity}).scalar()
            if not eligible:
                db.session.rollback();continue
            for file in files:
                db.session.execute(text("""UPDATE fact_api_archivo SET ruta=:path,sha256=:hash,bytes=:size
                    WHERE id_documento=:id AND formato=:format"""),{'id':identity,**file})
            db.session.commit()
            print('Actualizada representación:',identity,flush=True)


if __name__=='__main__':main()

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
from sqlalchemy import Uuid, bindparam, cast, func, select
from app.modules.facturacion.repository import nombre_local
from app.modules.facturacion.transport import call
from app.modules.facturacion.worker import persist_pdf


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    with create_app().app_context():
        jobs=[dict(r) for r in db.session.execute(select(func.public.facturacion_ventas_completadas_pdf().table_valued('id_operacion', 'id_local', 'origen', 'id_origen', 'version', 'payload', 'payload_hash', 'estado', 'intentos', 'max_intentos', 'obsoleto', 'disponible_en', 'lease_hasta', 'lease_token', 'ultimo_http', 'ultimo_error', 'creado_en', 'actualizado_en'))).mappings()]
        db.session.commit()
        print('Ventas con PDF disponibles:',len(jobs),flush=True)
        if not args.apply:return
        if call('health').get('modo')!='DEMO':raise RuntimeError('Se requiere DEMO.')
        for job in jobs:
            identity=str(job['id_operacion'])
            # A unique immutable directory for this representation, never overwrite old bytes.
            job['lease_token']=str(uuid4())
            job['nombre_local']=nombre_local(job['id_local'])
            db.session.rollback()
            files=[persist_pdf(job,fmt,call(f'documents/{identity}/pdf?format={fmt}',binary=True))
                   for fmt in ('A4','80mm')]
            eligible=db.session.execute(select(func.public.facturacion_bloquear_pdf_actualizable(cast(bindparam('id'), Uuid))),{'id':identity}).scalar()
            if not eligible:
                db.session.rollback();continue
            for file in files:
                db.session.execute(select(func.public.facturacion_actualizar_pdf(bindparam('path'), bindparam('hash'), bindparam('size'), cast(bindparam('id'), Uuid), bindparam('format'))),{'id':identity,**file})
            db.session.commit()
            print('Actualizada representación:',identity,flush=True)


if __name__=='__main__':main()

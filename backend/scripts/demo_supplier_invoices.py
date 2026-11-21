"""Complete fictional local purchase history without duplicating existing receipts.

Read-only unless --apply. Existing DEMO/DSHI quantities and inventory are untouched.
Missing suppliers receive four small monthly examples in Sheraton. New receptions
use the normal service and therefore add their actual received quantities to stock.
Prices and tax treatments are demonstration data, never legal classifications.
"""
import argparse
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
import json
from pathlib import Path
import sys
from unittest.mock import patch
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'backend'))
from dotenv import load_dotenv
load_dotenv(ROOT / 'backend/.env')
from app import create_app
from app.core.extensions import db
from app.modules.recepciones.invoices import calcular_factura
from app.modules.recepciones.service import registrar_recepcion
from flask import g
from sqlalchemy import text
TAG = 'DEMO-FACTURAS-PROVEEDORES-V1'


def rows(sql, **params):
    return [dict(r) for r in db.session.execute(text(sql), params).mappings()]


def ruc_ejemplo(identidad):
    prefix=f'2099{identidad:06d}'
    digit=11-sum(int(a)*b for a,b in zip(prefix,[5,4,3,2,7,6,5,4,3,2]))%11
    return prefix+str(0 if digit==10 else 1 if digit==11 else digit)


def amounts(products, day):
    lines = []
    for i, p in enumerate(products):
        # Synthetic examples of all treatments; not a claim about this product.
        tipo = 'GRAVADO'
        lines.append(dict(id_producto=p['id_producto'], cantidad_facturada=float(p['cantidad_recibida']),
                          precio_unitario=round(2.5 + (p['id_producto'] % 23) * 1.15, 2), descuento=0,
                          afectacion_igv=tipo, igv_porcentaje=18 if tipo == 'GRAVADO' else 0))
    return dict(fecha_emision=day.isoformat(), moneda='PEN', lineas=lines)


def main(apply=False):
    with create_app().test_request_context():
        if db.engine.url.host not in ('localhost', '127.0.0.1', '::1'):
            raise RuntimeError('Solo se permite la base local.')
        db.session.execute(text("SELECT pg_advisory_xact_lock(hashtext(:tag))"), {'tag': TAG})
        providers = rows('SELECT id_proveedor,nombre,datos_comerciales FROM proveedor ORDER BY id_proveedor')
        invoices = rows("""SELECT f.*,o.id_local FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra)
                           WHERE f.datos_factura IS NULL AND (f.numero_factura LIKE 'DEMO-%' OR f.numero_factura LIKE 'DSHI-%')
                           ORDER BY f.id_factura_recepcion""")
        missing = providers
        print(f'Recepciones ficticias por completar: {len(invoices)}; proveedores a revisar: {len(providers)}.')
        if not apply:
            db.session.rollback(); return
        user = rows('SELECT id_usuario FROM usuario WHERE estado_registro=1 ORDER BY id_usuario LIMIT 1')[0]['id_usuario']
        by_id = {}
        for p in providers:
            data = dict(p['datos_comerciales'] or {})
            for k,v in dict(ruc=ruc_ejemplo(p['id_proveedor']), razon_social=p['nombre'], nombre_comercial=p['nombre'], direccion=f"Av. Los Industriales {150+p['id_proveedor']*23}, Lima",
                            contacto='Área comercial', email=f"proveedor{p['id_proveedor']}@example.invalid").items():
                if not data.get(k): data[k] = v
            db.session.execute(text('UPDATE proveedor SET datos_comerciales=CAST(:d AS jsonb) WHERE id_proveedor=:id'), {'id':p['id_proveedor'],'d':json.dumps(data)})
            by_id[p['id_proveedor']] = {'nombre':p['nombre'], **data}
        for f in invoices:
            products = rows('''SELECT d.id_producto,d.cantidad_recibida,p.nombre,p.codigo,p.unidad
                                FROM factura_recepcion_detalle d JOIN producto p USING(id_producto)
                                WHERE d.id_factura_recepcion=:id ORDER BY d.id_producto''', id=f['id_factura_recepcion'])
            if not products: raise RuntimeError('Recepción ficticia sin detalle.')
            invoice = calcular_factura(amounts(products, f['fecha_recepcion']))
            invoice.update(proveedor=by_id[f['id_proveedor']], origen=TAG, datos_ficticios=True)
            for l,p in zip(invoice['lineas'], products): l.update(nombre=p['nombre'],codigo=p['codigo'],unidad=p['unidad'])
            delivery=[dict(fecha=f['fecha_recepcion'].isoformat(),usuario=f['usuario_recepcion'],detalles=[dict(id_producto=p['id_producto'],cantidad_recibida=float(p['cantidad_recibida'])) for p in products])]
            db.session.execute(text('''UPDATE factura_recepcion SET datos_factura=CAST(:d AS jsonb),
                                       entregas=CASE WHEN entregas='[]'::jsonb THEN CAST(:e AS jsonb) ELSE entregas END
                                       WHERE id_factura_recepcion=:id'''), {'id':f['id_factura_recepcion'],'d':json.dumps(invoice),'e':json.dumps(delivery)})
        today=datetime.now(timezone(timedelta(hours=-5))).date()
        g.local_operativo=rows("SELECT id_local FROM local WHERE lower(nombre)='sheraton'")[0]['id_local']
        g.operaciones_por_local_listas=True
        new=0
        with patch.object(db.session, 'commit', lambda: None):
            for tienda in rows('SELECT id_local FROM local ORDER BY id_local'):
                g.local_operativo=tienda['id_local']
                for supplier in missing:
                    products=rows('SELECT id_producto,presentacion FROM producto WHERE id_proveedor=:p ORDER BY id_producto LIMIT 3',p=supplier['id_proveedor'])
                    if not products: raise RuntimeError(f"Proveedor {supplier['id_proveedor']} sin productos: no se inventa un vínculo.")
                    for month in range(4):
                        day=today-timedelta(days=7+month*30)
                        if rows("""SELECT 1 FROM factura_recepcion f JOIN orden_compra o USING(id_orden_compra) WHERE f.id_proveedor=:p AND o.id_local=:local
                                   AND date_trunc('month',fecha_recepcion)=date_trunc('month',CAST(:d AS date))
                                   AND (numero_factura LIKE 'DEMO%' OR numero_factura LIKE 'DSHI-%') LIMIT 1""", p=supplier['id_proveedor'],d=day,local=g.local_operativo): continue
                        code=f"DF{g.local_operativo}-{supplier['id_proveedor']}-{day:%Y%m%d}"
                        if rows('SELECT 1 FROM orden_compra WHERE codigo=:c',c=code): continue
                        order=rows("""INSERT INTO orden_compra(codigo,estado_orden_compra,usuario_registro,fecha_registro,id_local)
                                      VALUES(:c,'ENVIADA',:u,:d,:l) RETURNING id_orden_compra""",c=code,u=user,d=day-timedelta(days=2),l=g.local_operativo)[0]['id_orden_compra']
                        details=[]
                        for p in products:
                            q=float(p['presentacion'] or 1)
                            db.session.execute(text('INSERT INTO orden_compra_detalle(id_orden_compra,id_producto,cantidad_solicitada,id_proveedor) VALUES(:o,:p,:q,:v)'), {'o':order,'p':p['id_producto'],'q':q,'v':supplier['id_proveedor']})
                            details.append(dict(id_producto=p['id_producto'],cantidad_recibida=q))
                        result,status=registrar_recepcion(order,user,dict(id_proveedor=supplier['id_proveedor'],numero_factura=f"DEMO{g.local_operativo}X{supplier['id_proveedor']}-{day:%Y%m%d}", fecha_recepcion=day.isoformat(),detalles=details,factura=amounts(details,day)))
                        if status != 201: raise RuntimeError(f'No se pudo crear el ejemplo: {result}')
                        db.session.execute(text("UPDATE factura_recepcion SET datos_factura=datos_factura || CAST(:d AS jsonb) WHERE id_factura_recepcion=:id"), {'id':result['id_factura_recepcion'],'d':json.dumps({'origen':TAG,'datos_ficticios':True})})
                        new+=1
        db.session.execute(text("""INSERT INTO actividad_usuario(id_usuario,modulo,accion,descripcion,id_local)
                               VALUES(:u,'RECEPCIONES','CARGAR_DEMO',:d,:l)"""), {'u':user,'d':f'{TAG}: {len(invoices)} facturas completadas; {new} ejemplos nuevos. Importes e impuestos ficticios.','l':g.local_operativo})
        db.session.commit()
        print(f'Aplicado: {len(invoices)} facturas completadas y {new} OC/facturas nuevas. Proveedores cubiertos: {len(providers)}.')


if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--apply',action='store_true')
    main(parser.parse_args().apply)

"""Persistence for incoming invoices; never sends fiscal documents."""
import json
from decimal import Decimal
from sqlalchemy import text
from app.core.local_scope import ejecutar_local, exigir_registro_local
from app.core.extensions import db
from .invoices import calcular_factura


def preparar(datos, id_orden, id_proveedor):
    factura = calcular_factura(datos)
    proveedor = db.session.execute(text('SELECT nombre, datos_comerciales FROM proveedor WHERE id_proveedor=:id'),
                                  {'id': id_proveedor}).mappings().first()
    if not proveedor:
        raise ValueError('El proveedor no existe.')
    factura['proveedor'] = {'nombre': proveedor['nombre'], **(proveedor['datos_comerciales'] or {})}
    # Reserve quantities already invoiced, including invoices not yet fully delivered.
    for linea in factura['lineas']:
        fila = ejecutar_local(text('''
            SELECT p.nombre, p.codigo, p.unidad, d.cantidad_solicitada,
              COALESCE((SELECT SUM(CASE WHEN f.datos_factura IS NULL THEN
                COALESCE((SELECT SUM(r.cantidad_recibida) FROM factura_recepcion_detalle r
                  WHERE r.id_factura_recepcion=f.id_factura_recepcion AND r.id_producto=d.id_producto),0)
                ELSE COALESCE((SELECT SUM((j->>'cantidad_facturada')::numeric)
                  FROM jsonb_array_elements(f.datos_factura->'lineas') j
                  WHERE (j->>'id_producto')::int=d.id_producto),0) END)
                FROM factura_recepcion f WHERE f.id_orden_compra=d.id_orden_compra AND f.id_proveedor=:proveedor),0) AS facturado
            FROM orden_compra_detalle d JOIN orden_compra o USING(id_orden_compra)
            JOIN producto p USING(id_producto)
            WHERE d.id_orden_compra=:orden AND d.id_proveedor=:proveedor
              AND d.id_producto=:producto AND o.id_local=:id_local_actual
            FOR UPDATE OF d
        '''), {'orden': id_orden, 'proveedor': id_proveedor, 'producto': linea['id_producto']}).mappings().first()
        if not fila or Decimal(str(linea['cantidad_facturada'])) > fila['cantidad_solicitada'] - fila['facturado']:
            raise ValueError('La cantidad facturada supera lo pendiente de facturar en la OC.')
        linea.update(nombre=fila['nombre'], codigo=fila['codigo'], unidad=fila['unidad'])
    return factura


def guardar(id_factura, factura):
    exigir_registro_local('factura', id_factura)
    ejecutar_local(text('UPDATE factura_recepcion SET datos_factura=CAST(:datos AS jsonb) WHERE id_factura_recepcion=:id'),
                   {'id': id_factura, 'datos': json.dumps(factura)})


def obtener(id_factura):
    exigir_registro_local('factura', id_factura)
    fila = ejecutar_local(text('SELECT datos_factura, entregas FROM factura_recepcion WHERE id_factura_recepcion=:id'),
                          {'id': id_factura}).mappings().one()
    return fila['datos_factura'], fila['entregas']


def anotar_entrega(id_factura, fecha, usuario, detalles, clave=None, solicitud=None):
    exigir_registro_local('factura', id_factura)
    ejecutar_local(text("UPDATE factura_recepcion SET entregas=entregas || CAST(:datos AS jsonb) WHERE id_factura_recepcion=:id"),
                   {'id': id_factura, 'datos': json.dumps([{'fecha': fecha, 'usuario': usuario, 'detalles': detalles,
                                                          'clave': clave, 'solicitud': solicitud}])})

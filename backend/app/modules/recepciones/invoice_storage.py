"""Persistence for incoming invoices; never sends fiscal documents."""
import json
from decimal import Decimal
from sqlalchemy import bindparam, func, select
from app.core.local_scope import ejecutar_local, exigir_registro_local
from app.core.extensions import db
from .invoices import calcular_factura


def preparar(datos, id_orden, id_proveedor):
    factura = calcular_factura(datos)
    proveedor = db.session.execute(select(func.public.recep_proveedor(bindparam("id")).table_valued(
        'nombre', 'datos_comerciales',
    )),
                                  {'id': id_proveedor}).mappings().first()
    if not proveedor:
        raise ValueError('El proveedor no existe.')
    factura['proveedor'] = {'nombre': proveedor['nombre'], **(proveedor['datos_comerciales'] or {})}
    # Reserve quantities already invoiced, including invoices not yet fully delivered.
    for linea in factura['lineas']:
        fila = ejecutar_local(select(func.public.recep_facturacion_pendiente(bindparam("orden"), bindparam("proveedor"), bindparam("producto"), bindparam("id_local_actual")).table_valued(
        'nombre', 'codigo', 'unidad', 'cantidad_solicitada', 'facturado',
    )), {'orden': id_orden, 'proveedor': id_proveedor, 'producto': linea['id_producto']}).mappings().first()
        if not fila or Decimal(str(linea['cantidad_facturada'])) > fila['cantidad_solicitada'] - fila['facturado']:
            raise ValueError('La cantidad facturada supera lo pendiente de facturar en la OC.')
        linea.update(nombre=fila['nombre'], codigo=fila['codigo'], unidad=fila['unidad'])
    return factura


def guardar(id_factura, factura):
    exigir_registro_local('factura', id_factura)
    ejecutar_local(select(func.public.recep_guardar_datos(bindparam("id"), bindparam("datos"))),
                   {'id': id_factura, 'datos': json.dumps(factura)})


def obtener(id_factura):
    exigir_registro_local('factura', id_factura)
    fila = ejecutar_local(select(func.public.recep_datos_factura(bindparam("id")).table_valued(
        'datos_factura', 'entregas',
    )),
                          {'id': id_factura}).mappings().one()
    return fila['datos_factura'], fila['entregas']


def anotar_entrega(id_factura, fecha, usuario, detalles, clave=None, solicitud=None):
    exigir_registro_local('factura', id_factura)
    ejecutar_local(select(func.public.recep_anotar_entrega(bindparam("id"), bindparam("datos"))),
                   {'id': id_factura, 'datos': json.dumps([{'fecha': fecha, 'usuario': usuario, 'detalles': detalles,
                                                          'clave': clave, 'solicitud': solicitud}])})

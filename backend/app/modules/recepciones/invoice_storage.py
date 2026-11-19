"""Persistence for incoming invoices; never sends fiscal documents."""
import json
import hashlib
from uuid import UUID
from decimal import Decimal
from sqlalchemy import text
from werkzeug.exceptions import BadRequest, Conflict
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


def entregar(id_factura, usuario, datos):
    from . import repository as repo
    from .service import recalcular_estado_orden
    from .invoices import numero
    from datetime import date
    from app.modules.auditoria.service import registrar_actividad
    if not isinstance(datos, dict):
        raise BadRequest('Completa la entrega.')
    try:
        fecha = date.fromisoformat(datos.get('fecha', ''))
    except (TypeError, ValueError):
        raise BadRequest('Ingresa una fecha válida.') from None
    try:
        cabecera = repo.obtener_factura_recepcion(id_factura, bloquear=True)
        factura, entregas = obtener(id_factura)
        if not factura:
            raise Conflict('Esta recepción anterior no tiene cantidades facturadas registradas.')
        clave = datos.get('clave')
        solicitud = hashlib.sha256(json.dumps(datos, sort_keys=True, ensure_ascii=True).encode()).hexdigest()
        if clave is not None:
            try:
                clave = str(UUID(clave))
            except (ValueError, TypeError, AttributeError):
                raise BadRequest('Identificador de entrega inválido.') from None
            anterior = next((e for e in entregas if e.get('clave') == clave), None)
            if anterior:
                if anterior.get('solicitud') != solicitud:
                    raise Conflict('La entrega ya fue registrada con otros datos. Recarga el detalle.')
                db.session.rollback()
                return {'mensaje': 'La entrega ya estaba registrada.', 'estado_orden_compra': cabecera['estado_orden_compra']}, 200
        if cabecera['estado_orden_compra'] not in ('ENVIADA', 'RECEPCION_PARCIAL'):
            raise Conflict('La orden ya no admite entregas.')
        if fecha.isoformat() < max(factura['fecha_emision'], cabecera['fecha_recepcion'].isoformat()):
            raise BadRequest('La entrega no puede ser anterior a la emisión o a la recepción inicial.')
        lineas = {l['id_producto']: l for l in factura['lineas']}
        actuales = {l['id_producto']: l for l in repo.listar_detalles_factura(id_factura)}
        detalles = datos.get('detalles')
        if not isinstance(detalles, list) or not detalles or len(detalles) > 500:
            raise BadRequest('Indica los productos entregados.')
        vistos = set(); validos = []
        for d in detalles:
            if not isinstance(d, dict) or type(d.get('id_producto')) is not int:
                raise BadRequest('Producto inválido.')
            identidad = d['id_producto']
            if identidad not in lineas or identidad in vistos:
                raise BadRequest('Producto ajeno o repetido.')
            vistos.add(identidad)
            cantidad = numero(d.get('cantidad_recibida'), 'cantidad recibida', True)
            actual = actuales.get(identidad)
            acumulado = (actual['cantidad_recibida'] if actual else Decimal(0)) + cantidad
            pendiente = repo.obtener_producto_pendiente(cabecera['id_orden_compra'], cabecera['id_proveedor'], identidad)
            if (acumulado > Decimal(str(lineas[identidad]['cantidad_facturada'])) or not pendiente
                    or cantidad > pendiente['cantidad_solicitada'] - pendiente['cantidad_recibida']):
                raise BadRequest('La entrega supera lo pendiente de la factura o de la OC.')
            validos.append((identidad, cantidad, acumulado, actual))
        for identidad, cantidad, acumulado, actual in validos:
            if actual:
                repo.actualizar_cantidad_recepcion(actual['id_factura_recepcion_detalle'], acumulado)
            else:
                repo.crear_detalle_recepcion(id_factura, identidad, cantidad)
        anotar_entrega(id_factura, fecha.isoformat(), usuario,
                      [{'id_producto': i, 'cantidad_recibida': float(c)} for i, c, _, _ in validos], clave, solicitud)
        estado = recalcular_estado_orden(cabecera['id_orden_compra'])
        registrar_actividad(usuario, 'RECEPCION_PRODUCTOS', 'CREAR', id_factura, 'Registró una entrega de la factura existente')
        db.session.commit()
        return {'mensaje': 'Entrega registrada correctamente.', 'estado_orden_compra': estado}, 201
    except ValueError as error:
        db.session.rollback()
        raise BadRequest(str(error)) from None
    except Exception:
        db.session.rollback()
        raise

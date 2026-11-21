import hashlib
import json
from datetime import date
from uuid import UUID

from werkzeug.exceptions import BadRequest, Conflict

from app.core.extensions import db
from app.modules.auditoria import service as auditoria
from . import invoice_storage, repository as repo, service
from .invoice_delivery_rules import validar_detalles_entrega


def entregar(id_factura, usuario, datos):
    if not isinstance(datos, dict):
        raise BadRequest('Completa la entrega.')
    try:
        fecha = date.fromisoformat(datos.get('fecha', ''))
    except (TypeError, ValueError):
        raise BadRequest('Ingresa una fecha válida.') from None
    try:
        cabecera = repo.obtener_factura_recepcion(id_factura, bloquear=True)
        factura, entregas = invoice_storage.obtener(id_factura)
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
        actuales = repo.listar_detalles_factura(id_factura)

        def cantidad_pendiente(id_producto):
            fila = repo.obtener_producto_pendiente(
                cabecera['id_orden_compra'], cabecera['id_proveedor'], id_producto,
            )
            if fila:
                return fila['cantidad_solicitada'] - fila['cantidad_recibida']
            return None

        validos = validar_detalles_entrega(
            datos.get('detalles'), factura['lineas'], actuales, cantidad_pendiente,
        )
        for identidad, cantidad, acumulado, actual in validos:
            if actual:
                repo.actualizar_cantidad_recepcion(actual['id_factura_recepcion_detalle'], acumulado)
            else:
                repo.crear_detalle_recepcion(id_factura, identidad, cantidad)
        invoice_storage.anotar_entrega(
            id_factura, fecha.isoformat(), usuario,
            [{'id_producto': i, 'cantidad_recibida': float(c)} for i, c, _, _ in validos],
            clave, solicitud,
        )
        estado = service.recalcular_estado_orden(cabecera['id_orden_compra'])
        auditoria.registrar_actividad(usuario, 'RECEPCION_PRODUCTOS', 'CREAR', id_factura, 'Registró una entrega de la factura existente')
        db.session.commit()
        return {'mensaje': 'Entrega registrada correctamente.', 'estado_orden_compra': estado}, 201
    except ValueError as error:
        db.session.rollback()
        raise BadRequest(str(error)) from None
    except Exception:
        db.session.rollback()
        raise

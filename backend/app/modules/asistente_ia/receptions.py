"""Reception proposals use local pending orders and native validation on confirmation."""
from datetime import date
from decimal import Decimal, InvalidOperation

from .provider import AssistantError

RESOURCES = {
    'recepciones': (24, '/recepciones/pendientes', 'pendientes', 'id_orden_compra'),
    'historial_recepciones': (32, '/recepciones/historial', 'recepciones', 'id_factura_recepcion'),
}


def allowed(session, resource, action):
    if action not in (('consultar', 'crear') if resource == 'recepciones' else ('consultar',)):
        return False
    return any(entry['id_opcion_menu'] == RESOURCES[resource][0]
               and entry.get('permisos', {}).get(action, False) for entry in session.get('menu', []))


def positive_id(value):
    if type(value) is not int or value <= 0:
        raise AssistantError('Indica un identificador válido de la orden, proveedor o producto.')
    return value


def prepare(session, action, identity, changes):
    from . import tools
    tools.authorize(session, 'recepciones', 'crear')
    tools.authorize(session, 'recepciones')
    fields = {'id_orden_compra', 'id_proveedor', 'numero_factura', 'fecha_recepcion', 'detalles'}
    if action != 'crear' or identity is not None:
        raise AssistantError('Solo se permite preparar una nueva recepción.')
    if not isinstance(changes, dict) or set(changes) != fields:
        raise AssistantError('Indica orden, proveedor, factura, fecha y cantidades recibidas.')
    order_id = positive_id(changes['id_orden_compra'])
    supplier_id = positive_id(changes['id_proveedor'])
    invoice = changes['numero_factura']
    if not isinstance(invoice, str) or not 1 <= len(invoice.strip()) <= 40:
        raise AssistantError('Indica el número real de factura, de hasta 40 caracteres.')
    try:
        received_date = date.fromisoformat(changes['fecha_recepcion']).isoformat()
    except (ValueError, TypeError):
        raise AssistantError('Indica la fecha real de recepción (AAAA-MM-DD).') from None
    pending = next((row for row in tools.records(session, 'recepciones')
                    if row['id_orden_compra'] == order_id and row['id_proveedor'] == supplier_id), None)
    if pending is None:
        raise AssistantError('La orden y proveedor no tienen recepción pendiente en el local activo.', 409)
    products = {row['id_producto']: row for row in pending['productos']}
    details = changes['detalles']
    if not isinstance(details, list) or not details:
        raise AssistantError('Indica al menos un producto recibido.')
    clean, review, seen = [], [], set()
    for item in details:
        if not isinstance(item, dict) or set(item) != {'id_producto', 'cantidad_recibida'}:
            raise AssistantError('Cada detalle requiere producto y cantidad recibida.')
        pid = positive_id(item['id_producto'])
        if pid not in products or pid in seen:
            raise AssistantError('Producto repetido o ajeno a la orden y proveedor.')
        try:
            quantity = Decimal(str(item['cantidad_recibida']))
        except (InvalidOperation, ValueError, TypeError):
            raise AssistantError('Cantidad recibida inválida.') from None
        product = products[pid]
        remaining = Decimal(str(product['cantidad_pendiente']))
        if not quantity.is_finite() or quantity <= 0 or quantity > remaining:
            raise AssistantError('La cantidad debe ser positiva y no superar el pendiente.')
        seen.add(pid)
        clean.append({'id_producto': pid, 'cantidad_recibida': float(quantity)})
        review.append({'producto': product['nombre'], 'unidad': product['unidad'],
                       'cantidad_solicitada': product['cantidad_solicitada'],
                       'recibido_anterior': product['cantidad_recibida'],
                       'cantidad_recibida': float(quantity),
                       'pendiente_despues': float(remaining - quantity)})
    return {'recurso': 'recepciones', 'accion': 'crear', 'id': None, 'anterior': None,
            'id_orden_compra': order_id,
            'datos': {'id_proveedor': supplier_id, 'numero_factura': invoice.strip(),
                      'fecha_recepcion': received_date, 'detalles': clean},
            'revision_recepcion': review, 'codigo_orden': pending.get('codigo_orden'),
            'proveedor': pending.get('proveedor'),
            'advertencia': 'Verifica físicamente las cantidades y el estado. Realizar registra esta recepción.'}


def execute(session, plan):
    from . import tools
    # Recheck local pending quantities before dispatch; native service checks again under lock.
    checked = prepare(session, 'crear', None, {
        **plan['datos'], 'id_orden_compra': plan['id_orden_compra']})
    return tools.native(f"/recepciones/ordenes/{checked['id_orden_compra']}/recepciones",
                        'POST', checked['datos'])


def readable(session, plan):
    from . import tools
    tools.authorize(session, 'recepciones')
    return {'orden': plan['codigo_orden'], 'proveedor': plan['proveedor'],
            'numero_factura': plan['datos']['numero_factura'],
            'fecha_recepcion': plan['datos']['fecha_recepcion'],
            'productos': plan['revision_recepcion'], 'advertencia': plan['advertencia']}

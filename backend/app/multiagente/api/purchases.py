"""Purchase proposals reuse native permissions, validation and confirmation."""
from decimal import Decimal, InvalidOperation, ROUND_CEILING
from .provider import AssistantError

RESOURCES = {
    'ordenes_compra': (22, '/ordenes-compra/formulario', 'productos', 'id_producto'),
    'pedido_sugerido': (22, '/ordenes-compra/pedido-sugerido', 'productos', 'id_producto'),
}


def allowed(session, resource, action):
    if action not in (('consultar', 'crear') if resource == 'ordenes_compra' else ('consultar',)):
        return False
    return any(m['id_opcion_menu'] == 22 and m.get('permisos', {}).get(action, False)
               for m in session['menu'])


def percentage(value):
    try:
        result = Decimal(str(value))
    except InvalidOperation:
        raise AssistantError('Porcentaje inválido.') from None
    if not result.is_finite() or not 0 <= result <= 1000:
        raise AssistantError('El porcentaje debe estar entre 0 y 1000.')
    return result


def short_summary(rows):
    if any(r.get('ajuste_manual') for r in rows):
        return 'Cantidades ajustadas manualmente; revisa el total a pedir antes de confirmar.'
    text = 'Solo se compra el faltante, descontando el stock disponible.'
    extras = [r for r in rows if r.get('porcentaje_adicional', 0) > 0]
    changed = [r for r in extras if r['cantidad_final'] > r['base_sugerida']]
    if changed:
        names = ', '.join(str(r['producto'])[:35] for r in changed[:2])
        more = f' y {len(changed)-2} insumos más' if len(changed)>2 else ''
        text += f' El adicional aumentó {names}{more}.'
    elif extras:
        text += ' El adicional no cambia las cantidades tras redondear por presentación.'
    return text


def prepare(session, action, identity, changes):
    from . import tools
    tools.authorize(session, 'ordenes_compra', 'crear')
    tools.authorize(session, 'ordenes_compra')
    if action != 'crear' or identity is not None:
        raise AssistantError('Solo se permite preparar una nueva orden.')
    if not isinstance(changes, dict) or set(changes) - {'porcentaje_general', 'adicionales', 'horizonte','dias_abastecimiento'} or not {'porcentaje_general','adicionales'} <= set(changes):
        raise AssistantError('Indica porcentaje_general y adicionales por producto.')
    if changes.get('horizonte') not in (None,'semanal'):
        raise AssistantError('Horizonte de compra no permitido.')
    days=changes.get('dias_abastecimiento',7)
    if type(days) is not int or not 1<=days<=90 or ('dias_abastecimiento' in changes and changes.get('horizonte')!='semanal'):
        raise AssistantError('Indica un plazo de abastecimiento de entre 1 y 90 días.')
    general = percentage(changes['porcentaje_general'])
    extras = changes['adicionales']
    if not isinstance(extras, list):
        raise AssistantError('Los adicionales deben ser una lista.')
    extra_by_id = {}
    for extra in extras:
        if not isinstance(extra, dict) or set(extra) != {'id_producto', 'porcentaje'}:
            raise AssistantError('Cada adicional requiere id_producto y porcentaje.')
        pid = extra['id_producto']
        if type(pid) is not int or pid <= 0 or pid in extra_by_id:
            raise AssistantError('Producto adicional inválido o repetido.')
        extra_by_id[pid] = percentage(extra['porcentaje'])
    tools.authorize(session, 'pedido_sugerido')
    weekly = changes.get('horizonte') == 'semanal'
    suggestion=tools.native('/ordenes-compra/pedido-sugerido?porcentaje=' + str(general) + ('&horizonte=semanal'+(f'&dias={days}' if days!=7 else '') if weekly else ''))
    rows = suggestion['productos']
    if set(extra_by_id) - {r['id_producto'] for r in rows}:
        raise AssistantError('Un adicional no tiene cantidad base sugerida. Revisa el pedido en Compras.')
    details, review = [], []
    for row in rows:
        base = Decimal(str(row['cantidad_sugerida']))
        pack = Decimal(str(row['presentacion']))
        if pack <= 0:
            raise AssistantError('Revisa la presentación del producto antes de comprar.')
        extra = extra_by_id.get(row['id_producto'], Decimal(0))
        adjusted = base * (1 + extra / 100)
        final = (adjusted / pack).to_integral_value(rounding=ROUND_CEILING) * pack
        details.append({'id_producto': row['id_producto'], 'cantidad_solicitada': float(final)})
        review.append({'producto': row['nombre'], 'unidad': row['unidad'], 'base_sugerida': float(base),
                       'porcentaje_general': float(general), 'porcentaje_adicional': float(extra),
                       'antes_de_redondear': float(adjusted), 'cantidad_final': float(final),
                       'presentacion_compra': float(pack)})
    if not details:
        raise AssistantError('No hay productos con necesidad de compra sugerida.')
    return {'recurso': 'ordenes_compra', 'accion': 'crear', 'id': None, 'anterior': None,
            **({'horizonte':'semanal','dias_abastecimiento':days,'periodos':suggestion.get('periodos',{})} if weekly else {}),
            'datos': {'accion': 'ENVIAR', 'detalles': details},
            'revision_compra': review,
            'resumen_compra': short_summary(review),
            'advertencia': (f'Abastecimiento para {days} días. ' if weekly else '')+f'El margen elegido es {general}% sobre el consumo, antes de restar stock. '
                           'Los adicionales por producto se aplican después; se redondean a presentaciones completas. '
                           'Se enviará la orden al confirmar Enviar pedido.'}

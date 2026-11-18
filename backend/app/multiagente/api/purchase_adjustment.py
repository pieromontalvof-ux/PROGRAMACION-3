"""Replace purchase reviews using server-owned presentation sizes, never orders."""
from copy import deepcopy
from decimal import Decimal, InvalidOperation
from uuid import uuid4
from sqlalchemy import JSON, column, insert, table, text
from app.core.extensions import db
from . import drafts, tools
from .provider import AssistantError


def _decimal(value):
    try:
        result = Decimal(str(value))
    except (InvalidOperation, ValueError, TypeError):
        raise AssistantError('La propuesta contiene cantidades inválidas. Prepara otra.', 409) from None
    if not result.is_finite() or result <= 0:
        raise AssistantError('La propuesta contiene cantidades inválidas. Prepara otra.', 409)
    return result


def _public(value):
    if isinstance(value, dict):
        return {k: _public(v) for k, v in value.items() if not k.startswith('_')}
    if isinstance(value, list):
        return [_public(v) for v in value]
    return value


def adjust(session, identity, quantities):
    tools.authorize(session, 'ordenes_compra', 'consultar')
    tools.authorize(session, 'ordenes_compra', 'crear')
    if not isinstance(quantities, list) or not quantities or len(quantities) > 1000:
        raise AssistantError('Indica las presentaciones que deseas pedir.')
    changes = {}
    for item in quantities:
        if not isinstance(item, dict) or set(item) != {'id_producto', 'presentaciones'}:
            raise AssistantError('Cada cantidad requiere producto y presentaciones completas.')
        pid, count = item['id_producto'], item['presentaciones']
        if type(pid) is not int or pid <= 0 or pid in changes or type(count) is not int or not 1 <= count <= 1000000:
            raise AssistantError('Usa productos únicos y entre 1 y 1000000 presentaciones completas.')
        changes[pid] = count
    original = drafts.load(identity)  # Scope-filtered and FOR UPDATE until replacement commits.
    if original['estado'] != 'PENDIENTE' or not original['vigente']:
        raise AssistantError('El borrador venció o ya fue procesado. Prepara uno nuevo.', 409)
    plan = deepcopy(original['plan'])
    if plan.get('recurso') != 'ordenes_compra' or plan.get('accion') != 'crear':
        raise AssistantError('Este borrador no es una propuesta de compra.', 409)
    details = plan.get('datos', {}).get('detalles')
    reviews = plan.get('revision_compra')
    if not isinstance(details, list) or not isinstance(reviews, list) or not details or len(details) != len(reviews):
        raise AssistantError('La propuesta no permite identificar sus productos. Prepara otra.', 409)
    products = {p['id_producto']: p for p in tools.native('/ordenes-compra/formulario')['productos']}
    seen = set()
    for detail, review in zip(details, reviews):
        if not isinstance(detail, dict) or not isinstance(review, dict):
            raise AssistantError('La propuesta contiene productos inválidos.', 409)
        pid = detail.get('id_producto')
        if type(pid) is not int or pid <= 0 or pid in seen or review.get('id_producto', pid) != pid:
            raise AssistantError('La propuesta contiene productos ambiguos.', 409)
        seen.add(pid)
        current = products.get(pid)
        pack = _decimal(review.get('presentacion_compra'))
        amount = _decimal(detail.get('cantidad_solicitada'))
        if (not current or _decimal(current.get('presentacion')) != pack
                or current.get('unidad') != review.get('unidad')
                or _decimal(review.get('cantidad_final')) != amount or amount % pack):
            raise AssistantError('Los productos o sus presentaciones cambiaron. Prepara otra propuesta.', 409)
        if pid in changes:
            final = pack * changes[pid]
            if final > Decimal('999999999.999'):
                raise AssistantError('La cantidad solicitada supera el máximo permitido.')
            detail['cantidad_solicitada'] = float(final)
            review['cantidad_final'] = float(final)
            review['ajuste_manual'] = True
    if set(changes) - seen:
        raise AssistantError('Solo puedes ajustar productos incluidos en la propuesta.')
    plan['ajuste_manual'] = True
    view = tools.readable(session, plan)
    new_id = str(uuid4())
    storage = table('asistente_ia_borrador', column('id'), column('id_usuario'),
                    column('id_perfil'), column('id_local'), column('plan', JSON))
    scope = drafts.scope()
    db.session.execute(insert(storage).values(id=new_id, id_usuario=scope['usuario'],
        id_perfil=scope['perfil'], id_local=scope['local'], plan=plan))
    db.session.execute(text("UPDATE asistente_ia_borrador SET estado='CANCELADO' WHERE id=:id"), {'id': identity})
    db.session.commit()
    return {'respuesta':'Cantidades actualizadas. Revisa la propuesta y confirma con Realizar.',
            'borrador':{'id_borrador':new_id, 'vista':_public(view), **_public(plan)}, 'consultas':[]}

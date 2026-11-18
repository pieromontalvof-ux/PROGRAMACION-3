"""Read-only coordination of catalog, local stock and registered supplier."""
import re
from decimal import Decimal, InvalidOperation

from app.multiagente.agents import activity
from app.multiagente.api import configuration, inventory, tools
from app.multiagente.api.provider import AssistantError


def active(row):
    return row.get('activo', True) and row.get('estado_registro', 1) == 1


def catalog_only(session):
    """Administrators define global recipes; stores handle local supply."""
    return (session.get('perfil_activo') or {}).get('id_perfil') == 1


def authorize(session, agent_id, resource):
    configuration.authorize(agent_id, resource)
    configuration.authorize_owner(resource)
    tools.authorize(session, resource)
    if not tools.allowed(session, resource):
        raise AssistantError('El perfil no permite consultar este recurso.', 403)


@activity.agent('carta_recetas')
def catalog(session, resource, agent_id):
    authorize(session, agent_id, resource)
    return {'registros': tools.records(session, resource)}


@activity.agent('inventario')
def stock(session, product, agent_id):
    authorize(session, agent_id, 'stock')
    # Paginate search results and match identity, never a similar product name.
    offset = 0
    while True:
        result = inventory.read(session, 'stock', {'busqueda': product['nombre'], 'desde_registro': offset})
        row = next((r for r in result['registros'] if r['id_producto'] == product['id_producto']), None)
        if row is not None:
            return row
        if not result.get('hay_mas'):
            return None
        offset += 30
        if offset >= result.get('total', offset):
            return None


def unavailable(error):
    return 'SIN_ACCESO' if error.status == 403 else 'NO_VERIFICADO'


def report(name, state, rows, summary, decision=False, scope='ABASTECIMIENTO'):
    return {'recurso': 'productos', 'busqueda': name, 'estado_catalogo': state,
            'total': len(rows), 'desde': 0, 'hay_mas': False, 'registros': rows,
            'resumen': summary, 'requiere_decision': decision, 'alcance': scope}


@activity.tool('revisar_insumo')
def review(session, name, agent_id):
    if not isinstance(name, str) or not 1 <= len(name.strip()) <= 200:
        raise AssistantError('Indica un nombre de insumo de hasta 200 caracteres.')
    name = name.strip()
    try:
        rows = catalog(session, 'productos', agent_id)['registros']
    except AssistantError as error:
        return report(name, unavailable(error), [], f'No pude comprobar si {name} está registrado con los accesos y servicios actuales.',
                      scope='CATALOGO' if catalog_only(session) else 'ABASTECIMIENTO')
    return review_rows(session, name, agent_id, rows)


def review_rows(session, name, agent_id, products):
    scope = 'CATALOGO' if catalog_only(session) else 'ABASTECIMIENTO'
    normalized = tools.normalized(name)
    exact = [p for p in products if tools.normalized(p['nombre'].strip()) == normalized]
    matches = exact or [p for p in products if normalized in tools.normalized(p['nombre'])]
    if not matches:
        # A commercial title can contain a catalog name. Offer that reference
        # for confirmation, never declare it an ingredient or a substitute.
        matches = [p for p in products if re.search(r'\b' + re.escape(tools.normalized(p['nombre'])) + r'\b', normalized)]
    public = [{k: p.get(k) for k in ('id_producto', 'nombre', 'unidad', 'activo')} for p in matches]
    if not matches:
        summary = (f'No encontré {name} en el catálogo de insumos. Debe registrarse para incluirlo en la receta.'
                   if scope == 'CATALOGO' else
                   f'No encontré {name} como producto de inventario. Podemos revisar proveedores y proponer su registro.')
        return report(name, 'NO_REGISTRADO', [], summary, True, scope)
    if len(exact) != 1:
        summary = (f'Encontré coincidencias para {name}; confirma qué insumo usarás en la receta.' if scope == 'CATALOGO' else
                   f'Encontré coincidencias para {name}; confirma el insumo antes de revisar su stock o sustituirlo.')
        return report(name, 'ELEGIR_PRODUCTO', public[:10], summary, True, scope)
    product = exact[0]
    if not active(product):
        return report(name, 'INACTIVO', public, f'{product["nombre"]} está registrado pero inactivo; no propongo un duplicado.', True, scope)

    if scope == 'CATALOGO':
        return report(name, 'ACTIVO', public, f'{product["nombre"]} está registrado y activo.', scope=scope)

    row = {**public[0], 'estado_stock': 'NO_VERIFICADO', 'stock_actual': None,
           'estado_proveedor': 'NO_VERIFICADO', 'proveedor': None}
    try:
        current = stock(session, product, agent_id)
        if current is not None and current.get('stock_actual') is not None and current.get('estado_stock') != 'SIN_CONTEO':
            amount = Decimal(str(current['stock_actual']))
            if amount.is_finite():
                row.update(stock_actual=float(amount), estado_stock='CON_STOCK' if amount > 0 else 'SIN_STOCK')
    except AssistantError as error:
        row['estado_stock'] = unavailable(error)
    except (InvalidOperation, TypeError, ValueError):
        pass
    try:
        providers = catalog(session, 'proveedores', agent_id)['registros']
        provider = next((p for p in providers if p['id_proveedor'] == product.get('id_proveedor')), None)
        if provider:
            row.update(proveedor=provider['nombre'], estado_proveedor='REGISTRADO' if active(provider) else 'INACTIVO')
        else:
            row['estado_proveedor'] = 'SIN_ASOCIACION'
    except AssistantError as error:
        row['estado_proveedor'] = unavailable(error)

    local = (session.get('local_activo') or {}).get('nombre', 'el local activo')
    summary = f'{product["nombre"]} está registrado.'
    if row['estado_stock'] == 'SIN_STOCK':
        summary += f' Sin existencias disponibles en {local}.'
    elif row['estado_stock'] == 'CON_STOCK':
        unit = {'LTR': 'L', 'KGM': 'kg', 'C62': 'unidades'}.get(product.get('unidad'), product.get('unidad', ''))
        summary += f' Stock registrado en {local}: {row["stock_actual"]:g} {unit}. Falta la receta y cantidad a preparar para saber si alcanza.'
    elif row['estado_stock'] == 'SIN_ACCESO':
        summary += f' No pude verificar el stock de {local} con los permisos actuales.'
    else:
        summary += f' No hay stock verificado para {local}; no lo considero agotado.'
    if row['estado_proveedor'] == 'REGISTRADO':
        summary += f' Proveedor asociado: {row["proveedor"]}; su disponibilidad debe confirmarse.'
    elif row['estado_proveedor'] == 'INACTIVO':
        summary += ' Su proveedor asociado está inactivo.'
    return report(name, 'ACTIVO', [row], summary, row['estado_stock'] == 'SIN_STOCK')


def for_title(session, title, agent_id):
    """Literal catalog names in a title are leads, never recipe ingredients."""
    try:
        products = catalog(session, 'productos', agent_id)['registros']
    except AssistantError:
        return None
    text = tools.normalized(title)
    matches = [p for p in products if re.search(r'\b' + re.escape(tools.normalized(p['nombre'])) + r'\b', text)]
    if not matches:
        return None
    # Prefer the longest literal name, e.g. Camu Camu Maracuyá over Maracuya.
    product = max(matches, key=lambda p: len(p['nombre']))
    result = review_rows(session, product['nombre'], agent_id, products)
    result['referencia'] = 'POSIBLE_INSUMO'
    result['resumen'] = 'Posible insumo por confirmar: ' + result['resumen']
    return result

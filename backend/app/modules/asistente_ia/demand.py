"""Bounded, local-only demand capability shared by demand and purchasing agents."""
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urlencode
from flask_jwt_extended import get_jwt
from .provider import AssistantError

RESOURCE = ('demanda_rotacion', (37, '/inventario-operativo/demanda', 'productos', 'id_producto'))


def allowed(session, action='consultar'):
    return action == 'consultar' and get_jwt().get('id_perfil') in (2, 3) and all(
        any(m['id_opcion_menu'] == menu and m.get('permisos', {}).get('consultar')
            for m in session['menu']) for menu in (15, 37))


def read(session, filters=None):
    from . import tools
    tools.authorize(session, RESOURCE[0])
    f = {} if filters is None else filters
    if not isinstance(f, dict) or set(f) - {'desde', 'hasta', 'busqueda', 'desde_registro'}:
        raise AssistantError('Filtros no permitidos. Se utiliza el local de la sesión.')
    today = datetime.now(timezone(timedelta(hours=-5))).date()
    try:
        start = date.fromisoformat(f.get('desde', (today - timedelta(days=29)).isoformat()))
        end = date.fromisoformat(f.get('hasta', today.isoformat()))
    except (ValueError, TypeError):
        raise AssistantError('Indica fechas válidas AAAA-MM-DD.') from None
    if end < start or (end-start).days > 366 or end > today:
        raise AssistantError('Indica hasta 367 días, sin fechas futuras.')
    search, offset = f.get('busqueda', ''), f.get('desde_registro', 0)
    if not isinstance(search, str) or len(search) > 200 or type(offset) is not int or offset < 0:
        raise AssistantError('Búsqueda o paginación inválida.')
    report = tools.native(RESOURCE[1][1] + '?' + urlencode({'desde': start.isoformat(), 'hasta': end.isoformat()}))
    terms = tools.normalized(search).split()
    def matches(row):
        text = tools.normalized(' '.join(str(row.get(k, '')) for k in ('nombre', 'codigo', 'categoria')))
        return all(term in text for term in terms)
    products = [r for r in report['productos'] if matches(r)]
    items = [r for r in report['articulos'] if matches(r)]
    return dict(recurso=RESOURCE[0], total=len(products), desde=offset,
                registros=products[offset:offset+20], hay_mas=len(products)>offset+20,
                contexto={k: v for k, v in report.items() if k not in ('productos', 'articulos')} | {
                    'articulos': items[offset:offset+20], 'total_articulos': len(items),
                    'hay_mas_articulos': len(items)>offset+20,
                    'nota_filtro': 'La búsqueda se aplica por separado a artículos e insumos; no implica trazabilidad individual entre ambos rankings.'})

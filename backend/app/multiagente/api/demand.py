from app.core.profile_capabilities import perfil_tiene_capacidad
from app.multiagente.agents import activity
"""Bounded, local-only demand capability shared by demand and purchasing agents."""
from datetime import date, datetime, timedelta, timezone
from urllib.parse import urlencode
from flask_jwt_extended import get_jwt
from .provider import AssistantError

RESOURCE = ('demanda_rotacion', (37, '/inventario-operativo/demanda', 'productos', 'id_producto'))


def allowed(session, action='consultar'):
    return action == 'consultar' and perfil_tiene_capacidad(get_jwt().get('id_perfil'), 'gestionar_inventario') and all(
        any(m['id_opcion_menu'] == menu and m.get('permisos', {}).get('consultar')
            for m in session['menu']) for menu in (15, 37))


@activity.tool('analizar_demanda')
def read(session, filters=None, *, global_scope=False):
    from . import tools
    resource='demanda_global' if global_scope else RESOURCE[0]
    tools.authorize(session, resource)
    f = {} if filters is None else filters
    if not isinstance(f, dict) or set(f) - {'desde', 'hasta', 'busqueda', 'desde_registro', 'detalle_productos'}:
        raise AssistantError('Filtros no permitidos. Se utiliza el local de la sesión.')
    if 'detalle_productos' in f and (type(f['detalle_productos']) is not bool or global_scope):
        raise AssistantError('El detalle de productos requiere un análisis local y un indicador válido.')
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
    path='/inventario-operativo/demanda-global' if global_scope else RESOURCE[1][1]
    params={'desde': start.isoformat(), 'hasta': end.isoformat()}
    if f.get('detalle_productos'): params['detalle']='productos'
    report = tools.native(path + '?' + urlencode(params))
    terms = tools.normalized(search).split()
    def matches(row):
        text = tools.normalized(' '.join(str(row.get(k, '')) for k in ('nombre', 'codigo', 'categoria')))
        return all(term in text for term in terms)
    products = [r for r in report['productos'] if matches(r)]
    items = [r for r in report['articulos'] if matches(r)]
    result=dict(recurso=resource, total=len(products), desde=offset,
                registros=products[offset:offset+20], hay_mas=len(products)>offset+20,
                contexto={k: v for k, v in report.items() if k not in ('productos', 'articulos', 'analisis_productos')} | {
                    'articulos': items[offset:offset+20], 'total_articulos': len(items),
                    'resumen': {'productos_con_consumo': sum(float(row.get('consumo_ventas') or 0) > 0 for row in products)},
                    'hay_mas_articulos': len(items)>offset+20,
                    'nota_filtro': 'La búsqueda se aplica por separado a artículos e insumos; no implica trazabilidad individual entre ambos rankings.'})
    if report.get('analisis_productos'):
        outlook=report['analisis_productos']
        ranked=[r for r in outlook['articulos'] if matches(r)]
        selected=ranked[offset:offset+20]
        ids={pid for r in selected for pid in r.get('ids_insumos',[])}
        result['contexto']['analisis_productos']={**outlook,'articulos':selected,'total_articulos':len(ranked),
            'insumos':[r for r in outlook['insumos'] if r['id_producto'] in ids]}
        result['contexto']['nota_filtro']='Las recetas actuales identifican los insumos de las presentaciones seleccionadas; el consumo incluye todas las ventas del local.'
    return result

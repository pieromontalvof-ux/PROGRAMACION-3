"""Complete explicitly requested purchase research with bounded, read-only calls."""
import re
from datetime import datetime, timedelta, timezone
from decimal import Decimal, InvalidOperation

from app.agents import activity
from app.agents.demanda import agent as demand_agent
from app.modules.asistente_ia import configuration, tools
from app.modules.asistente_ia.provider import AssistantError


def exclusions(instruction):
    value = tools.normalized(instruction)
    excluded = set()
    start = (r'\b(?:no\s+(?:(?:quiero|necesito|deseo)\s+)*'
             r'(?:analices|analizar|revises|revisar|evalues|evaluar|muestres|mostrar|hagas|hacer|ventas|stock|existencias|reposicion|consumo|demanda)'
             r'|sin\s+(?:analisis|revision))\b')
    for match in re.finditer(start, value):
        clause = re.split(r'[.;!?]|\bpero\b|,\s*(?=analiza|revisa|muestra|quiero)|\by\s+(?=analiza|revisa|muestra)', value[match.start():], maxsplit=1)[0]
        for stage, words in (('ventas', r'ventas|demanda|consumo'), ('stock', r'stock|existencias|cobertura'),
                             ('reposicion', r'reposicion|reponer|pedido'), ('eventos', r'eventos|conciertos|festividades')):
            if re.search(r'\b(?:' + words + r')\b', clause):
                excluded.add(stage)
    return excluded


def requested(instruction):
    value = tools.normalized(instruction)
    # Remove explicit exclusions before checking whether analysis was requested.
    value = re.sub(r'\b(?:no|sin)\s+(?:(?:quiero|deseo|necesito|analices|revises|analizar|revisar|analisis|de|el|la|las|los|ni)\s+)*'
                   r'(?:ventas|stock|existencias|reposicion|demanda)\b[^.;!?]*', '', value)
    return bool(re.search(r'\b(?:analiza|analizar|revisa|revisar|evalua|evaluar|muestra|muestrame)\b', value)
                and re.search(r'\b(?:ventas|stock|existencias|reposicion|reponer|demanda|consumo)\b', value))


def sales_filters(instruction):
    value = tools.normalized(instruction)
    dates = re.search(r'\b(?:ventas|consumo|analisis)\s+(?:(?:cobradas|registradas|del|de|desde|entre|el|periodo|en)\s+)*'
                      r'(\d{4}-\d{2}-\d{2})\s+(?:al|hasta|y)\s+(\d{4}-\d{2}-\d{2})', value)
    if dates:
        return {'desde': dates[1], 'hasta': dates[2]}
    days = re.search(r'\b(?:ventas|consumo)\s+(?:(?:de|los|en|durante|ultimos)\s+)*(\d+)\s+dias\b', value)
    if days:
        count = int(days[1])
        if not 1 <= count <= 367:
            raise AssistantError('Indica un período de ventas de entre 1 y 367 días.')
        today = datetime.now(timezone(timedelta(hours=-5))).date()
        return {'desde': str(today - timedelta(days=count - 1)), 'hasta': str(today)}
    return {}  # The native demand capability uses and labels the last 30 days.


def event_brief(result):
    reports = result.get('consultas') or []
    report = next((q['registros'][0] for q in reports if q.get('recurso') == 'eventos_cercanos' and q.get('registros')), {})
    if report.get('estado') in ('consultado', 'parcial') and re.search(r'^\s*\|', report.get('informe', ''), re.M):
        # Keep dates, sources and per-row uncertainty together, without another model call.
        return result.get('respuesta') or report['informe']
    state = report.get('estado')
    if state and state not in ('consultado', 'parcial'):
        return 'Eventos: no se obtuvo un informe verificado; esto no demuestra que no haya eventos. Continúo con los datos internos.'
    raw = report.get('informe') or result.get('respuesta', '')
    blocks, current = [], []
    verified_section = False
    block_verified = False
    for line in raw.splitlines():
        plain = tools.normalized(re.sub(r'[*_#`]', '', line)).strip()
        if plain.startswith('referencias sin cercania verificada'):
            break
        if plain.startswith('eventos con cercania verificada'):
            verified_section = True
            continue
        if re.match(r'^\s*(?:[-*•]|\d+[.)])\s+', line):
            if current:
                blocks.append((' '.join(current), block_verified))
            current, block_verified = [line.strip()], verified_section
        elif current:
            current.append(line.strip())
    if current:
        blocks.append((' '.join(current), block_verified))
    uncertainty = r'cercania por confirmar|sin cercania|no(?:\s+\w+){0,3}\s+verific'
    verified = [block for block, marked in blocks
                if (marked or 'cerca de:' in tools.normalized(block))
                and not re.search(uncertainty, tools.normalized(block))]
    uncertain = re.search(uncertainty, tools.normalized(raw))
    if uncertain and not verified:
        return 'Eventos: no pude verificar cercanía; esto no justifica incrementar el pedido. Las referencias y fuentes están en el detalle.'
    if verified:
        short = []
        for block in verified[:3]:
            if len(block) > 350:
                links = re.findall(r'https?://[^\s)]+', block)
                plain = re.sub(r'\[([^]]+)\]\([^)]+\)', r'\1', block)
                block = plain[:240].rstrip() + '…' + (f' [Fuente]({links[0]})' if links else '')
            short.append(block)
        label = 'Eventos (informe parcial)' if state == 'parcial' else 'Eventos'
        return label + ': referencias con cercanía verificada en el informe:\n' + '\n'.join(short) + '\nFuentes y limitaciones en el detalle.'
    if len(raw) > 650:
        return 'Eventos: el informe y sus fuentes están en el detalle. No se aplican incrementos automáticos por esos resultados.'
    return 'Eventos: ' + raw.strip()


@activity.agent('compras')
@activity.tool('revisar_base_reposicion')
def base(session):
    configuration.authorize('compras', 'pedido_sugerido')
    tools.authorize(session, 'pedido_sugerido')
    return tools.native('/ordenes-compra/pedido-sugerido?porcentaje=0')


def number(value):
    try:
        amount = Decimal(str(value))
        return format(amount.normalize(), 'f') if amount.is_finite() else 'no verificado'
    except (InvalidOperation, ValueError, TypeError):
        return 'no verificado'


@activity.agent('inventario')
@activity.tool('revisar_stock_reposicion')
def stock_report(session):
    configuration.authorize('inventario', 'stock')
    tools.authorize(session, 'stock')
    source = tools.native('/inventarios/stock')
    rows = source.get('productos') or []
    counts = {'AGOTADO':0, 'STOCK_BAJO':0, 'SIN_CONTEO':0, 'DISPONIBLE':0}
    alerts = []
    for row in rows:
        try:
            amount = Decimal(str(row.get('stock_actual')))
            minimum = Decimal(str(row.get('stock_minimo'))) if row.get('stock_minimo') is not None else None
            native_state = row.get('estado_stock')
            if not amount.is_finite() or native_state == 'SIN_CONTEO':
                state = 'SIN_CONTEO'
            elif native_state in counts:
                state = native_state
            else:
                state = ('AGOTADO' if amount <= 0 else 'STOCK_BAJO'
                         if minimum is not None and minimum.is_finite() and amount <= minimum else 'DISPONIBLE')
        except (InvalidOperation, ValueError, TypeError):
            state = 'SIN_CONTEO'
        counts[state] += 1
        if state != 'DISPONIBLE':
            alerts.append({k:row.get(k) for k in ('id_producto','nombre','unidad','stock_actual','stock_minimo')} | {'estado_stock':state})
    order = {'AGOTADO':0, 'STOCK_BAJO':1, 'SIN_CONTEO':2}
    alerts.sort(key=lambda row:(order[row['estado_stock']], row['nombre']))
    message = (f"### Stock actual registrado\n{len(rows)} insumos: {counts['AGOTADO']} agotados, "
               f"{counts['STOCK_BAJO']} bajo mínimo y {counts['SIN_CONTEO']} sin conteo verificado.")
    labels = {'AGOTADO':'agotado', 'STOCK_BAJO':'bajo mínimo', 'SIN_CONTEO':'sin conteo'}
    units = {'KGM':'kg', 'LTR':'L', 'C62':'unidades'}
    for row in alerts[:3]:
        unit = units.get(row.get('unidad'), row.get('unidad',''))
        detail = 'cantidad no verificada' if row['estado_stock'] == 'SIN_CONTEO' else f"{number(row['stock_actual'])} {unit}"
        message += f"\n- {row['nombre']}: {labels[row['estado_stock']]} ({detail})."
    if alerts:
        message += '\nEstas alertas requieren revisión; por sí solas no determinan una cantidad de compra.'
    return {'respuesta':message, 'recurso':'stock', 'registros':alerts[:5], 'total':len(alerts),
            'desde':0,'hay_mas':len(alerts)>5, 'contexto':{'total_insumos':len(rows),'resumen':counts}}


def next_step(state):
    if state.get('margen') is None:
        state['paso'] = 'porcentaje'
        return '¿Qué porcentaje de incremento deseas aplicar al consumo para este pedido? Indica 0% si no deseas incremento.'
    state['paso'] = 'analisis'
    return f'Conservo tu incremento de {state["margen"]}%. ¿Preparo la propuesta con ese porcentaje?'


def sales_only(result):
    queries, lines = [], []
    for query in result.get('consultas', []):
        source = query.get('contexto', {})
        if query.get('recurso') != 'demanda_rotacion':
            continue
        context = {k:source[k] for k in ('desde','hasta','dias_calendario','articulos','total_articulos','hay_mas_articulos') if k in source}
        context['alcance'] = 'SOLO_VENTAS'
        queries.append({'recurso':'demanda_rotacion','registros':[],'total':0,'desde':0,'hay_mas':False,'contexto':context})
        lines.append(f"Período de ventas: {source.get('desde')} al {source.get('hasta')}.")
        articles = source.get('articulos') or []
        for item in articles[:5]:
            lines.append(f"- {item['nombre']}: {number(item.get('cantidad'))} presentaciones vendidas.")
        if not articles:
            lines.append('No hay ventas cobradas registradas en este período; no demuestra falta de demanda.')
    if not lines:
        lines.append('No se obtuvo un detalle verificable de ventas.')
    return {'respuesta':'\n'.join(lines),'consultas':queries,'plan':None}


def replenishment(session, demand_result):
    suggestion = base(session)
    rows = suggestion.get('productos') or []
    messages = ['### Base de reposición sin incremento\n' + (suggestion.get('diagnostico') or {}).get('mensaje', 'Referencia nativa de consumo y stock.')]
    if rows:
        ranking = {r['id_producto']: i for q in (demand_result or {}).get('consultas', [])
                   for i, r in enumerate(q.get('registros', [])) if r.get('cobertura_dias') is not None and 'id_producto' in r}
        rows = sorted(rows, key=lambda row: ranking.get(row['id_producto'], 100000))
        units = {'KGM':'kg', 'LTR':'L', 'C62':'unidades'}
        for row in rows[:5]:
            unit = units.get(row.get('unidad'), row.get('unidad', ''))
            detail = f"stock {number(row.get('stock_actual'))} {unit}"
            if row.get('cantidad_sin_redondear') is not None:
                detail += f"; necesidad antes de redondear {number(row['cantidad_sin_redondear'])} {unit}"
            messages.append(f"- **{row['nombre']}: {number(row.get('cantidad_sugerida'))} {unit}** ({detail}).")
        messages.append(f'Se muestran {min(5,len(rows))} de {len(rows)} insumos sugeridos. La base usa su consumo registrado, stock actual y redondeo por presentación; puede usar un período distinto al análisis de ventas.')
    elif not (suggestion.get('diagnostico') or {}).get('mensaje'):
        messages.append('No se obtuvieron cantidades base; esto no demuestra que el stock sea suficiente.')
    query = {'recurso':'pedido_sugerido','registros':rows,'total':len(rows),'desde':0,'hay_mas':False,
             'diagnostico':suggestion.get('diagnostico', {}), 'porcentaje_incremento':0}
    return messages, query


def review(session, state, instruction, event_result, context=''):
    messages = [event_brief(event_result)]
    period = state.get('periodo_eventos')
    if period and len(period) == 2 and period[1] not in messages[0]:
        messages[0] = f'Período de eventos: {period[0]} al {period[1]} (hora de Lima).\n\n' + messages[0]
    local_name = (session.get('local_activo') or {}).get('nombre')
    if local_name and not messages[0].startswith('Sede:'):
        messages[0] = f'Sede: {local_name}\n\n' + messages[0]
    queries = list(event_result.get('consultas') or [])
    excluded = exclusions(instruction)
    demand_result = None
    if 'ventas' not in excluded:
        try:
            configuration.authorize('demanda', 'demanda_rotacion')
            tools.authorize(session, 'demanda_rotacion')
            demand_result = demand_agent.run(session, 'Analiza ventas, consumo y cobertura del stock del local activo.',
                                            '', context, bounded=True, filters=sales_filters(instruction))
            if 'stock' in excluded:
                demand_result = sales_only(demand_result)
            messages.append(demand_result['respuesta'])
            queries.extend(demand_result.get('consultas') or [])
        except AssistantError as error:
            messages.append(f'No pude completar el análisis de ventas y cobertura: {error}')
    if 'stock' not in excluded:
        try:
            stocks = stock_report(session)
            messages.append(stocks['respuesta'])
            queries.append({k:v for k,v in stocks.items() if k != 'respuesta'})
        except AssistantError as error:
            messages.append(f'No pude consultar el stock actual: {error}')
    if not {'stock','reposicion'} & excluded:
        try:
            base_messages, query = replenishment(session, demand_result)
            messages.extend(base_messages)
            queries.append(query)
        except AssistantError as error:
            messages.append(f'No pude revisar la base de reposición: {error}')
    state['revision_completada'] = True
    state['analisis'] = '\n\n'.join(messages[1:])[-6000:]
    messages.append(next_step(state))
    return {'respuesta':'\n\n'.join(messages), 'consultas':queries, 'plan':None, 'agente':'compras'}

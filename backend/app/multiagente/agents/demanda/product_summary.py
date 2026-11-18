"""Stable presentation of native product trends and ingredient availability."""
from app.multiagente.agents.tables import table,number,quantity


def render(query):
    context=query.get('contexto',{})
    outlook=context.get('analisis_productos')
    if not outlook: return None
    items=outlook['articulos']
    periods=outlook.get('periodos',{})
    current=periods.get('ultimos7',{})
    prior=periods.get('anteriores7',{})
    lines=[f"Período analizado: {context.get('desde','—')} al {context.get('hasta','—')}.",
           '### Productos más vendidos: tendencia y duración estimada',
           f"Últimos 7 días calendario: {current.get('desde','—')} al {current.get('hasta','—')}. Comparación: {prior.get('desde','—')} al {prior.get('hasta','—')}."]
    lines.append('El promedio diario y la duraci\u00f3n del stock usan el per\u00edodo solicitado; la tendencia compara las dos semanas indicadas.')
    if context.get('local'): lines.insert(0,'Local: '+context['local'])
    # Incomplete history must not hide the available business analysis.
    lines.append(table(['Producto','Ventas del período','Promedio por día','7 días anteriores','Últimos 7 días','Tendencia','Días estimados','Insumo limitante'],[
        [r.get('nombre'),number(r.get('cantidad')),number(r.get('ventas_diarias'),2),number(r.get('ventas_anteriores7')),number(r.get('ventas_ultimos7')),
         r['tendencia'].replace(' en registros (provisional)', ' en registros')+(f" ({number(r['cambio_porcentaje'],2)}%)" if r.get('cambio_porcentaje') is not None else ''),
         number(r['cobertura_dias'],2) if r.get('cobertura_dias') is not None else r['estado_cobertura'],r.get('insumo_limitante')]
        for r in items]))
    if not items: lines.append('No hay productos de venta con cobros registrados en el período elegido.')
    weeks=[w for w in periods.get('semanas_completas',[]) if w['desde']>=context.get('desde','')]
    if weeks and items:
        def amount(row,week):
            found=next((w for w in row.get('semanas',[]) if w.get('desde')==week['desde']),None)
            return number(found.get('cantidad')) if found else '—'
        lines+=['### Comparación entre semanas completas',table(['Producto']+[f"{w['desde']} al {w['hasta']}" for w in weeks],
                                                               [[r.get('nombre')]+[amount(r,w) for w in weeks] for r in items])]
    base=periods.get('base_cobertura',{})
    lines+=['### Insumos de estos productos',f"Consumo total del local: {base.get('desde','—')} al {base.get('hasta','—')}.",
            table(['Insumo','Stock actual','Consumo diario total','Días estimados','Estado'],[
                [r.get('nombre'),quantity(r.get('stock_actual'),r.get('unidad')),quantity(r.get('consumo_diario'),r.get('unidad')),
                 number(r.get('cobertura_dias'),2),('Estimada' if r.get('estado_cobertura')=='Provisional' else r.get('estado_cobertura'))] for r in outlook['insumos']]),
            outlook['nota']]
    if outlook.get('total_articulos',len(items))>len(items):
        lines.append(f"Se consultaron {len(items)} de {outlook['total_articulos']} productos; puedes pedir los siguientes.")
    return '\n\n'.join(lines)

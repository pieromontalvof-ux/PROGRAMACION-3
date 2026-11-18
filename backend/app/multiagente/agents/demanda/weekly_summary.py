"""Presentation adapter; weekly business calculations belong to native inventory."""
from app.multiagente.api import configuration, tools
from app.multiagente.agents.tables import table, quantity, number


def analyze(session,dias_abastecimiento=7):
    configuration.authorize('demanda','demanda_rotacion')
    tools.authorize(session,'demanda_rotacion')
    report=tools.native('/inventario-operativo/plan-semanal'+(f'?dias={dias_abastecimiento}' if dias_abastecimiento!=7 else ''))
    periods=report.get('periodos',{})
    history=periods.get('ultimos7',{})
    lines=['### Artículos con mayor salida',
           f"Ventas: {history.get('desde','—')} al {history.get('hasta','—')}. Comparación con los siete días anteriores."]
    articles=report.get('articulos',[])
    missing=report.get('metadata',{}).get('fechas_sin_registro',[])
    if any(r.get('estado_ultimos7')=='INSUFICIENTE' or r.get('estado_anteriores7')=='INSUFICIENTE' for r in articles):
        lines.append('Parcial significa que faltan días por confirmar; no es el total definitivo. Fechas sin registro: '+', '.join(missing)+'.')
    lines.append(table(['Producto','Últimos 7 días','7 días anteriores','Cambio (%)'],[
        [r.get('nombre'),number(r.get('cantidad'))+(' (parcial)' if r.get('estado_ultimos7')=='INSUFICIENTE' else ''),
         number(r.get('cantidad_anterior'))+(' (parcial)' if r.get('estado_anteriores7')=='INSUFICIENTE' else ''),
         number(r.get('variacion_porcentaje'),2)] for r in articles]))
    weeks=periods.get('semanas_completas',[])
    if weeks:
        labels=[f"{w.get('desde','—')} al {w.get('hasta','—')}" for w in weeks]
        lines+=['### Comparación entre semanas completas',table(['Producto']+labels,[
            [r.get('nombre')]+[(number(v.get('cantidad'))+(' (parcial)' if v.get('estado_historial')=='INSUFICIENTE' else '')) if isinstance(v,dict) else number(v) for v in r.get('semanas',[])]
            for r in articles])]
    lines+=['### Insumos con menor cobertura estimada']
    base=periods.get('base_cobertura',{})
    lines.append(f"Consumo de los últimos 20 días completos: {base.get('desde','—')} al {base.get('hasta','—')}. Solo cobertura de hasta 10 días.")
    products=[r for r in report.get('productos',[]) if r.get('cobertura_dias') is not None and 0<=r['cobertura_dias']<=10]
    lines.append(table(['Insumo','Stock','Consumo diario','Cobertura estimada (días)'],[
        [r.get('nombre'),quantity(r.get('stock_actual'),r.get('unidad')),
         quantity(r.get('consumo_diario'),r.get('unidad')),number(r.get('cobertura_dias'),2)] for r in products]))
    if not products:
        if report.get('metadata',{}).get('cobertura_completa') is False:
            missing_coverage=report['metadata'].get('fechas_sin_registro_cobertura',[])
            lines.append('No se pudo calcular la cobertura: falta confirmar información de '+', '.join(missing_coverage)+'.')
        else:
            lines.append('No hay insumos con cobertura calculada de 10 días o menos.')
    if report.get('advertencias'):
        lines.extend(str(w) for w in report['advertencias'])
    query={'recurso':'demanda_rotacion','registros':report.get('productos',[]),
           'total':len(report.get('productos',[])),'desde':0,'hay_mas':False,
           'contexto':{**periods,'articulos':articles,'plan_semanal':report,'horizonte':'semanal'}}
    return {'respuesta':'\n\n'.join(lines),'consultas':[query],'plan':None}

"""One scoped read; concise tables preserve native demand evidence in metadata."""
from app.multiagente.api import configuration, demand
from app.multiagente.agents.tables import sales, table, quantity, number


def analyze(session, filters):
    if filters.get('semanal') is True:
        from .weekly_summary import analyze as weekly
        return weekly(session,filters.get('dias_abastecimiento',7))
    configuration.authorize('demanda','demanda_rotacion')
    report=demand.read(session,filters)
    items=report.get('contexto',{}).get('articulos',[])
    lines=['### Artículos con mayor salida']
    lines.append(sales(items) if items else 'No hay ventas cobradas registradas.')
    products=[row for row in report.get('registros',[]) if row.get('cobertura_dias') is not None]
    lines+=['### Insumos con menor cobertura estimada']
    if products:
        lines.append(table(['Insumo','Stock','Consumo diario','Cobertura estimada (días)'],[
            [r.get('nombre'),quantity(r.get('stock_actual'),r.get('unidad')),
             quantity(r.get('consumo_diario'),r.get('unidad')),number(r.get('cobertura_dias'),2)] for r in products]))
    else:
        lines.append('Sin consumo registrado para estimar cobertura.')
    return {'respuesta':'\n\n'.join(lines),'consultas':[report],'plan':None}

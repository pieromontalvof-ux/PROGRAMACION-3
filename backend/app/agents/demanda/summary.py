"""One scoped read for the standard guided analysis; no model pagination loop."""
from app.modules.asistente_ia import configuration, demand


def analyze(session, filters):
    configuration.authorize('demanda', 'demanda_rotacion')
    report = demand.read(session, filters)
    context = report.get('contexto', {})
    lines = [f"Período analizado: {context.get('desde')} al {context.get('hasta')} "
             f"({context.get('dias_calendario')} días calendario)."]
    items = context.get('articulos', [])
    if items:
        lines += ['', '### Artículos con mayor salida']
        for item in items[:5]:
            lines.append(f"- {item.get('nombre')}: {item.get('cantidad', 0)} presentaciones; "
                         f"promedio diario {item.get('ventas_diarias', 0)}.")
        lines.append('Ranking por presentaciones; no equivale a ingresos ni consumo de insumos. '
                     'Las elecciones de promociones no deben sumarse de nuevo a sus combos.')
    else:
        lines.append('No hay ventas cobradas registradas en este período. Esto no demuestra falta de demanda.')
    products = [row for row in report.get('registros', []) if row.get('cobertura_dias') is not None]
    if products:
        lines += ['', '### Insumos con menor cobertura estimada']
        units = {'KGM': 'kg', 'LTR': 'L', 'C62': 'unidad'}
        for row in products[:5]:
            unit = units.get(row.get('unidad'), row.get('unidad', ''))
            lines.append(f"- {row.get('nombre')}: stock {row.get('stock_actual', 0)} {unit}; "
                         f"consumo diario {row.get('consumo_diario', 0)} {unit}; "
                         f"cobertura orientativa {row['cobertura_dias']} días.")
    else:
        lines.append('No se puede estimar cobertura sin consumo registrado; no significa que el stock sea suficiente.')
    summary = context.get('resumen', {})
    if summary:
        lines.append(f"Se evaluaron {report.get('total', 0)} insumos; "
                     f"{summary.get('productos_con_consumo', 0)} tienen consumo de ventas en este período.")
    lines += ['', 'Se muestran hasta 5 resultados de cada ranking. Puedes pedir el detalle por artículo o insumo. '
              'La cobertura usa el stock actual y días calendario; no predice agotamiento exacto ni prueba el efecto de eventos.',
              'Este análisis histórico no cambia el período ni la fórmula del pedido sugerido.']
    return {'respuesta': '\n'.join(lines), 'consultas': [report], 'plan': None}

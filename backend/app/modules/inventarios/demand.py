"""Read-only demand based on paid receipts and their recorded inventory consumption."""

from sqlalchemy import bindparam, func, select
from decimal import Decimal


def calculate(start, end, items, products):
    days = (end - start).days + 1
    articles = []
    for source in items:
        row = dict(source)
        row['ventas_diarias'] = round(float(row['cantidad']) / days, 4)
        articles.append(row)
    results = []
    for source in products:
        row = dict(source)
        consumption = Decimal(str(row['consumo_ventas']))
        stock = Decimal(str(row['stock_actual']))
        daily = consumption / days
        coverage = max(stock, Decimal(0)) / daily if daily > 0 else None
        row.update(consumo_diario=round(float(daily), 4),
                   cobertura_dias=round(float(coverage), 2) if coverage is not None else None,
                   prioridad=('SIN_CONSUMO_REGISTRADO' if coverage is None else
                              'REVISAR_REPOSICION' if coverage <= 7 else 'COBERTURA_MAYOR_A_7_DIAS'))
        results.append(row)
    # Do not rank heterogeneous units by their raw consumption quantities.
    results.sort(key=lambda r: (r['cobertura_dias'] is None,
                               r['cobertura_dias'] if r['cobertura_dias'] is not None else 0,
                               r['nombre']))
    articles.sort(key=lambda r: (-float(r['cantidad']), r['nombre']))
    return dict(desde=start.isoformat(), hasta=end.isoformat(), dias_calendario=days,
                articulos=articles, productos=results,
                metodologia='Ventas cobradas y consumo histórico guardado al cobrar; promedio por días calendario inclusivos. '
                'Stock actual al consultar, no stock al final del periodo. Cobertura orientativa; 7 días es una alerta, '
                'no el plazo del proveedor. No incluye mermas ni traslados como ventas. '
                'Cantidad de presentaciones incluye elecciones de promociones; los combos tienen id_promocion '
                'y su importe no se reparte entre elecciones. No sumar combos y elecciones. '
                'No mide días con disponibilidad ni agotamiento por lote. Sin ventas registradas no demuestra falta de demanda.')


def report(local, start, end):
    from .operativo import filas, serial
    params = dict(local=local, desde=start, hasta=end)
    items = filas(select(func.public.inv_demand_report_1(bindparam('local'), bindparam('desde'), bindparam('hasta')).table_valued(
        'id_presentacion', 'id_promocion', 'nombre', 'id_item_carta', 'categoria', 'cantidad',
        'total', 'cantidad_en_promociones'
    )), params)
    products = filas(select(func.public.inv_demand_report_2(bindparam('local'), bindparam('desde'), bindparam('hasta')).table_valued(
        'id_producto', 'codigo', 'nombre', 'unidad', 'categoria', 'stock_actual',
        'consumo_ventas', 'entradas'
    )), params)
    return serial(calculate(start, end, items, products))

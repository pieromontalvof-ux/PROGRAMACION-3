"""Read-only demand based on paid receipts and their recorded inventory consumption."""
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
    items = filas('''WITH lineas AS (
        SELECT c.creado_en,linea
        FROM salon_cobro c CROSS JOIN LATERAL jsonb_array_elements(c.comprobante->'lineas') linea
        WHERE c.id_local=:local AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN :desde AND :hasta
      ), demanda AS (
        SELECT creado_en,(linea->>'id_presentacion')::int id_presentacion,
          (linea->>'id_promocion')::int id_promocion,linea->>'nombre' nombre,
          (linea->>'cantidad')::numeric cantidad,
          (linea->>'cantidad')::numeric*(linea->>'precio')::numeric total,
          0::numeric cantidad_en_promociones FROM lineas
        UNION ALL
        SELECT creado_en,(opcion->>'id_presentacion')::int,NULL,opcion->>'nombre',
          (linea->>'cantidad')::numeric,0::numeric,(linea->>'cantidad')::numeric
          FROM lineas CROSS JOIN LATERAL jsonb_array_elements(coalesce(linea->'selecciones_promocion','[]'::jsonb)) opcion
          WHERE (linea->>'id_promocion') IS NOT NULL
      ) SELECT d.id_presentacion,d.id_promocion,
        (array_agg(d.nombre ORDER BY d.creado_en DESC))[1] nombre,
        pv.id_item_carta,cc.nombre categoria,sum(d.cantidad) cantidad,
        sum(d.total) total,sum(d.cantidad_en_promociones) cantidad_en_promociones
        FROM demanda d
        LEFT JOIN presentacion_venta pv ON pv.id_presentacion_venta=d.id_presentacion
        LEFT JOIN item_carta ic ON ic.id_item_carta=pv.id_item_carta
        LEFT JOIN categoria_carta cc ON cc.id_categoria_carta=ic.id_categoria_carta
        GROUP BY d.id_presentacion,d.id_promocion,pv.id_item_carta,cc.nombre''', params)
    products = filas('''WITH consumo AS (
        SELECT d.id_producto,sum(d.cantidad) consumo_ventas
        FROM salon_cobro c
        JOIN movimiento_inventario m ON m.id_movimiento_inventario=c.id_movimiento AND m.id_local=c.id_local
        JOIN movimiento_inventario_detalle d USING(id_movimiento_inventario)
        WHERE c.id_local=:local AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN :desde AND :hasta
        GROUP BY d.id_producto
      ), entradas AS (
        SELECT id_producto,sum(greatest(cantidad,0)) entradas FROM inventario_evento
        WHERE id_local=:local AND (registrado_en AT TIME ZONE 'America/Lima')::date BETWEEN :desde AND :hasta
        GROUP BY id_producto
      ) SELECT p.id_producto,p.codigo,p.nombre,p.unidad,cat.nombre categoria,
        coalesce(s.stock_actual,0) stock_actual,coalesce(c.consumo_ventas,0) consumo_ventas,
        coalesce(e.entradas,0) entradas
      FROM producto p LEFT JOIN categoria_producto cat ON cat.id_categoria=p.id_categoria
      LEFT JOIN inventario_stock_teorico s ON s.id_producto=p.id_producto AND s.id_local=:local
      LEFT JOIN consumo c ON c.id_producto=p.id_producto
      LEFT JOIN entradas e ON e.id_producto=p.id_producto
      WHERE p.activo OR c.id_producto IS NOT NULL OR coalesce(s.stock_actual,0)<>0''', params)
    return serial(calculate(start, end, items, products))

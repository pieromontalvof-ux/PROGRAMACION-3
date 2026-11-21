"""Read-only cross-store promotion evidence, separate from store operations."""
from decimal import Decimal
from .demand import report as local_report


def combine(start,end,stores):
    articles={};products={};coverage=[]
    days=(end-start).days+1
    for store in stores:
        identity=store['id_local'];name=store['nombre']
        known=set(store['productos_con_stock'])
        verified=store.get('cobros_con_inventario',store['cobros'])
        complete=verified==store['cobros']
        coverage.append({key:store[key] for key in ('id_local','nombre','cobros','dias_con_ventas')})
        coverage[-1].update(productos_con_stock=len(known),
                            cobros_con_inventario=verified,
                            estado_ventas='CON_VENTAS_REGISTRADAS' if store['cobros'] else 'SIN_VENTAS_REGISTRADAS',
                            estado_stock='CON_STOCK_REGISTRADO' if known else 'SIN_STOCK_REGISTRADO',
                            estado='CON_DATOS' if store['cobros'] or known else 'SIN_DATOS')
        for source in store['reporte'].get('articulos',[]):
            key=(source.get('id_presentacion'),source.get('id_promocion'))
            row=articles.setdefault(key,{**source,'cantidad':Decimal(0),'total':Decimal(0),
                                         'cantidad_en_promociones':Decimal(0),'locales':[]})
            for field in ('cantidad','total','cantidad_en_promociones'):
                row[field]+=Decimal(str(source.get(field) or 0))
            row['locales'].append(dict(id_local=identity,local=name,cantidad=source['cantidad']))
        for source in store['reporte'].get('productos',[]):
            row=products.setdefault(source['id_producto'],{key:source.get(key) for key in ('id_producto','codigo','nombre','unidad','categoria')})
            row.setdefault('stock_total_registrado',Decimal(0));row.setdefault('consumo_ventas',Decimal(0));row.setdefault('locales',[])
            observed=source['id_producto'] in known
            stock=source['stock_actual'] if observed else None
            row['stock_total_registrado']+=Decimal(str(stock or 0))
            row['consumo_ventas']+=Decimal(str(source['consumo_ventas']))
            row['locales'].append(dict(id_local=identity,local=name,stock_actual=stock,
                consumo_diario=source['consumo_diario'],consumo_verificado=complete,
                cobertura_dias=source['cobertura_dias'] if observed and complete else None))
    for row in articles.values():row['ventas_diarias']=float(row['cantidad'])/days
    for row in products.values():
        values=[local['cobertura_dias'] for local in row['locales'] if local['cobertura_dias'] is not None]
        row['cobertura_minima_dias']=min(values) if values else None
        row['consumo_diario']=float(row['consumo_ventas'])/days
    return dict(alcance='GLOBAL',desde=start.isoformat(),hasta=end.isoformat(),dias_calendario=days,
        locales=coverage,articulos=sorted(articles.values(),key=lambda row:-row['cantidad']),
        productos=sorted(products.values(),key=lambda row:(row['cobertura_minima_dias'] is None,row['cobertura_minima_dias'] or 0,row['nombre'])),
        metodologia='Ventas cobradas agregadas por identidad de presentación; incluye elecciones de promociones sin sumar de nuevo sus combos. '
        'Stock actual y cobertura separados por tienda. El stock total no implica disponibilidad en otra sede ni autoriza traslados. '
        'Sin saldo inicial ni eventos de inventario, el stock es desconocido, no cero. Días con ventas no equivalen a días abiertos ni prueban historial completo.')


def report(start,end):
    from .operativo import filas,serial
    stores=filas('''SELECT l.id_local,l.nombre,count(c.id_cobro) cobros,
        count(m.id_movimiento_inventario) cobros_con_inventario,
        count(DISTINCT (c.creado_en AT TIME ZONE 'America/Lima')::date) dias_con_ventas
        FROM local l LEFT JOIN salon_cobro c ON c.id_local=l.id_local AND c.comprobante->'anulacion' IS NULL
        AND (c.creado_en AT TIME ZONE 'America/Lima')::date BETWEEN :desde AND :hasta
        LEFT JOIN movimiento_inventario m ON m.id_movimiento_inventario=c.id_movimiento AND m.id_local=l.id_local
        WHERE l.estado_registro=1 GROUP BY l.id_local,l.nombre ORDER BY l.id_local''',dict(desde=start,hasta=end))
    registered=filas('''SELECT id_local,id_producto FROM inventario_saldo_inicial
                        UNION SELECT id_local,id_producto FROM inventario_evento''')
    for store in stores:
        store['productos_con_stock']=[r['id_producto'] for r in registered if r['id_local']==store['id_local']]
        store['reporte']=local_report(store['id_local'],start,end) if store['cobros'] or store['productos_con_stock'] else {}
    result=combine(start,end,stores)
    presentations=filas('''SELECT pv.id_presentacion_venta id_presentacion,ic.nombre,ic.tipo,
        pv.contenido,pv.unidad,pv.precio,pv.activo,m.nombre menaje
        FROM presentacion_venta pv JOIN item_carta ic USING(id_item_carta)
        JOIN menaje m USING(id_menaje)''')
    by_id={row['id_presentacion']:row for row in presentations}
    for article in result['articulos']:
        article['presentacion']=by_id.get(article.get('id_presentacion'))
    return serial(result)

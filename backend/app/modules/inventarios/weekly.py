"""Read-only weekly purchasing capacity. Sales consumption only; no agent dependencies."""

from sqlalchemy import bindparam, func, select
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal, ROUND_CEILING


def period(start, end):
    return dict(desde=start.isoformat(), hasta=end.isoformat(), dias=(end-start).days+1)


def validate_days(dias):
    if isinstance(dias, bool) or not (isinstance(dias, int) or isinstance(dias, str) and dias.isascii() and dias.isdigit()):
        raise ValueError('Los días de abastecimiento deben ser un entero entre 1 y 90')
    dias = int(dias)
    if not 1 <= dias <= 90:
        raise ValueError('Los días de abastecimiento deben estar entre 1 y 90')
    return dias


def delivery_date(today, dias=7):
    """Default delivery boundary of the native seven-day replenishment cycle."""
    return today+timedelta(days=validate_days(dias))


def calculate(today, items_daily, consumption_daily, products, coverage_daily, porcentaje=0, dias=7):
    dias = validate_days(dias)
    pct = Decimal(str(porcentaje))
    if not pct.is_finite() or not 0 <= pct <= 1000:
        raise ValueError('El porcentaje debe estar entre 0 y 1000')
    end = today-timedelta(days=1)
    start = today-timedelta(days=28)
    monday = today-timedelta(days=today.weekday())
    weeks = [period(monday-timedelta(days=28-7*i), monday-timedelta(days=22-7*i)) for i in range(4)]
    recent = period(today-timedelta(days=7), end)
    previous = period(today-timedelta(days=14), today-timedelta(days=8))
    dates = [start+timedelta(days=i) for i in range(28)]
    def day(value):
        return value.isoformat() if hasattr(value, 'isoformat') else str(value)
    coverage = {day(r['fecha']): r for r in coverage_daily}
    def observed(row):
        return ((row.get('cobros',0)>0 or row.get('jornada_cerrada') is True)
                and row.get('cobros_con_inventario',0)==row.get('cobros',0))
    receipts = sum(coverage.get(day(d), {}).get('cobros', 0)>0 for d in dates)
    inventory = sum(observed(coverage.get(day(d), {})) for d in dates)
    complete = inventory == 28
    def weekly_status(w):
        first=date.fromisoformat(w['desde'])
        records = [coverage.get(day(first+timedelta(days=i)), {}) for i in range(w['dias'])]
        return 'COMPLETO' if len(records)==7 and all(observed(r) for r in records) else 'INSUFICIENTE'
    recent_status,prior_status=weekly_status(recent),weekly_status(previous)
    articles = {}
    for source in items_daily:
        key = (source.get('id_presentacion'), source.get('id_promocion'))
        row = articles.setdefault(key, {k:v for k,v in source.items() if k not in ('fecha','cantidad')})
        row.setdefault('_daily', {})[day(source['fecha'])] = row.setdefault('_daily', {}).get(day(source['fecha']), Decimal(0))+Decimal(str(source['cantidad']))
    for row in articles.values():
        daily = row.pop('_daily')
        def total(p):
            return float(sum((n for d,n in daily.items() if p['desde']<=d<=p['hasta']), Decimal(0)))
        current, prior = total(recent), total(previous)
        row.update(cantidad=current, cantidad_anterior=prior, variacion=current-prior,
                   estado_ultimos7=recent_status,estado_anteriores7=prior_status,
                   variacion_porcentaje=(current-prior)/prior*100 if prior and recent_status==prior_status=='COMPLETO' else None,
                   semanas=[dict(**w, cantidad=total(w), estado_historial=weekly_status(w)) for w in weeks])
    consumption = {}
    weekday_consumption = {}
    coverage_start=today-timedelta(days=20)
    coverage_consumption={}
    observed_consumption={}
    observed_days=sum(observed(coverage.get(day(coverage_start+timedelta(days=i)),{})) for i in range(20))
    coverage_complete=all(observed(coverage.get(day(coverage_start+timedelta(days=i)),{})) for i in range(20))
    for row in consumption_daily:
        if start.isoformat()<=day(row['fecha'])<=end.isoformat():
            key = row['id_producto']
            consumption[key] = consumption.get(key, Decimal(0))+Decimal(str(row['cantidad']))
            weekday = date.fromisoformat(day(row['fecha'])).weekday()
            amounts = weekday_consumption.setdefault(key, {})
            amounts[weekday] = amounts.get(weekday, Decimal(0))+Decimal(str(row['cantidad']))
        if coverage_start.isoformat()<=day(row['fecha'])<=end.isoformat():
            key=row['id_producto']
            coverage_consumption[key]=coverage_consumption.get(key,Decimal(0))+Decimal(str(row['cantidad']))
            if observed(coverage.get(day(row['fecha']),{})):
                observed_consumption[key]=observed_consumption.get(key,Decimal(0))+Decimal(str(row['cantidad']))
    results = []
    warnings = [] if complete else ['Historial insuficiente: faltan días con cobros o inventario vinculado; no se genera pedido.']
    for source in products:
        row = dict(source)
        amount = consumption.get(row['id_producto'], Decimal(0))
        stock = Decimal(str(row.get('stock_actual') or 0))
        pack = Decimal(str(row.get('presentacion') or 1))
        if pack<=0: pack=Decimal(1)
        # Each weekday has four historical observations; sum the requested future days.
        weekdays = weekday_consumption.get(row['id_producto'], {})
        forecast = sum((weekdays.get((today+timedelta(days=i)).weekday(), Decimal(0))/4 for i in range(dias)), Decimal(0))
        projected = forecast*(1+pct/100) if complete and row.get('stock_actual') is not None else None
        projected_week = amount/4*(1+pct/100) if projected is not None else None
        net = max(Decimal(0), projected-stock) if projected is not None else None
        packages = int((net/pack).to_integral_value(rounding=ROUND_CEILING)) if net is not None else None
        daily = coverage_consumption.get(row['id_producto'],Decimal(0))/20 if coverage_complete and row.get('stock_actual') is not None else None
        # Read-only fallback, never used for authoritative purchase quantities.
        observed_daily=observed_consumption.get(row['id_producto'],Decimal(0))/observed_days if observed_days else None
        row.update(dias_observados_cobertura=observed_days,
                   consumo_diario_observado=float(observed_daily) if observed_daily is not None else None,
                   cobertura_provisional_dias=float(stock/observed_daily) if observed_daily and row.get('stock_actual') is not None and stock>=0 else None)
        row.update(consumo_ventas_28_dias=float(amount), consumo_diario=float(daily) if daily is not None else None,
                   consumo_proyectado=float(projected) if projected is not None else None,
                   consumo_proyectado_7_dias=float(projected_week) if projected_week is not None else None,
                   cantidad_sin_redondear=float(net) if net is not None else None,
                   cantidad_sugerida=float(pack*packages) if packages is not None else None,
                   paquetes_sugeridos=packages, cobertura_dias=float(max(stock,Decimal(0))/daily) if daily else None,
                   estado_historial='COMPLETO' if complete else 'INSUFICIENTE',
                   supera_stock_maximo=(stock+pack*packages>Decimal(str(row['stock_maximo']))) if packages is not None and row.get('stock_maximo') is not None else None)
        results.append(row)
        if row.get('stock_actual') is None:
            warnings.append(f"{row['nombre']}: no hay stock actual registrado; revisar antes de comprar.")
        if not row.get('compra_habilitada', True):
            warnings.append(f"{row['nombre']}: producto, categoría o proveedor no habilitado para compra.")
        if row['supera_stock_maximo']:
            warnings.append(f"{row['nombre']}: la reposición supera el stock máximo configurado.")
    results.sort(key=lambda r:(r['cobertura_dias'] is None,r['cobertura_dias'] or 0,r['nombre']))
    return dict(periodos=dict(proyeccion=period(today,today+timedelta(days=dias-1)),proxima_entrega=delivery_date(today,dias).isoformat(),base_proyeccion=period(start,end),base_cobertura=period(coverage_start,end),
                             ultimos7=recent,anteriores7=previous,semanas_completas=weeks),
                articulos=sorted(articles.values(),key=lambda r:-r['cantidad']), productos=results,
                reposicion=[r for r in results if r.get('compra_habilitada',True) and (r['cantidad_sugerida'] or 0)>0], advertencias=warnings,
                comparaciones=dict(ultimos7=recent,anteriores7=previous,semanas_completas=weeks),
                metadata=dict(fecha_consulta=today.isoformat(),porcentaje=float(pct),dias_abastecimiento=dias,dias_con_cobros=receipts,
                              dias_con_inventario=inventory,dias_requeridos=28,historial_completo=complete,
                              fechas_sin_registro=[day(d) for d in dates if not observed(coverage.get(day(d),{}))],
                              cobertura_completa=coverage_complete,
                              fechas_sin_registro_cobertura=[day(coverage_start+timedelta(days=i)) for i in range(20)
                                  if not observed(coverage.get(day(coverage_start+timedelta(days=i)),{}))],
                              metodologia=f'Consumo de ventas cobradas: cuatro observaciones por día de semana; {dias} días desde hoy. '
                              'Los cierres sin cobros son cero observado; sin cierre ni cobros vinculados el día es desconocido. '
                              'No incluye mermas ni traslados. Stock actual, no histórico. Redondeo de paquetes hacia arriba; '
                              'el máximo es una advertencia y no reduce la demanda. No mide disponibilidad ni demanda perdida.'))


def report(local, today=None, porcentaje=0, dias=7):
    dias = validate_days(dias)
    from .operativo import filas, serial
    today = today or datetime.now(timezone(timedelta(hours=-5))).date()
    monday = today-timedelta(days=today.weekday())
    params = dict(local=local, desde=min(today-timedelta(days=28),monday-timedelta(days=28)), hasta=today-timedelta(days=1))
    coverage = filas(select(func.public.inv_weekly_report_1(bindparam('local'), bindparam('desde'), bindparam('hasta')).table_valued(
        'fecha', 'cobros', 'cobros_con_inventario', 'jornada_cerrada'
    )),params)
    items = filas(select(func.public.inv_weekly_report_2(bindparam('local'), bindparam('desde'), bindparam('hasta')).table_valued(
        'fecha', 'id_presentacion', 'id_promocion', 'nombre', 'cantidad'
    )), params)
    consumption = filas(select(func.public.inv_weekly_report_3(bindparam('local'), bindparam('desde'), bindparam('hasta')).table_valued(
        'fecha', 'id_producto', 'cantidad'
    )),params)
    products = filas(select(func.public.inv_weekly_report_4(bindparam('local')).table_valued(
        'id_producto', 'codigo', 'nombre', 'unidad', 'presentacion', 'id_categoria',
        'categoria', 'id_proveedor', 'proveedor', 'stock_actual', 'compra_habilitada',
        'stock_minimo', 'stock_maximo'
    )),params)
    return serial(calculate(today,items,consumption,products,coverage,porcentaje,dias))

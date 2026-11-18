"""Read-only product availability from recipes and shared recorded consumption.

Recipes identify dependencies only. Consumption rates come from paid sales of
the whole menu, never from pretending an ingredient is exclusive to one drink.
"""
from datetime import datetime, timedelta, timezone


def calculate(historical, weekly, recipes, subproducts, known_stock, start):
    requested_period='productos' in historical and historical.get('dias_calendario',0)>0
    products={r['id_producto']:dict(r) for r in (historical.get('productos',[]) if requested_period else weekly.get('productos',[]))}
    subs={r['id_subproducto']:r for r in subproducts}
    recipe_by_item={r['id_presentacion_venta']:r for r in recipes if r.get('activo',True)}
    recent={r.get('id_presentacion'):r for r in weekly.get('articulos',[]) if not r.get('id_promocion')}
    periods=dict(weekly.get('periodos',{}))
    if requested_period:
        periods['base_cobertura']={'desde':historical.get('desde',start.isoformat()),'hasta':historical.get('hasta'),
                                   'dias':historical.get('dias_calendario')}
    coverage_start=periods.get('base_cobertura',{}).get('desde')
    coverage_complete=weekly.get('metadata',{}).get('cobertura_completa') is True and bool(coverage_start and coverage_start>=start.isoformat())
    prior_start=periods.get('anteriores7',{}).get('desde')
    used=set()

    def ingredient_state(pid):
        row=products.get(pid)
        if row is None: return 'Sin datos del insumo'
        if row.get('stock_actual') is not None and row['stock_actual']<0: return 'Revisar stock negativo'
        if pid not in known_stock or row.get('stock_actual') is None: return 'Sin stock verificado'
        if requested_period:
            if row.get('cobertura_dias') is None: return 'Sin consumo registrado para estimar'
            return 'Provisional' if historical.get('fechas_sin_registro') else 'Estimada'
        if not coverage_complete:

            if (coverage_start and coverage_start>=start.isoformat() and row.get('cobertura_provisional_dias') is not None):
                return 'Provisional'
            return 'Historial reciente incompleto'
        if row.get('cobertura_dias') is None: return 'Sin consumo reciente para estimar'
        return 'Estimada'

    for pid,row in products.items():
        if not requested_period and ingredient_state(pid)=='Provisional':
            row['cobertura_dias']=row['cobertura_provisional_dias']
            row['consumo_diario']=row['consumo_diario_observado']
    articles=[]
    for source in historical.get('articulos',[]):
        if source.get('id_promocion') or not source.get('id_presentacion') or float(source.get('cantidad') or 0)<=0:
            continue
        row=dict(source)
        days=historical.get('dias_calendario',0)
        row['ventas_diarias']=float(source.get('cantidad') or 0)/days if days else source.get('ventas_diarias')
        current=recent.get(row['id_presentacion'],{})
        complete=(current.get('estado_ultimos7')=='COMPLETO' and current.get('estado_anteriores7')=='COMPLETO'
                  and bool(prior_start and prior_start>=start.isoformat()))
        change=current.get('variacion_porcentaje') if complete else None
        recent_start=periods.get('ultimos7',{}).get('desde')
        provisional=False
        if (not complete and prior_start and prior_start>=start.isoformat()
                and current.get('cantidad') is not None and current.get('cantidad_anterior',0)>0):
            change=(current['cantidad']-current['cantidad_anterior'])/current['cantidad_anterior']*100
            provisional=True
        row.update(ventas_ultimos7=current.get('cantidad') if recent_start and recent_start>=start.isoformat() else None,
                   ventas_anteriores7=current.get('cantidad_anterior') if prior_start and prior_start>=start.isoformat() else None,
                   cambio_porcentaje=change,tendencia=('Sube' if change>0 else 'Baja' if change<0 else 'Estable') if change is not None else 'Sin comparación completa',
                   semanas=current.get('semanas',[]),cobertura_dias=None,insumo_limitante=None)
        row['comparacion_provisional']=provisional
        if provisional: row['tendencia']+=' en registros (provisional)'
        recipe=recipe_by_item.get(row['id_presentacion'])
        dependencies=set()
        issue=None
        if not recipe or not recipe.get('componentes'):
            issue='Sin receta activa completa'
        else:
            if recipe.get('id_grupo_salsa') or recipe.get('grupo_salsa'):
                issue='Revisar ingredientes opcionales'
            for component in recipe['componentes']:
                ingredients=[]
                if component.get('tipo_componente')=='PRODUCTO':
                    ingredients=[component]
                elif component.get('id_subproducto'):
                    sub=subs.get(component['id_subproducto'])
                    if (not sub or not sub.get('activo',True) or float(sub.get('rendimiento') or 0)<=0
                            or sub.get('unidad')!=component.get('unidad') or not sub.get('ingredientes')):
                        issue=issue or 'Intermedio sin rendimiento o ingredientes válidos'
                    else:
                        ingredients=sub['ingredientes']
                else:
                    issue=issue or 'Componente sin identificar'
                for ingredient in ingredients:
                    pid=ingredient.get('id_producto')
                    if pid:
                        dependencies.add(pid)
                    if (not pid or not ingredient.get('activo',True) or float(ingredient.get('cantidad') or 0)<=0
                            or pid not in products or ingredient.get('unidad')!=products[pid].get('unidad')):
                        issue=issue or 'Revisar cantidades y unidades de la receta'
        used.update(dependencies)
        states=[ingredient_state(pid) for pid in sorted(dependencies)]
        negative=next((products[pid] for pid in sorted(dependencies) if ingredient_state(pid)=='Revisar stock negativo'),None)
        if negative:
            issue='Revisar stock negativo'+('; '+issue if issue else '')
            row['insumo_limitante']=negative['nombre']
        issue=issue or next((s for s in states if s not in ('Estimada','Provisional')),None)
        if dependencies and not issue:
            limiting=min((products[pid] for pid in dependencies),key=lambda r:r['cobertura_dias'])
            row.update(cobertura_dias=limiting['cobertura_dias'],insumo_limitante=limiting['nombre'])
        elif dependencies:
            # A known risk can be shown without claiming the complete product's
            # duration when another required ingredient is unknown.
            risks=[products[pid] for pid in dependencies if ingredient_state(pid)=='Estimada']
            if risks and not row['insumo_limitante']: row['insumo_limitante']=min(risks,key=lambda r:r['cobertura_dias'])['nombre']
        row['estado_cobertura']=issue or ('Provisional' if 'Provisional' in states else 'Estimada')
        row['ids_insumos']=sorted(dependencies)
        articles.append(row)
    articles.sort(key=lambda r:(-float(r.get('cantidad') or 0),r.get('nombre','')))
    ingredients=[]
    for pid in sorted(used):
        row=dict(products.get(pid,{'id_producto':pid,'nombre':'Insumo sin datos'}))
        row['estado_cobertura']=ingredient_state(pid)
        if row['estado_cobertura'] not in ('Estimada','Provisional'): row['cobertura_dias']=None
        if not requested_period and not coverage_complete and row['estado_cobertura']!='Provisional': row['consumo_diario']=None
        ingredients.append(row)
    ingredients.sort(key=lambda r:(r.get('cobertura_dias') is None,r.get('cobertura_dias') or 0,r.get('nombre','')))
    return {'articulos':articles,'insumos':ingredients,'periodos':periods,'fechas_sin_registro':historical.get('fechas_sin_registro',[]) if requested_period else weekly.get('metadata',{}).get('fechas_sin_registro',[]),
            'nota':('Promedio diario: ventas registradas divididas entre los d\u00edas calendario del per\u00edodo solicitado. '
                    'Duraci\u00f3n: stock actual dividido entre el consumo diario de ese mismo per\u00edodo; '
                    'cada insumo suma el consumo de todos los productos que lo utilizan. '
                    'C\u00e1lculos con los registros disponibles; no incluyen movimientos a\u00fan no registrados. No es caducidad.')}



def report(local,start,end):
    from . import demand, weekly
    from .operativo import filas,serial
    from app.modules.recetas.repository import listar_recetas_detalladas
    from app.modules.produccion.repository import listar_subproductos_detallados
    today=datetime.now(timezone(timedelta(hours=-5))).date()
    # Use complete historical days; historical totals retain the chosen window.
    anchor=min(end+timedelta(days=1),today)
    historical=demand.report(local,start,end)
    # Verify the selected window, not only the latest twenty days. A closed
    # zero-sales day is observed; an absent day remains unknown.
    coverage=filas("""WITH receipts AS (
        SELECT (creado_en AT TIME ZONE 'America/Lima')::date fecha,count(*) cobros,
          count(*) FILTER (WHERE EXISTS (SELECT 1 FROM movimiento_inventario m
            WHERE m.id_movimiento_inventario=c.id_movimiento AND m.id_local=c.id_local)) vinculados
        FROM salon_cobro c WHERE id_local=:local
          AND (creado_en AT TIME ZONE 'America/Lima')::date BETWEEN :desde AND :hasta GROUP BY 1
        ), closures AS (SELECT fecha FROM inventario_jornada WHERE id_local=:local
          AND cerrado_en IS NOT NULL AND fecha BETWEEN :desde AND :hasta)
        SELECT coalesce(r.fecha,j.fecha) fecha FROM receipts r FULL JOIN closures j USING(fecha)
        WHERE (coalesce(r.cobros,0)>0 OR j.fecha IS NOT NULL)
          AND coalesce(r.cobros,0)=coalesce(r.vinculados,0)""",{'local':local,'desde':start,'hasta':end})
    observed={r['fecha'].isoformat() if hasattr(r['fecha'],'isoformat') else str(r['fecha']) for r in coverage}
    historical['fechas_sin_registro']=[(start+timedelta(days=i)).isoformat()
        for i in range((end-start).days+1) if (start+timedelta(days=i)).isoformat() not in observed]
    weeks=weekly.report(local,today=anchor)
    known=filas('''SELECT id_producto FROM inventario_saldo_inicial WHERE id_local=:local
                  UNION SELECT id_producto FROM inventario_evento WHERE id_local=:local''',{'local':local})
    outlook=calculate(historical,weeks,listar_recetas_detalladas(),listar_subproductos_detallados(),
                      {r['id_producto'] for r in known},start)
    store=filas('SELECT nombre FROM local WHERE id_local=:local',{'local':local})
    return serial({**historical,'id_local':local,'local':store[0]['nombre'] if store else None,'analisis_productos':outlook})

import unittest
from unittest.mock import patch
from datetime import date

from app.multiagente.agents.orchestrator import purchase_review
from app.multiagente.agents.eventos.period import resolve
from app.multiagente.api import purchases
from app.multiagente.agents.demanda import summary
from app.modules.inventarios.weekly import calculate
from app.multiagente.agents.compras import agent as purchase_agent
from datetime import timedelta


class WeeklyIntegrationTests(unittest.TestCase):
    def test_unknown_days_do_not_produce_false_percentage_declines(self):
        today=date(2026,11,15)
        coverage=[dict(fecha=today-timedelta(days=i),cobros=1,cobros_con_inventario=1) for i in range(7,15)]
        items=[dict(fecha=today-timedelta(days=7),id_presentacion=1,nombre='A',cantidad=1),
               dict(fecha=today-timedelta(days=8),id_presentacion=1,nombre='A',cantidad=100)]
        row=calculate(today,items,[],[],coverage)['articulos'][0]
        self.assertIsNone(row['variacion_porcentaje'])
        self.assertEqual(row['estado_ultimos7'],'INSUFICIENTE')
    def test_correction_of_weekly_order_never_checks_monthly_base(self):
        plan={'horizonte':'semanal','recurso':'ordenes_compra'}
        with patch.object(purchase_agent.tools,'authorize'),patch('app.multiagente.api.configuration.authorize'), \
             patch.object(purchase_agent.tools,'native',return_value={'productos':[{'id_producto':1}]}) as native, \
             patch.object(purchases,'prepare',return_value=plan):
            result=purchase_agent.run({},'Prepara el pedido con 20% de incremento sobre el consumo.',horizonte='semanal')
        self.assertEqual(result['plan'],plan)
        self.assertIn('horizonte=semanal',native.call_args.args[0])

    def test_sales_only_preserves_weekly_comparisons_and_all_articles(self):
        text='### Artículos con mayor salida\n12 productos\n### Comparación entre semanas completas\nValores\n### Insumos con menor cobertura estimada\nStock'
        result={'respuesta':text,'consultas':[{'recurso':'demanda_rotacion','registros':[{'stock_actual':3}],
                'contexto':{'horizonte':'semanal','articulos':[{'nombre':str(i)} for i in range(12)],'plan_semanal':{'productos':[1]}}}]}
        stripped=purchase_review.sales_only(result)
        self.assertIn('Comparación entre semanas completas',stripped['respuesta'])
        self.assertNotIn('Stock',stripped['respuesta'])
        self.assertEqual(len(stripped['consultas'][0]['contexto']['articulos']),12)
        self.assertNotIn('plan_semanal',stripped['consultas'][0]['contexto'])

    def test_closed_inventory_day_with_no_sales_is_observed_zero(self):
        today=date(2026,11,15)
        days=[dict(fecha=today-timedelta(days=i),cobros=0,cobros_con_inventario=0,jornada_cerrada=True) for i in range(1,29)]
        result=calculate(today,[],[],[dict(id_producto=1,nombre='Limón',stock_actual=2,presentacion=1)],days)
        self.assertTrue(result['metadata']['historial_completo'])
        self.assertEqual(result['productos'][0]['consumo_proyectado'],0)
        self.assertEqual(result['reposicion'],[])
    def test_weekly_summary_keeps_more_than_five_rows_and_uses_native_comparison(self):
        articles=[dict(nombre=f'Bebida {i}',cantidad=12,cantidad_anterior=8,variacion_porcentaje=50,
                       semanas=[dict(cantidad=8,estado_historial='COMPLETO')]) for i in range(12)]
        report={'articulos':articles,'productos':[],'reposicion':[],
                'periodos':{'ultimos7':{'desde':'2026-11-08','hasta':'2026-11-14'},
                            'semanas_completas':[{'desde':'2026-11-02','hasta':'2026-11-08'}]}}
        with patch('app.multiagente.api.configuration.authorize'),patch('app.multiagente.api.tools.authorize'), \
             patch('app.multiagente.api.tools.native',return_value=report) as native:
            result=summary.analyze({}, {'semanal':True})
        native.assert_called_once_with('/inventario-operativo/plan-semanal')
        self.assertIn('| Bebida 11 | 12 | 8 | 50 |',result['respuesta'])
        self.assertEqual(result['consultas'][0]['contexto']['horizonte'],'semanal')

    def test_weekly_replenishment_uses_same_report_without_monthly_fallback(self):
        weekly={'periodos':{'proyeccion':{'desde':'2026-11-15','hasta':'2026-11-21'}},
                'reposicion':[dict(id_producto=1,nombre='Limón',unidad='KGM',stock_actual=1,cantidad_sugerida=4)]}
        demand={'consultas':[{'contexto':{'plan_semanal':weekly},'registros':[]}]}
        with patch.object(purchase_review,'base',side_effect=AssertionError('monthly read')):
            lines,query=purchase_review.replenishment({},demand)
        self.assertIn('2026-11-22',' '.join(lines))
        self.assertEqual(query['registros'][0]['cantidad_sugerida'],4)

    def test_weekday_with_explicit_day_uses_the_day_not_today(self):
        self.assertEqual(resolve('hasta el domingo 22', date(2026,11,15)),
                         ('2026-11-15','2026-11-22'))
        with self.assertRaises(ValueError):
            resolve('hasta el lunes 22', date(2026,11,15))

    def test_stock_report_returns_all_alerts_and_available_items(self):
        rows=[dict(id_producto=i,nombre=f'Producto {i:02}',unidad='C62',stock_actual=i,
                   stock_minimo=3,estado_stock='STOCK_BAJO' if i<=3 else 'DISPONIBLE') for i in range(1,13)]
        with patch.object(purchase_review.configuration,'authorize'),patch.object(purchase_review.tools,'authorize'), \
             patch.object(purchase_review.tools,'native',return_value={'productos':rows}):
            result=purchase_review.stock_report({})
        self.assertEqual(result['total'],12)
        self.assertEqual(len(result['registros']),12)
        self.assertIn('Producto 12',result['respuesta'])
        self.assertIn('en el mínimo',result['respuesta'])

    def test_weekly_draft_uses_native_weekly_endpoint(self):
        row=dict(id_producto=1,nombre='Limón',unidad='KGM',presentacion=1,cantidad_sugerida=4)
        with patch('app.multiagente.api.tools.authorize'), \
             patch('app.multiagente.api.tools.native',return_value={'productos':[row]}) as native:
            plan=purchases.prepare({},'crear',None,{'porcentaje_general':10,'adicionales':[], 'horizonte':'semanal'})
        self.assertIn('horizonte=semanal',native.call_args.args[0])
        self.assertEqual(plan['datos']['detalles'][0]['cantidad_solicitada'],4)
        self.assertEqual(plan['horizonte'],'semanal')


if __name__=='__main__':unittest.main()

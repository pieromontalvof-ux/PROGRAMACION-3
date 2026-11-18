import unittest
from datetime import date,datetime,timezone
from unittest.mock import patch
import test_purchase_review as fixtures
from app.multiagente.agents.orchestrator import purchase_flow as flow


class ConfirmPurchaseHorizonTests(unittest.TestCase):
    setUp=fixtures.PurchaseReviewTests.setUp
    review=fixtures.PurchaseReviewTests.review

    def test_next_delivery_requires_date_before_any_search_or_calculation(self):
        instruction=fixtures.REQUEST.replace('de los próximos siete días','hasta la próxima entrega')
        result,search,demand,native=self.review(instruction=instruction)
        search.assert_not_called();demand.assert_not_called();native.assert_not_called()
        self.assertIn('¿Hasta qué fecha necesitas que alcance este pedido?',result['respuesta'])
        self.assertNotIn('dias_abastecimiento',flow.load(result['flujo_compra']))

    def test_ten_days_resumes_task_and_propagates_horizon(self):
        request=fixtures.REQUEST.replace('de los próximos siete días','hasta la próxima entrega')
        first,_,_,_=self.review(instruction=request)
        with patch.object(flow,'datetime') as clock:
            clock.now.return_value=datetime(2026,11,16,12,tzinfo=timezone.utc)
            result,search,demand,native=self.review(instruction='para 10 días',token=first['flujo_compra'])
        state=flow.load(result['flujo_compra'])
        self.assertEqual(state['dias_abastecimiento'],10)
        self.assertEqual(state['periodo_eventos'],['2026-11-16','2026-11-26'])
        self.assertIn('2026-11-26',search.call_args.args[1])
        self.assertEqual(demand.call_args.kwargs['filters']['dias_abastecimiento'],10)
        self.assertIn('dias=10',native.call_args.args[0])
        with patch.object(flow.purchase_agent,'run',return_value={'respuesta':'Propuesta','consultas':[],'plan':None}) as purchase, patch.object(flow,'datetime') as clock:
            clock.now.return_value=datetime(2026,11,16,12,tzinfo=timezone.utc)
            flow.handle({},'10%',token=result['flujo_compra'])
        self.assertEqual(purchase.call_args.kwargs['dias_abastecimiento'],10)

    def test_date_confirmation_without_events_still_precedes_replenishment(self):
        instruction='Quiero preparar el pedido. Sin analisis de eventos; analiza ventas y stock.'
        result,search,demand,native=self.review(instruction=instruction)
        search.assert_not_called();demand.assert_not_called();native.assert_not_called()
        self.assertIsNone(result['plan'])

    def test_initial_explicit_duration_does_not_get_asked_again(self):
        instruction=fixtures.REQUEST.replace('de los próximos siete días','para 14 días')
        result,search,demand,native=self.review(instruction=instruction)
        self.assertEqual(search.call_count,1)
        self.assertEqual(flow.load(result['flujo_compra'])['dias_abastecimiento'],14)
        self.assertEqual(demand.call_args.kwargs['filters']['dias_abastecimiento'],14)

    def test_weekly_draft_retains_ten_day_horizon(self):
        from app.multiagente.api import purchases
        row=dict(id_producto=1,nombre='Limón',unidad='KGM',presentacion=1,cantidad_sugerida=5)
        with patch('app.multiagente.api.tools.native',return_value={'productos':[row]}) as native:
            plan=purchases.prepare({},'crear',None,{'porcentaje_general':10,'adicionales':[],
                                                  'horizonte':'semanal','dias_abastecimiento':10})
        self.assertIn('dias=10',native.call_args.args[0])
        self.assertEqual(plan['dias_abastecimiento'],10)

    def test_duration_parser_and_explicit_date_share_delivery_boundary(self):
        from app.multiagente.agents.orchestrator.purchase_horizon import resolve
        today=date(2026,11,16)
        self.assertEqual(resolve('para dos semanas',today,waiting=True),('2026-11-16','2026-11-30'))
        self.assertEqual(resolve('10 dias',today,waiting=True),('2026-11-16','2026-11-26'))
        self.assertEqual(resolve('hasta el 26 de este mismo mes',today,waiting=True),('2026-11-16','2026-11-26'))
        self.assertIsNone(resolve('10%',today,waiting=True))
        self.assertIsNone(resolve('analiza ventas de los ultimos 20 dias',today))
        self.assertIsNone(resolve('Quiero un pedido hasta la proxima entrega y analiza ventas durante 30 dias',today))
        self.assertIsNone(resolve('Quiero preparar un pedido hasta la proxima entrega, revisa el historial de esta semana',today))
        self.assertEqual(resolve('Quiero un pedido hasta el 25 de noviembre y analiza ventas durante 30 dias',today),
                         ('2026-11-16','2026-11-25'))
        self.assertEqual(resolve('Analiza ventas durante 30 dias y prepara un pedido para 10 dias',today),
                         ('2026-11-16','2026-11-26'))

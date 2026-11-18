import unittest
from datetime import date
from unittest.mock import patch
from flask import Flask
from app.multiagente.agents.orchestrator import purchase_flow as flow
from app.multiagente.api.provider import AssistantError


class GuidedPurchaseTests(unittest.TestCase):
    def setUp(self):
        self.app = Flask(__name__)
        self.app.config['SECRET_KEY'] = 'test-purchase-flow-secret'
        self.ctx = self.app.app_context()
        self.ctx.push()
        self.scope = patch.object(flow.drafts, 'scope', return_value={'usuario': 1, 'perfil': 2, 'local': 1})
        self.scope.start()
        self.auth = patch.object(flow.tools, 'authorize')
        self.auth.start()

    def tearDown(self):
        self.auth.stop()
        self.scope.stop()
        self.ctx.pop()

    def start(self):
        with patch.object(flow.event_agent, 'run', return_value={'respuesta': 'Eventos verificados', 'consultas': [], 'plan': None}) as events:
            result = flow.handle({}, 'Quiero hacer un pedido')
            events.assert_not_called()
            self.assertIn('¿Hasta qué fecha',result['respuesta'])
            result=flow.handle({},'para 7 días',token=result['flujo_compra'])
            events.assert_called_once()
        return result['flujo_compra']

    def test_start_events_then_choices_without_draft(self):
        token = self.start()
        state = flow.load(token)
        self.assertEqual(state['paso'], 'analisis')

    def test_historical_event_requires_dates_before_analysis(self):
        token = self.start()
        with patch.object(flow.demand_agent, 'run') as demand:
            result = flow.handle({}, 'Analizar evento pasado parecido', token=token)
            self.assertIn('fechas', result['respuesta'])
            demand.assert_not_called()
        with patch.object(flow.demand_agent, 'run', return_value={'respuesta': 'Ventas registradas', 'consultas': [], 'plan': None}) as demand:
            result = flow.handle({}, '2026-10-10 al 2026-10-11', token=result['flujo_compra'])
            self.assertIn('2026-10-10', demand.call_args.args[1])
            self.assertTrue(result['opciones'])

    def test_last_order_uses_real_date_and_no_web_retry(self):
        token = self.start()
        with patch.object(flow, 'last_order_date', return_value=date(2026, 10, 20)), patch.object(flow.demand_agent, 'run', return_value={'respuesta': 'Informe', 'plan': None, 'consultas': []}) as demand, patch.object(flow.event_agent, 'run') as events:
            result = flow.handle({}, 'Analizar desde la última orden enviada', token=token)
            self.assertIn('2026-10-20', demand.call_args.args[1])
            events.assert_not_called()
            self.assertIsNone(result['plan'])

    def test_continue_asks_percentage_then_prepares(self):
        token = self.start()
        result = flow.handle({}, 'Continuar con el pedido', token=token)
        self.assertIn('porcentaje', result['respuesta'])
        with patch.object(flow.purchase_agent, 'run', return_value={'respuesta': 'Propuesta', 'plan': {'recurso': 'ordenes_compra'}, 'consultas': []}) as purchase:
            result = flow.handle({}, '15', token=result['flujo_compra'])
            self.assertIn('15%', purchase.call_args.args[1])
            self.assertIsNotNone(result['plan'])

    def test_missing_history_does_not_invent_period(self):
        token = self.start()
        with patch.object(flow, 'last_order_date', return_value=None), patch.object(flow.demand_agent, 'run') as demand:
            result = flow.handle({}, 'Analizar desde la última orden enviada', token=token)
            self.assertIn('No hay', result['respuesta'])
            demand.assert_not_called()

    def test_token_cannot_cross_local_or_be_modified(self):
        token = self.start()
        with self.assertRaises(AssistantError):
            flow.load(token + 'x')
        with patch.object(flow.drafts, 'scope', return_value={'usuario': 1, 'perfil': 2, 'local': 2}), self.assertRaises(AssistantError):
            flow.load(token)

    def test_unrelated_request_is_not_intercepted_without_flow(self):
        self.assertIsNone(flow.handle({}, 'Crear producto'))

    def test_questions_during_analysis_cannot_prepare_changes(self):
        token = self.start()
        with patch.object(flow, 'run_specialist', return_value={'respuesta': 'Explicación', 'consultas': [], 'plan': None}) as specialist:
            result = flow.handle({}, '¿Cómo calculas el porcentaje?', token=token)
            self.assertEqual(specialist.call_args.kwargs['writable_resources'], ())
            self.assertIsNone(result['plan'])
            self.assertTrue(result['opciones'])

    def test_expired_flow_requires_restart(self):
        token = self.start()
        with patch('itsdangerous.timed.TimestampSigner.get_timestamp', return_value=9999999999), self.assertRaises(AssistantError):
            flow.load(token)

    def test_existing_margin_is_retained_until_continuing(self):
        token = self.start()
        result = flow.handle({}, 'Quiero 12%', token=token)
        with patch.object(flow.purchase_agent, 'run', return_value={'respuesta': 'Propuesta', 'consultas': [], 'plan': {'recurso': 'ordenes_compra'}}) as purchase:
            flow.handle({}, 'Continuar con el pedido', token=result['flujo_compra'])
            self.assertIn('12%', purchase.call_args.args[1])

    def test_invalid_or_future_dates_do_not_run_analysis(self):
        token = self.start()
        with patch.object(flow.demand_agent, 'run') as demand:
            for dates in ('2026-13-01', '2099-01-01', '2026-10-20 al 2026-10-10'):
                flow.handle({}, dates, token=token)
            demand.assert_not_called()

    def test_hypothetical_percentages_are_questions_not_margin_choices(self):
        token = self.start()
        with patch.object(flow, 'run_specialist', return_value={'respuesta': 'Es un ejemplo.', 'plan': None, 'consultas': []}) as specialist:
            result = flow.handle({}, '¿Qué pasaría con 20%?', token=token)
            specialist.assert_called_once()
            self.assertIsNone(flow.load(result['flujo_compra'])['margen'])

    def test_negated_or_multiple_percentages_are_not_silently_selected(self):
        self.assertIsNone(flow.margin('No quiero 20%, quiero 10%'))
        self.assertIsNone(flow.margin('No quiero 20%'))
        self.assertIsNone(flow.margin('20% o 30%'))

    def test_recipe_question_keeps_purchase_flow_and_recipe_choices(self):
        from test_recipe_answers import recipe
        token = self.start()
        with patch.object(flow.tools, 'records', return_value=[recipe(), recipe(2)]):
            result = flow.handle({}, 'como se prepara una hamburguesa', token=token)
        self.assertEqual(result['agente'], 'recetas')
        self.assertEqual(len(result['opciones']), 2)
        self.assertIsNone(result['plan'])
        self.assertEqual(flow.load(result['flujo_compra'])['paso'], 'analisis')

    def test_disabled_optional_events_still_offers_purchase_continuation(self):
        with patch.object(flow.event_agent, 'run', side_effect=AssistantError('Eventos deshabilitados', 403)):
            result = flow.handle({}, 'Quiero hacer un pedido para 7 días')
        self.assertIn('flujo_compra', result)
        self.assertIn('Continuar con el pedido', [option['instruccion'] for option in result['opciones']])
        self.assertIsNone(result['plan'])

import unittest
from unittest.mock import patch
from app.agents.demanda import agent as demand
from app.agents.compras import agent as purchases
from app.modules.compras.service import obtener_pedido_sugerido


class PurchaseFlowRepairTests(unittest.TestCase):
    def test_nonempty_suggestion_keeps_existing_reviewable_draft_flow(self):
        proposed = {'respuesta': 'Revisa la propuesta.', 'plan': {'recurso': 'ordenes_compra'}, 'consultas': []}
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.configuration.authorize'), patch('app.modules.asistente_ia.tools.native', return_value={'productos': [{'id_producto': 1}]}), patch.object(purchases, 'run_specialist', return_value=proposed) as model:
            result = purchases.run({}, 'Prepara el pedido con 35% de incremento sobre el consumo.', '', 'Conservar condiciones del pedido.')
        model.assert_called_once()
        self.assertIn('35%', model.call_args.args[1])
        self.assertEqual(model.call_args.args[3], 'Conservar condiciones del pedido.')
        self.assertIs(result, proposed)

    def test_events_do_not_duplicate_headers_or_imply_unconfirmed_proximity(self):
        from app.agents.eventos import agent
        report = {'estado': 'consultado', 'local': {'nombre': 'Miraflores', 'direccion': 'C. Manuel Bonilla 108'},
                  'periodo': ['2026-11-04', '2026-11-10'],
                  'informe': '## Miraflores — C. Manuel Bonilla 108\n\n**Período: 2026-11-04 al 2026-11-10**\n\n- Recital. Cercanía por confirmar.'}
        with patch('app.modules.asistente_ia.configuration.authorize'), patch('app.modules.asistente_ia.tools.authorize'), patch.object(agent, 'events', return_value=report):
            result = agent.run({}, 'eventos')
        self.assertEqual(result['respuesta'].count('C. Manuel Bonilla 108'), 1)
        self.assertEqual(result['respuesta'].count('2026-11-04 al 2026-11-10'), 1)
        self.assertIn('no se consideran eventos cercanos verificados', result['respuesta'])

    def test_guided_analysis_reads_once_without_model_pagination_loop(self):
        report = {'recurso': 'demanda_rotacion', 'total': 141, 'registros': [], 'desde': 0, 'hay_mas': True,
                  'contexto': {'desde': '2026-10-03', 'hasta': '2026-11-04', 'dias_calendario': 33,
                               'articulos': [{'nombre': 'IPA', 'cantidad': 8, 'ventas_diarias': .24}],
                               'total_articulos': 1, 'resumen': {'productos_con_consumo': 0}}}
        with patch('app.modules.asistente_ia.configuration.authorize'), patch('app.modules.asistente_ia.demand.read', return_value=report) as read, patch.object(demand, 'run_specialist') as model:
            result = demand.run({}, 'Analizar periodo', bounded=True, filters={'desde': '2026-10-03', 'hasta': '2026-11-04'})
        read.assert_called_once()
        model.assert_not_called()
        self.assertIn('2026-10-03', result['respuesta'])
        self.assertIn('IPA', result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_empty_suggestion_distinguishes_missing_consumption_from_sufficient_stock(self):
        with patch('app.modules.compras.service.listar_productos_para_compra', return_value=[{'consumo_total': 0}]):
            result, status = obtener_pedido_sugerido('20')
        self.assertEqual(status, 200)
        self.assertEqual(result['diagnostico']['motivo'], 'sin_consumo')
        self.assertEqual(result['porcentaje_incremento'], 20)

    def test_empty_guided_order_explains_source_and_keeps_chosen_percentage_without_model(self):
        reply = {'productos': [], 'diagnostico': {'motivo': 'sin_consumo', 'mensaje': 'No hay consumo registrado en los últimos 30 días.'}}
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.configuration.authorize'), patch('app.modules.asistente_ia.tools.native', return_value=reply), patch.object(purchases, 'run_specialist') as model:
            result = purchases.run({}, 'Prepara el pedido con 20% de incremento sobre el consumo.')
        model.assert_not_called()
        self.assertIn('30 días', result['respuesta'])
        self.assertIn('20%', result['respuesta'])
        self.assertIsNone(result['plan'])

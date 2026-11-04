import json
import unittest
from unittest.mock import patch

from app.agents.orchestrator.router import route, run
from app.modules.asistente_ia.provider import AssistantError


class OperationAgentTests(unittest.TestCase):
    def test_independent_routes(self):
        for text, expected in (
            ('quiero hacer un pedido', 'compras'),
            ('eventos cerca de Barranco', 'eventos'),
            ('reintentar eventos', 'eventos'),
            ('consultar stock', 'inventario'),
            ('recibir el pedido del proveedor', 'recepcion'),
            ('recepciones pendientes', 'recepcion'),
            ('historial de recepciones', 'recepcion'),
            ('pedido de mesa', 'salon'),
            ('hacer un pedido sin consultar eventos', 'compras'),
            ('quiero un pedido, no quiero consultar eventos', 'compras'),
            ('prepara una compra con 20% por los eventos', 'compras'),
            ('busca eventos para mi pedido', 'eventos'),
        ):
            with self.subTest(text=text):
                self.assertEqual(route(text), expected)

    def test_purchase_never_calls_event_search(self):
        from app.agents.compras.agent import run as purchase
        with patch('app.modules.asistente_ia.tools.authorize'), \
             patch('app.agents.eventos.agent.events') as search, \
             patch('app.agents.compras.agent.run_specialist', return_value={
                 'respuesta': 'Base', 'plan': None, 'consultas': []}):
            purchase({}, 'quiero hacer un pedido')
        search.assert_not_called()

    def test_event_report_has_no_second_model_call_or_write(self):
        from app.agents.eventos.agent import run as event_run
        with patch('app.modules.asistente_ia.tools.authorize'), \
             patch('app.agents.eventos.agent.events', return_value={
                 'estado': 'consultado', 'informe': 'Evento con fuente', 'fuentes': []}), \
             patch('app.modules.asistente_ia.provider.respond') as model:
            result = event_run({}, 'eventos cerca')
        model.assert_not_called()
        self.assertIsNone(result['plan'])
        self.assertIn('Evento con fuente', result['respuesta'])

    def test_followup_keeps_reception_context(self):
        with patch('app.agents.recepcion.agent.run', return_value={
                'respuesta': 'Detalle', 'plan': None, 'consultas': []}) as specialist:
            result = run({}, 'faltaron dos cajas', context='consultar recepciones pendientes')
        specialist.assert_called_once()
        self.assertEqual(result['agente'], 'recepcion')

    def test_shortage_followup_keeps_reception_but_explicit_stock_switches(self):
        with patch('app.agents.recepcion.agent.run', return_value={
                'respuesta': 'Detalle', 'plan': None, 'consultas': []}) as specialist:
            result = run({}, 'hay un faltante de dos cajas', context='recepciones pendientes')
        specialist.assert_called_once()
        self.assertEqual(result['agente'], 'recepcion')
        self.assertEqual(route('consultar stock', 'recepciones pendientes'), 'inventario')

    def test_events_without_permission_never_search(self):
        from app.agents.eventos.agent import run as event_run
        with patch('app.agents.eventos.agent.events') as search, self.assertRaises(AssistantError):
            event_run({'menu': []}, 'eventos cercanos')
        search.assert_not_called()

    def test_declining_events_does_not_restore_previous_search(self):
        with patch('app.agents.eventos.agent.events') as search:
            result = run({}, 'no consultar eventos', context='eventos cercanos')
        search.assert_not_called()
        self.assertIsNone(result['plan'])

    def test_reception_exposes_only_its_own_write_capability(self):
        from app import create_app
        from app.agents.recepcion.agent import run as reception_run
        output = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Consulta lista.'}]}]
        with create_app().test_request_context(), \
             patch('app.modules.asistente_ia.provider.respond', return_value=output) as model:
            reception_run({'menu': [{'id_opcion_menu': 24, 'permisos': {
                'consultar': True, 'crear': True}}]}, 'recibir productos')
        definitions = {tool['name']: tool for tool in model.call_args.args[1]}
        self.assertEqual(definitions['preparar_cambio']['parameters']['properties']['recurso']['enum'],
                         ['recepciones'])
        self.assertEqual(definitions['consultar']['parameters']['properties']['recurso']['enum'],
                         ['recepciones'])

    def test_reception_query_only_profile_has_no_write_tool(self):
        from app import create_app
        from app.agents.recepcion.agent import run as reception_run
        output = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Consulta lista.'}]}]
        with create_app().test_request_context(), \
             patch('app.modules.asistente_ia.provider.respond', return_value=output) as model:
            reception_run({'menu': [{'id_opcion_menu': 24, 'permisos': {
                'consultar': True}}]}, 'recepciones pendientes')
        self.assertNotIn('preparar_cambio', [tool['name'] for tool in model.call_args.args[1]])


class ReceptionProposalTests(unittest.TestCase):
    def rows(self):
        return [{'id_orden_compra': 7, 'codigo_orden': 'OC-7', 'id_proveedor': 2,
                 'proveedor': 'Proveedor', 'productos': [
                     {'id_producto': 3, 'nombre': 'Producto', 'unidad': 'UND',
                      'cantidad_solicitada': 10, 'cantidad_recibida': 2,
                      'cantidad_pendiente': 8}]}]

    def prepare(self, quantity=5, product=3, **extra):
        from app.modules.asistente_ia import receptions
        changes = {'id_orden_compra': 7, 'id_proveedor': 2,
                   'numero_factura': 'F001-1', 'fecha_recepcion': '2026-10-21',
                   'detalles': [{'id_producto': product, 'cantidad_recibida': quantity}], **extra}
        with patch('app.modules.asistente_ia.tools.authorize'), \
             patch('app.modules.asistente_ia.tools.records', return_value=self.rows()):
            return receptions.prepare({}, 'crear', None, changes)

    def test_partial_receipt_is_reviewable_without_writes(self):
        with patch('app.modules.asistente_ia.tools.native') as native:
            plan = self.prepare()
        native.assert_not_called()
        self.assertEqual(plan['recurso'], 'recepciones')
        self.assertEqual(plan['datos']['detalles'][0]['cantidad_recibida'], 5)
        self.assertEqual(plan['revision_recepcion'][0]['pendiente_despues'], 3)

    def test_rejects_foreign_product_excess_nonfinite_and_hidden_scope(self):
        for arguments in ({'quantity': 9}, {'quantity': 'NaN'}, {'quantity': -1},
                          {'quantity': True}, {'product': 88}, {'id_local': 99}):
            with self.subTest(arguments=arguments), self.assertRaises(AssistantError):
                self.prepare(**arguments)

    def test_permissions_come_from_reception_menu(self):
        from app.modules.asistente_ia import tools
        session = {'menu': [{'id_opcion_menu': 24, 'permisos': {'consultar': True}}]}
        self.assertTrue(tools.allowed(session, 'recepciones'))
        self.assertFalse(tools.allowed(session, 'recepciones', 'crear'))

    def test_execute_reuses_native_route_and_rechecks_pending(self):
        from app.modules.asistente_ia import tools
        plan = self.prepare()
        with patch.object(tools, 'authorize'), \
             patch.object(tools, 'records', return_value=self.rows()), \
             patch.object(tools, 'native', return_value={'mensaje': 'Registrada'}) as native:
            tools.execute({}, plan)
        self.assertEqual(native.call_args.args[:2],
                         ('/recepciones/ordenes/7/recepciones', 'POST'))

    def test_stale_or_foreign_order_is_rejected_before_write(self):
        from app.modules.asistente_ia import tools
        plan = self.prepare()
        with patch.object(tools, 'authorize'), patch.object(tools, 'records', return_value=[]), \
             patch.object(tools, 'native') as native, self.assertRaises(AssistantError):
            tools.execute({}, plan)
        native.assert_not_called()

    def test_duplicate_products_and_missing_invoice_are_rejected(self):
        for extra in ({'numero_factura': ''}, {'fecha_recepcion': 'ayer'},
                      {'detalles': [{'id_producto': 3, 'cantidad_recibida': 1}] * 2},
                      {'id_proveedor': 99}, {'id_orden_compra': True}):
            with self.subTest(extra=extra), self.assertRaises(AssistantError):
                self.prepare(**extra)

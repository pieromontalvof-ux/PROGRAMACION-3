import unittest
from unittest.mock import patch
from flask import Flask


PRODUCTS = [
    {'id_producto': 27, 'nombre': 'Maracuya', 'unidad': 'LTR', 'activo': True, 'id_proveedor': 2},
    {'id_producto': 121, 'nombre': 'Camu Camu Maracuyá', 'unidad': 'LTR', 'activo': True, 'id_proveedor': 9},
]
PROVIDERS = [{'id_proveedor': 2, 'nombre': 'Distribuidora Central', 'activo': True}]


class SupplyReviewTests(unittest.TestCase):
    def setUp(self):
        self.ctx = Flask(__name__).test_request_context()
        self.ctx.push()
        self.addCleanup(self.ctx.pop)
        for target, kwargs in (
            ('app.modules.asistente_ia.tools.allowed', {'return_value': True}),
            ('app.modules.asistente_ia.tools.authorize', {}),
            ('app.modules.asistente_ia.configuration.authorize', {}),
            ('app.modules.asistente_ia.configuration.authorize_owner', {}),
        ):
            p = patch(target, **kwargs)
            p.start()
            self.addCleanup(p.stop)
        self.session = {'local_activo': {'id_local': 4, 'nombre': 'Sheraton'}}

    def inspect(self, stock, products=None, providers=None):
        from app.agents import supply
        sources = {'productos': PRODUCTS if products is None else products,
                   'proveedores': PROVIDERS if providers is None else providers}
        with patch('app.modules.asistente_ia.tools.records', side_effect=lambda s, r: sources[r]), \
             patch('app.modules.asistente_ia.inventory.read', return_value={
                 'registros': stock, 'hay_mas': False}), \
             patch('app.modules.asistente_ia.tools.execute', side_effect=AssertionError('No writes')):
            return supply.review(self.session, 'Maracuyá', 'presentaciones')

    def test_exact_product_wins_over_a_different_drink_with_the_same_word(self):
        report = self.inspect([{'id_producto': 27, 'stock_actual': 0, 'unidad': 'LTR'}])
        self.assertEqual(report['registros'][0]['id_producto'], 27)
        self.assertEqual(report['registros'][0]['estado_stock'], 'SIN_STOCK')
        self.assertEqual(report['registros'][0]['proveedor'], 'Distribuidora Central')
        self.assertIn('Sheraton', report['resumen'])
        self.assertTrue(report['requiere_decision'])

    def test_admin_recipe_review_only_checks_registration_not_stock_or_supply(self):
        from app.agents import supply
        session = {**self.session, 'perfil_activo': {'id_perfil': 1}}
        with patch('app.modules.asistente_ia.tools.records', side_effect=lambda s, r: PRODUCTS if r == 'productos' else self.fail('No supplier query for recipe creation')), \
             patch('app.modules.asistente_ia.inventory.read') as stock:
            report = supply.review(session, 'Maracuyá', 'recetas')
        self.assertEqual(report['alcance'], 'CATALOGO')
        self.assertEqual(report['estado_catalogo'], 'ACTIVO')
        self.assertNotIn('stock', report['resumen'].lower())
        self.assertNotIn('proveedor', report['resumen'].lower())
        self.assertNotIn('estado_stock', report['registros'][0])
        self.assertFalse(report['requiere_decision'])
        stock.assert_not_called()

    def test_missing_admin_ingredient_requires_registration_not_purchasing(self):
        from app.agents import supply
        session = {**self.session, 'perfil_activo': {'id_perfil': 1}}
        with patch('app.modules.asistente_ia.tools.records', return_value=[]):
            report = supply.review(session, 'Nuevo insumo', 'recetas')
        self.assertEqual(report['estado_catalogo'], 'NO_REGISTRADO')
        self.assertEqual(report['alcance'], 'CATALOGO')
        self.assertNotIn('proveedor', report['resumen'].lower())
        self.assertTrue(report['requiere_decision'])

    def test_supply_review_also_works_when_agent_activity_is_recording(self):
        from app.agents import activity
        token = activity.begin('Revisar maracuyá', {'usuario': 1, 'perfil': 1, 'local': 4})
        try:
            report = self.inspect([{'id_producto': 27, 'stock_actual': 0}])
            self.assertEqual(report['registros'][0]['estado_stock'], 'SIN_STOCK')
            self.assertEqual(report['registros'][0]['proveedor'], 'Distribuidora Central')
        finally:
            activity.reset(token)

    def test_positive_stock_is_not_a_promise_that_it_covers_an_unknown_recipe(self):
        report = self.inspect([{'id_producto': 27, 'stock_actual': 2.5, 'unidad': 'LTR'}])
        self.assertEqual(report['registros'][0]['estado_stock'], 'CON_STOCK')
        self.assertEqual(report['registros'][0]['stock_actual'], 2.5)
        self.assertIn('cantidad', report['resumen'].lower())
        self.assertFalse(report['requiere_decision'])

    def test_null_or_missing_stock_is_not_reported_as_zero(self):
        for stock in ([], [{'id_producto': 27, 'stock_actual': None, 'unidad': 'LTR'}]):
            with self.subTest(stock=stock):
                report = self.inspect(stock)
                self.assertEqual(report['registros'][0]['estado_stock'], 'NO_VERIFICADO')
                self.assertIsNone(report['registros'][0]['stock_actual'])

    def test_unregistered_and_inactive_products_have_distinct_states(self):
        for products, expected in (([], 'NO_REGISTRADO'), ([{**PRODUCTS[0], 'activo': False}], 'INACTIVO')):
            with self.subTest(expected=expected):
                report = self.inspect([], products=products)
                self.assertEqual(report['estado_catalogo'], expected)
                self.assertTrue(report['requiere_decision'])

    def test_partial_match_is_offered_for_selection_not_substituted(self):
        from app.agents import supply
        with patch('app.modules.asistente_ia.tools.records', return_value=[PRODUCTS[1]]), \
             patch('app.modules.asistente_ia.inventory.read') as stock:
            report = supply.review(self.session, 'Maracuya', 'recetas')
        self.assertEqual(report['estado_catalogo'], 'ELEGIR_PRODUCTO')
        stock.assert_not_called()

    def test_commercial_drink_name_does_not_hide_a_registered_possible_ingredient(self):
        from app.agents import supply
        with patch('app.modules.asistente_ia.tools.records', return_value=PRODUCTS), \
             patch('app.modules.asistente_ia.inventory.read') as stock:
            report = supply.review(self.session, 'Maracuyá especial', 'recetas')
        self.assertEqual(report['estado_catalogo'], 'ELEGIR_PRODUCTO')
        self.assertEqual(report['registros'][0]['id_producto'], 27)
        stock.assert_not_called()

    def test_stock_profile_permission_is_checked_before_querying(self):
        with patch('app.modules.asistente_ia.tools.allowed', side_effect=lambda s, r, *a: r != 'stock'):
            report = self.inspect([{'id_producto': 27, 'stock_actual': 0}])
        self.assertEqual(report['registros'][0]['estado_stock'], 'SIN_ACCESO')
        self.assertIsNone(report['registros'][0]['stock_actual'])
        self.assertNotIn('sin stock', report['resumen'].lower())

    def test_disabled_agent_catalog_access_does_not_claim_product_is_absent(self):
        from app.agents import supply
        from app.modules.asistente_ia.provider import AssistantError
        with patch('app.modules.asistente_ia.configuration.authorize', side_effect=AssistantError('Deshabilitado', 403)), \
             patch('app.modules.asistente_ia.tools.records') as records:
            report = supply.review(self.session, 'Maracuyá', 'recetas')
        self.assertEqual(report['estado_catalogo'], 'SIN_ACCESO')
        records.assert_not_called()

    def test_disabled_stock_owner_access_does_not_leak_stock(self):
        from app.modules.asistente_ia.provider import AssistantError
        def authorize(resource, *args):
            if resource == 'stock':
                raise AssistantError('Deshabilitado', 403)
        with patch('app.modules.asistente_ia.configuration.authorize_owner', side_effect=authorize):
            report = self.inspect([{'id_producto': 27, 'stock_actual': 10}])
        self.assertEqual(report['registros'][0]['estado_stock'], 'SIN_ACCESO')
        self.assertIsNone(report['registros'][0]['stock_actual'])

    def test_unavailable_stock_service_is_not_reported_as_a_shortage(self):
        from app.agents import supply
        from app.modules.asistente_ia.provider import AssistantError
        with patch('app.modules.asistente_ia.tools.records', side_effect=lambda s, r: PRODUCTS if r == 'productos' else PROVIDERS), \
             patch('app.modules.asistente_ia.inventory.read', side_effect=AssistantError('No disponible', 502)):
            report = supply.review(self.session, 'Maracuya', 'presentaciones')
        self.assertEqual(report['registros'][0]['estado_stock'], 'NO_VERIFICADO')
        self.assertNotIn('sin stock', report['resumen'].lower())

    def test_inactive_provider_is_not_recommended_as_available(self):
        report = self.inspect([{'id_producto': 27, 'stock_actual': 0}],
                              providers=[{**PROVIDERS[0], 'activo': False}])
        self.assertEqual(report['registros'][0]['estado_proveedor'], 'INACTIVO')
        self.assertNotIn('proveedor disponible', report['resumen'].lower())

    def test_stock_is_matched_by_product_id_not_by_first_search_result(self):
        report = self.inspect([{'id_producto': 121, 'stock_actual': 50},
                               {'id_producto': 27, 'stock_actual': 0}])
        self.assertEqual(report['registros'][0]['stock_actual'], 0)

    def test_supplier_permission_does_not_leak_its_name_from_the_product(self):
        with patch('app.modules.asistente_ia.tools.allowed', side_effect=lambda s, r, *a: r != 'proveedores'):
            report = self.inspect([{'id_producto': 27, 'stock_actual': 0}])
        self.assertEqual(report['registros'][0]['estado_proveedor'], 'SIN_ACCESO')
        self.assertIsNone(report['registros'][0]['proveedor'])

    def test_recipe_supply_connections_remain_read_only_in_manifest(self):
        from app.agents.manifest import catalog
        recipe = next(a for a in catalog()['agentes'] if a['id'] == 'recetas')
        self.assertIn('stock', recipe['recursos_solo_consulta'])
        self.assertIn('proveedores', recipe['recursos_solo_consulta'])
        self.assertEqual(recipe['recursos_modificables'], ['recetas'])

    def test_matching_a_title_is_only_a_possible_ingredient_not_a_recipe(self):
        from app.agents import supply
        with patch('app.modules.asistente_ia.tools.records', side_effect=lambda s, r: PRODUCTS if r == 'productos' else PROVIDERS), \
             patch('app.modules.asistente_ia.inventory.read', return_value={'registros': []}):
            report = supply.for_title(self.session, 'Maracuyá especial', 'presentaciones')
        self.assertEqual(report['referencia'], 'POSIBLE_INSUMO')
        self.assertEqual(report['registros'][0]['id_producto'], 27)
        self.assertIn('confirmar', report['resumen'].lower())

    def test_recipe_request_keeps_its_agent_when_it_also_mentions_stock_and_purchase(self):
        from app.agents.orchestrator.router import route
        self.assertEqual(route('Quiero registrar una receta de maracuyá; revisa el stock y si falta vemos la compra.'), 'recetas')

    def test_runtime_reads_supply_with_no_write_tools_for_suppliers_or_stock(self):
        import json
        from app.agents.catalog_specialists import SPECIALISTS
        tool_call = [{'type': 'function_call', 'call_id': 'supply', 'name': 'revisar_insumo',
                      'arguments': json.dumps({'nombre': 'Maracuyá'})}]
        answer = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Sin existencias. Revisemos el proveedor.'}]}]
        with patch('app.modules.asistente_ia.configuration.saved', return_value=None), \
             patch('app.modules.asistente_ia.library.for_skills', return_value=''), \
             patch('app.agents.runtime.db.session.rollback'), \
             patch('app.modules.asistente_ia.tools.records', side_effect=lambda s, r: PRODUCTS if r == 'productos' else PROVIDERS), \
             patch('app.modules.asistente_ia.inventory.read', return_value={'registros': [{'id_producto': 27, 'stock_actual': 0}]}), \
             patch('app.modules.asistente_ia.provider.respond', side_effect=[tool_call, answer]) as model:
            result = SPECIALISTS['presentaciones'].run(self.session, 'Quiero una bebida de maracuyá')
        self.assertEqual(result['consultas'][0]['registros'][0]['estado_stock'], 'SIN_STOCK')
        definitions = {t['name']: t for t in model.call_args.args[1]}
        self.assertIn('revisar_insumo', definitions)
        self.assertEqual(definitions['preparar_cambio']['parameters']['properties']['recurso']['enum'], ['presentaciones'])
        self.assertNotIn('stock', definitions['solicitar_especialista']['parameters']['properties']['recurso']['enum'])

    def test_presentation_preflight_reports_the_registered_ingredient_and_stock(self):
        from app.agents.orchestrator.presentation_advice import run
        sources = {'productos': PRODUCTS, 'proveedores': PROVIDERS,
                   'presentaciones': [], 'menajes': [{'id_menaje': 1, 'nombre': 'Vaso', 'activo': True}],
                   'categorias_carta': [{'id_categoria_carta': 1, 'nombre': 'Sin alcohol', 'prefijo': 'SA', 'activo': True}]}
        with patch('app.modules.asistente_ia.tools.records', side_effect=lambda s, r: sources[r]), \
             patch('app.modules.asistente_ia.inventory.read', return_value={'registros': [{'id_producto': 27, 'stock_actual': 0}]}):
            result = run(self.session, 'Crear una presentación llamada «Maracuyá especial», de 400 mL, a S/ 14, en la categoría «Sin alcohol»')
        self.assertIn('Distribuidora Central', result['respuesta'])
        self.assertEqual(result['_referencias_revisadas']['decision_pendiente'], 'abastecimiento')
        self.assertEqual(result['_referencias_revisadas']['revision_insumo']['referencia'], 'POSIBLE_INSUMO')
        self.assertIsNone(result['plan'])

    def test_admin_inactive_ingredient_preflight_asks_about_catalog_not_supply(self):
        from app.agents.orchestrator.presentation_advice import run
        sources = {'productos': [{**PRODUCTS[0], 'activo': False}], 'proveedores': PROVIDERS,
                   'presentaciones': [], 'menajes': [{'id_menaje': 1, 'nombre': 'Vaso', 'activo': True}],
                   'categorias_carta': [{'id_categoria_carta': 1, 'nombre': 'Sin alcohol', 'prefijo': 'SA', 'activo': True}]}
        with patch('app.modules.asistente_ia.tools.records', side_effect=lambda s, r: sources[r]):
            result = run({**self.session, 'perfil_activo': {'id_perfil': 1}},
                         'Crear una presentación llamada «Maracuyá especial», de 400 mL, a S/ 14, en la categoría «Sin alcohol»')
        self.assertNotIn('abastecimiento', result['respuesta'].lower())
        self.assertEqual(result['_referencias_revisadas']['decision_pendiente'], 'insumo_catalogo')

    def test_supply_results_are_retained_for_the_next_conversation_turn(self):
        from app.agents.orchestrator import communication
        report = self.inspect([{'id_producto': 27, 'stock_actual': 0}])
        with self.ctx.app.test_request_context('/api/asistente-ia/preparar', json={'modo': 'conversacion'}), \
             patch.object(communication.drafts, 'scope', return_value={'usuario': 1, 'perfil': 1, 'local': 4}):
            self.ctx.app.config['SECRET_KEY'] = 'test-supply-conversation'
            for agent, task in [('presentaciones', 'Crear presentación de maracuyá'), ('recetas', 'Registrar receta de maracuyá')]:
                with self.subTest(agent=agent):
                    result = communication.coordinate(self.session,
                        {'agente': agent, 'respuesta': report['resumen'], 'consultas': [report], 'plan': None}, task)
                    state = communication.load(result['continuacion'])
                    self.assertEqual(communication.conversation(state['actual'])['revisiones_insumos'][0]['registros'][0]['estado_stock'], 'SIN_STOCK')

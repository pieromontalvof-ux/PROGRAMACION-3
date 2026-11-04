import unittest
from unittest.mock import patch
from app.agents.orchestrator.router import route, run
from app.modules.asistente_ia.provider import AssistantError


def recipe(identity=1, name='Hamburguesa Barbarian', instructions='Usar la preparación registrada.'):
    return {'id_receta': identity, 'item_carta': name, 'codigo_item': f'H-{identity}',
            'categoria_carta': 'Hamburguesas', 'contenido': 1, 'unidad_presentacion': 'C62',
            'activo': True, 'instrucciones': instructions, 'componentes': [
                {'nombre_componente': 'Pan registrado', 'cantidad': 1, 'unidad': 'C62'}], 'grupo_salsa': None}


class RecipeAnswersTests(unittest.TestCase):
    def test_minor_typoes_in_preparation_request_find_registered_recipe(self):
        for prompt in ('quiero hacer uan haburguesa', 'como se preapra una hamburgueza', 'quiero preparar una hamburgesa'):
            with self.subTest(prompt=prompt), patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=[recipe()]):
                result = run({}, prompt)
                self.assertEqual(result['agente'], 'recetas')
                self.assertIn('Usar la preparación registrada.', result['respuesta'])

    def test_close_names_are_options_not_an_automatic_recipe_selection(self):
        rows = [recipe(name='Hamburguesa Mia'), recipe(2, 'Hamburguesa Mila')]
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=rows):
            result = run({}, 'como se prepara una hamburguesa Mla')
        self.assertEqual(len(result['opciones']), 2)
        self.assertIsNone(result['plan'])

    def test_typo_handling_does_not_reinterpret_write_or_operational_requests(self):
        from app.agents.orchestrator import recipe_answers
        for prompt in ('quiero hacer un pedido', 'quiero hacer una orden de compra', 'quiero crear una hamburguesa', 'editar receta de haburguesa'):
            self.assertIsNone(recipe_answers.detect(prompt))

    def test_exact_name_has_priority_and_numeric_identifiers_are_not_approximated(self):
        from app.agents.orchestrator.recipe_answers import close_word
        self.assertFalse(close_word('250', '2500'))
        self.assertFalse(close_word('h001', 'h002'))
        rows = [recipe(name='Hamburguesa Mia'), recipe(2, 'Hamburguesa Mila')]
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=rows):
            result = run({}, 'quiero hacer una hamburguesa Mia')
        self.assertEqual(result['consultas'][0]['registros'][0]['id_receta'], 1)
        self.assertNotIn('opciones', result)

    def test_preparation_question_routes_to_recipes(self):
        for prompt in ('quiero saber como se prepara una hamburguesa',
                       'quiero saber como se prepra una hamburguesa',
                       '¿Cómo hago una hamburguesa?', 'ingredientes de la hamburguesa'):
            self.assertEqual(route(prompt), 'recetas')

    def test_answer_uses_saved_recipe_without_model_or_writes(self):
        with patch('app.modules.asistente_ia.tools.authorize'), \
             patch('app.modules.asistente_ia.tools.records', return_value=[recipe()]), \
             patch('app.modules.asistente_ia.provider.respond') as model:
            result = run({}, 'como se prepara una hamburguesa')
        self.assertEqual(result['agente'], 'recetas')
        self.assertIn('Usar la preparación registrada.', result['respuesta'])
        self.assertIn('Pan registrado', result['respuesta'])
        self.assertNotIn('sal y pimienta', result['respuesta'])
        self.assertIsNone(result['plan'])
        model.assert_not_called()

    def test_ambiguous_dishes_require_selecting_actual_recipe(self):
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=[recipe(), recipe(2, 'BBQ Burger')]):
            result = run({}, 'como se prepara una hamburguesa')
            self.assertEqual(len(result['opciones']), 2)
            self.assertNotIn('Usar la preparación registrada.', result['respuesta'])
            selected = run({}, result['opciones'][1]['instruccion'])
            self.assertIn('BBQ Burger', selected['respuesta'])

    def test_missing_instructions_are_not_completed_from_general_knowledge(self):
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=[recipe(instructions='')]):
            result = run({}, 'como se prepara una hamburguesa')
        self.assertIn('No hay instrucciones de preparación registradas', result['respuesta'])
        self.assertNotIn('plancha', result['respuesta'])

    def test_unknown_dish_does_not_get_generic_recipe(self):
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=[recipe()]):
            result = run({}, 'como se prepara un risotto')
        self.assertIn('No encontré', result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_query_does_not_bypass_recipe_permissions(self):
        with patch('app.modules.asistente_ia.tools.authorize', side_effect=AssistantError('Sin permiso', 403)), patch('app.modules.asistente_ia.tools.records') as records:
            with self.assertRaises(AssistantError):
                run({}, 'como se prepara una hamburguesa')
            records.assert_not_called()

    def test_edit_request_keeps_existing_specialist_flow(self):
        self.assertEqual(route('editar receta de hamburguesa'), 'recetas')
        from app.agents.orchestrator import recipe_answers
        self.assertIsNone(recipe_answers.detect('editar receta de hamburguesa'))

    def test_operational_preparation_is_not_a_cooking_question(self):
        from app.agents.orchestrator import recipe_answers
        for instruction in ('como preparo un pedido', 'como se hace un conteo', 'como se prepara una orden de compra'):
            self.assertIsNone(recipe_answers.detect(instruction))

    def test_inactive_recipe_is_not_presented_as_current_preparation(self):
        row = recipe()
        row['activo'] = False
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=[row]):
            result = run({}, 'Consultar preparación registrada de receta #1')
        self.assertIn('No encontré', result['respuesta'])

    def test_conversational_suffixes_do_not_hide_existing_recipes(self):
        for prompt in ('como se prepara una hamburguesa paso a paso', 'ingredientes de la hamburguesa y su preparación'):
            with self.subTest(prompt=prompt), patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=[recipe()]):
                result = run({}, prompt)
                self.assertIn('Usar la preparación registrada.', result['respuesta'])

    def test_presentation_can_be_selected_by_registered_size(self):
        small, large = recipe(), recipe(2)
        small.update(contenido=250.0, unidad_presentacion='GRM')
        large.update(contenido=500.0, unidad_presentacion='GRM')
        with patch('app.modules.asistente_ia.tools.authorize'), patch('app.modules.asistente_ia.tools.records', return_value=[small, large]):
            result = run({}, 'como se prepara una hamburguesa de 250 g')
        self.assertEqual(result['consultas'][0]['registros'][0]['id_receta'], 1)

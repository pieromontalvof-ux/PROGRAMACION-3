import json
import unittest

from app.modules.asistente_ia.provider import AssistantError


TASK = 'Quiero registrar la receta de una bebida nueva llamada «Maracuyá especial», de 400 mL, a S/ 14.'


class PreparationFlowTests(unittest.TestCase):
    def test_new_drink_recipe_requires_choosing_batch_or_glass(self):
        from app.agents import preparation
        state = preparation.resolve(TASK)
        self.assertTrue(state['requerido'])
        self.assertIsNone(state['metodo'])
        self.assertEqual(state['medida_venta'], {'cantidad': '400', 'unidad': 'MLT'})
        answer = preparation.question(state)
        self.assertIn('por lote', answer)
        self.assertIn('por cada vaso', answer)

    def test_reference_alone_does_not_copy_a_preparation_method(self):
        from app.agents import preparation
        context = json.dumps({'tarea_original': TASK, 'aclaraciones': [], 'contexto_original': ''})
        state = preparation.resolve('Cámbialo como la chicha y explícame si es intermedio o final', context)
        self.assertIsNone(state['metodo'])
        self.assertTrue(preparation.is_reference_question('Cámbialo como la chicha y explícame si es intermedio o final'))

    def test_batch_yield_does_not_replace_the_sale_measure(self):
        from app.agents import preparation
        context = json.dumps({'tarea_original': TASK, 'aclaraciones': [], 'contexto_original': ''})
        state = preparation.resolve('Por lote, quiero que rinda 12 L', context)
        self.assertEqual(state['metodo'], 'LOTE')
        self.assertEqual(state['medida_venta'], {'cantidad': '400', 'unidad': 'MLT'})

    def test_preparation_survives_a_specialist_context_and_short_reply(self):
        from app.agents import preparation
        parent = {'tarea_original': TASK, 'contexto_original': '',
                  'aclaraciones': ['La preparo por cada vaso'], 'preparacion': preparation.resolve(TASK)}
        child = {'tarea_original': 'Crear presentación Maracuyá especial de 1 porción',
                 'contexto_original': json.dumps(parent), 'aclaraciones': ['Usa Vaso']}
        state = preparation.resolve('Sí, activa', json.dumps(child))
        self.assertEqual(state['metodo'], 'POR_VASO')
        self.assertEqual(state['medida_venta'], {'cantidad': '400', 'unidad': 'MLT'})

    def test_silent_conversion_to_one_portion_is_rejected(self):
        from app.agents import preparation
        state = preparation.resolve(TASK + ' La preparo por vaso.')
        with self.assertRaises(AssistantError):
            preparation.validate(state, 'presentaciones', {'contenido': 1, 'unidad': 'PORCION'})

    def test_equivalent_liters_are_accepted(self):
        from app.agents import preparation
        state = preparation.resolve(TASK + ' La preparo por vaso.')
        preparation.validate(state, 'presentaciones', {'contenido': '0.4', 'unidad': 'LTR'})

    def test_explicit_measure_correction_is_retained(self):
        from app.agents import preparation
        state = preparation.resolve('Cambia la presentación a 1 porción',
                                    json.dumps({'tarea_original': TASK + ' Por vaso.', 'contexto_original': ''}))
        preparation.validate(state, 'presentaciones', {'contenido': 1, 'unidad': 'PORCION'})
        self.assertEqual(state['medida_venta'], {'cantidad': '1', 'unidad': 'PORCION'})

    def test_unknown_preparation_method_cannot_become_a_proposal(self):
        from app.agents import preparation
        with self.assertRaises(AssistantError):
            preparation.validate(preparation.resolve(TASK), 'presentaciones', {'contenido': '0.4', 'unidad': 'LTR'})

    def test_batch_recipe_consumes_an_intermediate_not_the_whole_batch_ingredients(self):
        from app.agents import preparation
        state = preparation.resolve(TASK + ' La preparo por lote.')
        with self.assertRaises(AssistantError):
            preparation.validate(state, 'recetas', {'componentes': [{'tipo_componente': 'PRODUCTO', 'id': 28, 'cantidad': 2}]})
        preparation.validate(state, 'recetas', {'componentes': [{'tipo_componente': 'SUBPRODUCTO', 'id': 9, 'cantidad': 0.4}]})

    def test_reading_an_existing_recipe_does_not_start_a_creation_question(self):
        from app.agents import preparation
        self.assertFalse(preparation.resolve('Cómo se prepara la chicha de 400 mL')['requerido'])

    def test_standalone_presentation_also_keeps_its_explicit_volume(self):
        from app.agents import preparation
        state = preparation.resolve('Crear una presentación de 400 mL a S/14')
        with self.assertRaises(AssistantError):
            preparation.validate(state, 'presentaciones', {'contenido': 1, 'unidad': 'PORCION'})

    def test_malformed_optional_context_does_not_replace_sale_facts(self):
        from app.agents import preparation
        context = json.dumps({'tarea_original': TASK, 'aclaraciones': None,
                              'preparacion': {'medida_venta': 'not a measure'}})
        state = preparation.resolve('Por vaso', context)
        self.assertEqual(state['medida_venta'], {'cantidad': '400', 'unidad': 'MLT'})

    def test_original_presentation_measure_does_not_overwrite_a_saved_correction(self):
        from app.agents import preparation
        context = json.dumps({'tarea_original': 'Crear una presentación de 500 mL', 'contexto_original': '',
                              'preparacion': {'requerido': False, 'metodo': None,
                                              'medida_venta': {'cantidad': '400', 'unidad': 'MLT'}}})
        self.assertEqual(preparation.resolve('Sí', context)['medida_venta'], {'cantidad': '400', 'unidad': 'MLT'})

    def test_initial_batch_volume_is_not_the_glass_measure(self):
        from app.agents import preparation
        state = preparation.resolve('Quiero registrar una receta de bebida por lote de 12 L, para vasos de 400 mL')
        self.assertEqual(state['medida_venta'], {'cantidad':'400','unidad':'MLT'})
        preparation.validate(state, 'presentaciones', {'contenido':'.4','unidad':'LTR'})

    def test_natural_measure_corrections_are_not_blocked_by_the_original_size(self):
        from app.agents import preparation
        context = json.dumps({'tarea_original':TASK.replace('400 mL','500 mL') + ' Por vaso.', 'contexto_original':''})
        for reply in ('Prefiero 400 mL y revisar el precio', 'Mejor 400 mL'):
            with self.subTest(reply=reply):
                state = preparation.resolve(reply, context)
                self.assertEqual(state['medida_venta'], {'cantidad':'400','unidad':'MLT'})
                preparation.validate(state, 'presentaciones', {'contenido':'.4','unidad':'LTR'})

    def test_recipe_information_questions_can_be_answered_while_method_is_pending(self):
        from app.agents import preparation
        self.assertTrue(preparation.is_reference_question('¿Qué ingredientes tiene la Chicha?'))

    def test_malformed_proposal_remains_a_validation_error(self):
        from app.agents import preparation
        with self.assertRaises(AssistantError):
            preparation.validate(preparation.resolve(TASK + ' Por lote.'), 'recetas', [])

    def test_a_complete_revised_request_can_explicitly_change_the_sale_measure(self):
        from app.agents import preparation
        context = json.dumps({'tarea_original':TASK.replace('400 mL','500 mL'), 'contexto_original':''})
        self.assertEqual(preparation.resolve(TASK, context)['medida_venta'], {'cantidad':'400','unidad':'MLT'})

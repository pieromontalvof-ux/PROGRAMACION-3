import unittest
from datetime import date
from unittest.mock import patch
import test_purchase_review as fixtures
from app.multiagente.agents.orchestrator import purchase_flow as flow
from app.multiagente.agents.orchestrator.purchase_horizon import resolve


class ConversationalPurchaseTests(unittest.TestCase):
    def test_missing_second_recipe_does_not_apply_a_partial_extra(self):
        from app.multiagente.agents.orchestrator import purchase_extras
        from app.multiagente.api.provider import AssistantError
        recipes=[{'item_carta':'Pisco Sour','componentes':[{'tipo_componente':'PRODUCTO','id_producto':7}]}]
        selected=purchase_extras.intent('10% general y 10% extra para Pisco Sour y Maracuyá Sour')
        with patch.object(flow.tools,'records',return_value=recipes), \
             patch('app.multiagente.api.purchases.prepare') as prepare:
            with self.assertRaisesRegex(AssistantError,'maracuya sour'):
                purchase_extras.prepare({},selected,6)
        prepare.assert_not_called()

    def test_shared_extra_for_two_recipes_is_applied_once_per_ingredient(self):
        from app.multiagente.agents.orchestrator import purchase_extras
        recipes=[{'item_carta':'Pisco Sour','componentes':[{'tipo_componente':'PRODUCTO','id_producto':7}, {'tipo_componente':'PRODUCTO','id_producto':8}]},
                 {'item_carta':'Maracuyá Sour','componentes':[{'tipo_componente':'PRODUCTO','id_producto':7}, {'tipo_componente':'PRODUCTO','id_producto':9}]}]
        selected=purchase_extras.intent('quiero un incremento de 10% un 10% adicional de los productos del pisco sour y el pisco sour de maracuyá')
        with patch.object(flow.tools,'records',return_value=recipes), \
             patch.object(flow.tools,'native',return_value={'productos':[{'id_producto':pid} for pid in (7,8,9)]}), \
             patch('app.multiagente.api.purchases.prepare',return_value={}) as prepare:
            result=purchase_extras.prepare({},selected,6)
        self.assertEqual(prepare.call_args.args[3]['adicionales'],[{'id_producto':pid,'porcentaje':'10'} for pid in (7,8,9)])
        self.assertIn('Maracuyá Sour',result['respuesta'])

    setUp=fixtures.PurchaseReviewTests.setUp
    review=fixtures.PurchaseReviewTests.review
    def test_date_variants_keep_current_month(self):
        for phrase in ('hasta el 22 de ese mes', 'hasta el 22 del mes', 'hasta el 22 de este mes'):
            with self.subTest(phrase=phrase):
                self.assertEqual(resolve(phrase, date(2026,11,16),waiting=True),('2026-11-16','2026-11-22'))

    def test_two_percentages_prepare_table_without_model_loop(self):
        first,_,_,_=self.review()
        recipes=[{'activo':True,'item_carta':'Pisco Sour','componentes':[
            {'tipo_componente':'PRODUCTO','id_producto':7},
            {'tipo_componente':'PRODUCTO','id_producto':8}]}]
        plan={'recurso':'ordenes_compra','revision_compra':[{'producto':'Pisco','cantidad_final':2}]}
        with patch.object(flow.tools,'records',return_value=recipes), \
             patch.object(flow.tools,'native',return_value={'productos':[{'id_producto':7},{'id_producto':8}]}), \
             patch('app.multiagente.api.purchases.prepare',return_value=plan) as prepare, \
             patch.object(flow,'run_specialist',side_effect=AssertionError('No read-only loop')):
            result=flow.handle({},'un pedido con un 10%, y con un 10% adicional de los productos que son para el pisco saur',token=first['flujo_compra'])
        self.assertEqual(result['plan'],plan)
        changes=prepare.call_args.args[3]
        self.assertEqual(str(changes['porcentaje_general']),'10')
        self.assertEqual(changes['adicionales'],[{'id_producto':7,'porcentaje':'10'},{'id_producto':8,'porcentaje':'10'}])
        self.assertIn('dias_abastecimiento',changes)

    def test_question_does_not_prepare(self):
        first,_,_,_=self.review()
        with patch.object(flow,'run_specialist',return_value={'respuesta':'Explicación','plan':None}), \
             patch('app.multiagente.api.purchases.prepare') as prepare:
            flow.handle({},'¿Y si uso 10% general y 10% adicional para Pisco Sour?',token=first['flujo_compra'])
        prepare.assert_not_called()

    def test_more_variants_and_capture_typos_prepare_without_query_loop(self):
        first,_,_,_=self.review()
        prompts=(
            'quiero pedir un 10% extra, pero un 10 adicional para los productos que componen el pisco saur',
            'quiero pedir un 10 porciento extra, y un 10 más para productos del pisco saur',
            'quiero hacer un pedido del 10 % extra, pero a los insumos de pisco saur auméntale 10 mas',
            'haz un pedido con un 10%, y un 10% mas para los insumos de pisco saur',
            'has un pedido con un 10%, y un 10% mas ara los insumos de lpisco saur',
            '10 por ciento general y 20 por ciento más para los insumos del Pisco Sour',
        )
        recipes=[{'item_carta':'Pisco Sour','componentes':[{'tipo_componente':'PRODUCTO','id_producto':7}]}]
        for prompt in prompts:
            with self.subTest(prompt=prompt), patch.object(flow.tools,'records',return_value=recipes), \
                 patch.object(flow.tools,'native',return_value={'productos':[{'id_producto':7}]}), \
                 patch('app.multiagente.api.purchases.prepare',return_value={'recurso':'ordenes_compra'}) as prepare, \
                 patch.object(flow,'run_specialist',side_effect=AssertionError('No model loop')):
                result=flow.handle({},prompt,token=first['flujo_compra'])
                self.assertIsNotNone(result['plan'])
                self.assertEqual(prepare.call_args.args[3]['porcentaje_general'],'10')
                self.assertEqual(prepare.call_args.args[3]['adicionales'][0]['id_producto'],7)
                self.assertEqual(prepare.call_args.args[3]['adicionales'][0]['porcentaje'], '20' if '20 por ciento' in prompt else '10')

    def test_unresolved_two_margins_asks_once_instead_of_looping(self):
        first,_,_,_=self.review()
        with patch.object(flow,'run_specialist',side_effect=AssertionError('No query loop')):
            result=flow.handle({},'haz el pedido con 10% y 20%',token=first['flujo_compra'])
        self.assertIsNone(result['plan'])
        self.assertIn('insumos',result['respuesta'])
        self.assertNotIn('límite',result['respuesta'])

    def test_ingredient_units_are_not_assumed_to_be_percentages(self):
        from app.multiagente.agents.orchestrator.purchase_extras import intent
        self.assertIsNone(intent('10% general pero para Pisco Sour agrega 10 huevos'))
        self.assertIsNone(intent('¿Y si al Pisco Sour auméntale 10 más con 10% general?'))

    def test_failed_recipe_lookup_keeps_both_percentages_for_retry(self):
        from app.multiagente.api.provider import AssistantError
        first,_,_,_=self.review()
        with patch('app.multiagente.agents.orchestrator.purchase_extras.prepare',side_effect=AssistantError('Consulta no disponible')):
            failed=flow.handle({},'10% general y 20% extra para Pisco Sour',token=first['flujo_compra'])
        saved=flow.load(failed['flujo_compra'])
        self.assertEqual(saved['adicional_receta']['extra'],'20')
        with patch('app.multiagente.agents.orchestrator.purchase_extras.prepare',return_value={'respuesta':'Revisa el cuadro','plan':{'recurso':'ordenes_compra'}}) as prepare:
            result=flow.handle({},'dale',token=failed['flujo_compra'])
        self.assertIsNotNone(result['plan'])
        self.assertEqual(prepare.call_args.args[1]['extra'],'20')

    def test_intermediate_ingredients_are_resolved_once_without_inventing(self):
        from app.multiagente.agents.orchestrator import purchase_extras
        recipes=[{'item_carta':'Pisco Sour','componentes':[
            {'tipo_componente':'PRODUCTO','id_producto':7},
            {'tipo_componente':'SUBPRODUCTO','id_subproducto':3}]}]
        intermediate=[{'id_subproducto':3,'ingredientes':[{'id_producto':7},{'id_producto':8}]}]
        with patch.object(flow.tools,'records',side_effect=[recipes,intermediate]), \
             patch.object(flow.tools,'native',return_value={'productos':[{'id_producto':7},{'id_producto':8}]}), \
             patch('app.multiagente.api.purchases.prepare',return_value={}) as prepare:
            purchase_extras.prepare({},purchase_extras.intent('10% general y 20% adicional para Pisco Sour'),6)
        self.assertEqual(len(prepare.call_args.args[3]['adicionales']),2)

    def test_ambiguous_recipes_do_not_prepare_an_order(self):
        from app.multiagente.agents.orchestrator import purchase_extras
        from app.multiagente.api.provider import AssistantError
        rows=[{'item_carta':name,'componentes':[]} for name in ('Pisco Sour clásico','Pisco Sour especial')]
        with patch.object(flow.tools,'records',return_value=rows), \
             patch('app.multiagente.api.purchases.prepare') as prepare:
            with self.assertRaises(AssistantError):
                purchase_extras.prepare({},purchase_extras.intent('10% general y 20% adicional para Pisco Sour'),6)
        prepare.assert_not_called()

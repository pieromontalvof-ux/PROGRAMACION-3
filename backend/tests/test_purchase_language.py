import json
import unittest
from datetime import date
from unittest.mock import patch
import test_purchase_review as fixtures
from app.multiagente.agents.orchestrator import purchase_flow as flow


def decision(**changes):
    value=dict(accion='ACTUALIZAR',porcentaje_general=None,porcentaje_adicional=None,
               bebida=None,quitar_adicional=False,hasta=None,dias=None,aclaracion=None)
    return {**value,**changes}


class PurchaseLanguageTests(unittest.TestCase):
    def test_same_extra_for_two_beverages_survives_confirmation(self):
        first,_,_,_=self.review()
        with self.model(decision(porcentaje_general=10,porcentaje_adicional=10,bebida='Pisco Sour y Pisco Sour de Maracuyá')), \
             patch('app.multiagente.agents.orchestrator.purchase_extras.prepare',return_value={'respuesta':'Cuadro','plan':{}}) as prepare:
            result=flow.handle({},'10 general y 10 adicional a ambos sours',token=first['flujo_compra'],interpret=True)
        selected=prepare.call_args.args[1]
        self.assertEqual(selected['targets'],[['pisco','sour'],['pisco','sour','maracuya']])
        with self.model(decision(accion='CONTINUAR')), \
             patch('app.multiagente.agents.orchestrator.purchase_extras.prepare',return_value={'respuesta':'Cuadro','plan':{}}) as continued:
            flow.handle({},'sí confirmo',token=result['flujo_compra'],interpret=True)
        self.assertEqual(continued.call_args.args[1]['targets'],selected['targets'])
        self.assertEqual(continued.call_args.args[1]['extra'],'10')

    setUp=fixtures.PurchaseReviewTests.setUp
    review=fixtures.PurchaseReviewTests.review

    def model(self,value):
        return patch('app.multiagente.agents.orchestrator.purchase_language.provider.respond',return_value=[{
            'type':'function_call','name':'interpretar_pedido','arguments':json.dumps(value)}])

    def test_natural_extra_uses_saved_general_and_preserves_deadline(self):
        first,_,_,_=self.review()
        saved=flow.load(first['flujo_compra']);saved['margen']='10'
        with self.model(decision(porcentaje_adicional=15,bebida='Pisco Sour')) as model, \
             patch('app.multiagente.agents.orchestrator.purchase_extras.prepare',return_value={'respuesta':'Cuadro','plan':{'recurso':'ordenes_compra'}}) as prepare:
            result=flow.handle({},'a lo del sour súbele otros quince',token=flow.serializer().dumps(saved),interpret=True)
        self.assertIsNotNone(result['plan'])
        self.assertEqual(prepare.call_args.args[1]['general'],'10')
        self.assertEqual(prepare.call_args.args[1]['extra'],'15')
        self.assertEqual(prepare.call_args.args[2],saved['dias_abastecimiento'])
        model.assert_called_once()

    def test_initial_purchase_request_cannot_become_a_freeform_analysis(self):
        request=fixtures.REQUEST.replace('de los próximos siete días','hasta la próxima entrega')
        for action in ('PREGUNTAR','OTRA','COBERTURA'):
            with self.subTest(action=action),self.model(decision(accion=action)), \
                 patch.object(flow,'run_specialist',side_effect=AssertionError('No analysis before deadline')), \
                 patch.object(flow.event_agent,'run',side_effect=AssertionError('No events before deadline')):
                result=flow.handle({},request,interpret=True)
                self.assertIn('¿Hasta qué fecha',result['respuesta'])
                self.assertIsNone(result['plan'])

    def test_question_never_changes_chosen_percentages(self):
        first,_,_,_=self.review()
        with self.model(decision(accion='PREGUNTAR')), \
             patch.object(flow,'run_specialist',return_value={'respuesta':'Explicación','plan':None}) as specialist:
            result=flow.handle({},'¿Qué pasaría si aumento veinte?',token=first['flujo_compra'],interpret=True)
        self.assertIsNone(result['plan'])
        self.assertEqual(flow.load(result['flujo_compra'])['margen'],flow.load(first['flujo_compra'])['margen'])
        self.assertEqual(specialist.call_args.kwargs['writable_resources'],())

    def test_uncertain_intent_asks_only_for_missing_detail(self):
        first,_,_,_=self.review()
        with self.model(decision(accion='ACLARAR',aclaracion='¿Diez unidades o diez por ciento?')):
            result=flow.handle({},'pon diez más',token=first['flujo_compra'],interpret=True)
        self.assertEqual(result['respuesta'],'¿Diez unidades o diez por ciento?')
        self.assertIsNone(result['plan'])

    def test_invalid_model_values_are_rejected_without_changing_state(self):
        first,_,_,_=self.review()
        with self.model(decision(porcentaje_general=1001)):
            result=flow.handle({},'sube el margen',token=first['flujo_compra'],interpret=True)
        self.assertIsNone(result['plan'])
        self.assertEqual(flow.load(result['flujo_compra'])['margen'],flow.load(first['flujo_compra'])['margen'])

    def test_changing_date_preserves_chosen_general_and_extra(self):
        first,_,_,_=self.review()
        saved=flow.load(first['flujo_compra']);saved['margen']='10'
        saved['adicional_receta']={'general':'10','extra':'20','terms':['pisco','sour']}
        execute=flow.handle
        with self.model(decision(hasta='2026-11-28')), patch.object(flow,'handle',return_value={'respuesta':'Nueva fecha'}) as native:
            execute({},'que dure hasta el veintiocho',token=flow.serializer().dumps(saved),interpret=True)
        self.assertEqual(native.call_args.args[1],'hasta el 2026-11-28')
        next_state=flow.load(native.call_args.args[4])
        self.assertEqual(next_state['margen'],'10')
        self.assertEqual(next_state['adicional_receta']['extra'],'20')

    def test_provider_failure_preserves_state_without_preparing(self):
        from app.multiagente.api.provider import AssistantError
        first,_,_,_=self.review()
        with patch('app.multiagente.agents.orchestrator.purchase_language.provider.respond',side_effect=AssistantError('Conexión no disponible')), \
             patch.object(flow.purchase_agent,'run') as prepare:
            result=flow.handle({},'mejor quince a todo',token=first['flujo_compra'],interpret=True)
        self.assertIsNone(result['plan'])
        self.assertEqual(flow.load(result['flujo_compra']),flow.load(first['flujo_compra']))
        prepare.assert_not_called()

    def test_general_ten_stays_decimal_and_replaces_only_general(self):
        first,_,_,_=self.review()
        saved=flow.load(first['flujo_compra']);saved['margen']='5'
        saved['adicional_receta']={'general':'5','extra':'20','terms':['pisco','sour']}
        with self.model(decision(porcentaje_general=10)), \
             patch('app.multiagente.agents.orchestrator.purchase_extras.prepare',return_value={'respuesta':'Cuadro','plan':{}}) as prepare:
            flow.handle({},'mejor diez para todo',token=flow.serializer().dumps(saved),interpret=True)
        self.assertEqual(prepare.call_args.args[1]['general'],'10')
        self.assertEqual(prepare.call_args.args[1]['extra'],'20')

    def test_clearing_extra_keeps_general(self):
        first,_,_,_=self.review()
        saved=flow.load(first['flujo_compra']);saved['margen']='10'
        saved['adicional_receta']={'general':'10','extra':'20','terms':['pisco','sour']}
        with self.model(decision(quitar_adicional=True)), \
             patch.object(flow.purchase_agent,'run',return_value={'respuesta':'Cuadro','plan':None}) as prepare:
            result=flow.handle({},'ya no le pongas extra al sour',token=flow.serializer().dumps(saved),interpret=True)
        self.assertNotIn('adicional_receta',flow.load(result['flujo_compra']))
        self.assertIn('10%',prepare.call_args.args[1])

    def test_initial_explicit_duration_runs_forward_review(self):
        request=fixtures.REQUEST.replace('de los próximos siete días','para 10 días')
        with self.model(decision(dias=10)), \
             patch.object(flow.event_agent,'run',return_value=fixtures.EVENTS) as events, \
             patch.object(flow.demand_agent,'run',return_value=fixtures.ANALYSIS), \
             patch.object(flow.tools,'native',side_effect=lambda path:fixtures.STOCK if path=='/inventarios/stock' else fixtures.BASE):
            result=flow.handle({'local_activo':{'nombre':'Sheraton'}},request,interpret=True)
        events.assert_called_once()
        self.assertTrue(flow.load(result['flujo_compra'])['revision_completada'])
        self.assertEqual(flow.load(result['flujo_compra'])['dias_abastecimiento'],10)

    def test_missing_extra_remembers_general_and_beverage_until_answered(self):
        first,_,_,_=self.review()
        with self.model(decision(accion='ACLARAR',porcentaje_general=10,bebida='Pisco Sour')):
            partial=flow.handle({},'diez general y un extra al sour',token=first['flujo_compra'],interpret=True)
        saved=flow.load(partial['flujo_compra'])
        self.assertEqual(saved['margen'],'10')
        self.assertEqual(saved['adicional_pendiente']['terms'],['pisco','sour'])
        with self.model(decision(porcentaje_adicional=15)), \
             patch('app.multiagente.agents.orchestrator.purchase_extras.prepare',return_value={'respuesta':'Cuadro','plan':{}}) as prepare:
            flow.handle({},'quince',token=partial['flujo_compra'],interpret=True)
        self.assertEqual(prepare.call_args.args[1]['extra'],'15')
        self.assertEqual(prepare.call_args.args[1]['general'],'10')

    def test_pending_extra_does_not_discard_date_in_same_message(self):
        first,_,_,_=self.review()
        with self.model(decision(accion='ACLARAR',porcentaje_general=10,bebida='Pisco Sour',hasta='2026-11-28')):
            partial=flow.handle({},'diez general, un extra al sour, hasta el 28',token=first['flujo_compra'],interpret=True)
        self.assertEqual(flow.load(partial['flujo_compra'])['plazo_pendiente_revision'],'2026-11-28')
        execute=flow.handle
        with self.model(decision(porcentaje_adicional=15)), patch.object(flow,'handle',return_value={}) as native:
            execute({},'quince',token=partial['flujo_compra'],interpret=True)
        self.assertEqual(native.call_args.args[1],'hasta el 2026-11-28')
        self.assertEqual(flow.load(native.call_args.args[4])['adicional_receta']['extra'],'15')

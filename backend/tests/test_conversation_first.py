import unittest
import json
from app.multiagente.api.provider import AssistantError
from unittest.mock import patch
from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
from app.multiagente.api import routes, forms
from app.multiagente.agents.catalog_specialists import SPECIALISTS
from app.multiagente.agents.orchestrator import communication


ANSWER=[{'type':'message','content':[{'type':'output_text','text':'Revisé las opciones. Falta elegir un menaje.'}]}]


class ConversationFirstTests(unittest.TestCase):
    def test_promotion_period_reply_stays_with_its_original_specialist(self):
        initial='Quiero comparar dos opciones de promocion con bebidas, entradas, ventas y stock. No crear todavia.'
        question={'agente':'promociones','respuesta':'Que periodo de ventas quieres comparar?','consultas':[],'plan':None}
        with patch('app.multiagente.agents.orchestrator.presentation_advice.run',return_value=None), \
             patch.object(routes.agent,'run',return_value=question), \
             patch('app.multiagente.agents.catalog_specialists.Specialist.run',return_value={
                 'respuesta':'Analizo cuatro meses en todas las tiendas.','consultas':[],'plan':None}) as specialist:
            first=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,json={
                'modo':'conversacion','instruccion':initial})
            self.assertEqual(first.status_code,200,first.json)
            self.assertIn('continuacion',first.json)
            second=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,json={
                'modo':'conversacion','instruccion':'revisa los ultimo 4 meses',
                'borrador_previo':question['respuesta'],'contexto_previo':initial,
                'continuacion':first.json['continuacion']})
        self.assertEqual(second.status_code,200,second.json)
        self.assertEqual(second.json['agente'],'promociones')
        self.assertIn(initial,specialist.call_args.args[3])
        self.assertEqual(specialist.call_args.args[1],'revisa los ultimo 4 meses')

    def setUp(self):
        self.app=Flask(__name__)
        self.app.config.update(JWT_SECRET_KEY='conversation-test-secret-key-32-characters',SECRET_KEY='conversation-signing')
        JWTManager(self.app)
        self.app.register_blueprint(routes.asistente_ia_bp,url_prefix='/api/asistente-ia')
        self.ctx=self.app.app_context();self.ctx.push();self.addCleanup(self.ctx.pop)
        self.token=create_access_token(identity='1',additional_claims={'id_perfil':2,'id_local':1})
        self.headers={'Authorization':'Bearer '+self.token};routes._attempts.clear()
        for target,kwargs in [
            ('app.multiagente.api.routes.obtener_sesion_actual',{'return_value':({'menu':[]},200)}),
            ('app.multiagente.api.tools.allowed',{'return_value':True}),
            ('app.multiagente.api.tools.authorize',{}),
            ('app.multiagente.api.configuration.saved',{'return_value':None}),
            ('app.multiagente.api.library.for_skills',{'return_value':''}),
            ('app.multiagente.agents.runtime.db.session.rollback',{}),
            ('app.multiagente.agents.activity.finish',{'return_value':None}),
        ]:
            p=patch(target,**kwargs);p.start();self.addCleanup(p.stop)

    def test_creation_starts_with_specialist_conversation_not_blank_form(self):
        with patch.object(routes.agent,'run',return_value={'respuesta':'Revisé proveedores. Dime qué categorías deseas asignar.','consultas':[],'plan':None,'agente':'carta_recetas'}) as specialist, \
             patch.object(forms,'open_form') as form:
            response=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,json={'instruccion':'Crear proveedor llamado Ejemplo'})
        self.assertEqual(response.status_code,200,response.json)
        specialist.assert_called_once();form.assert_not_called()
        self.assertNotIn('formulario',response.json)

    def test_new_beverage_recipe_asks_batch_or_glass_and_seals_the_sale_measure(self):
        from tests.test_preparation_flow import TASK
        with patch('app.multiagente.api.provider.respond', return_value=ANSWER):
            response = self.app.test_client().post('/api/asistente-ia/preparar', headers=self.headers,
                json={'instruccion': TASK})
        self.assertEqual(response.status_code, 200, response.json)
        self.assertIn('por lote', response.json['respuesta'])
        self.assertIn('por cada vaso', response.json['respuesta'])
        self.assertNotIn('_preparacion', response.json)
        state = communication.serializer().loads(response.json['continuacion'])
        self.assertEqual(state['actual']['preparacion']['medida_venta'], {'cantidad': '400', 'unidad': 'MLT'})

    def test_reference_cannot_prepare_a_silent_change_from_400ml_to_one_portion(self):
        from tests.test_preparation_flow import TASK
        call = [{'type':'function_call','call_id':'proposal','name':'preparar_cambio', 'arguments':json.dumps({
            'recurso':'presentaciones','accion':'crear','id':None,
            'datos_json':json.dumps({'contenido':1,'unidad':'PORCION'})})}]
        context = json.dumps({'tarea_original':TASK,'contexto_original':'','aclaraciones':['Por cada vaso.']})
        with self.app.test_request_context('/api/asistente-ia/preparar', json={'modo':'conversacion'}), \
             patch('app.multiagente.api.provider.respond', side_effect=[call,ANSWER]), \
             patch.object(forms,'prepare',return_value={'recurso':'presentaciones','accion':'crear'}) as prepare:
            result = SPECIALISTS['presentaciones'].run({}, 'Cámbialo como la chicha', context=context)
        self.assertIsNone(result['plan'])
        prepare.assert_not_called()

    def test_recipe_with_possible_purchase_does_not_start_the_purchase_flow(self):
        with patch('app.multiagente.api.provider.respond', return_value=ANSWER):
            response = self.app.test_client().post('/api/asistente-ia/preparar', headers=self.headers, json={
                'instruccion': 'Quiero crear una receta de maracuya; revisa el stock y, si falta, vemos comprar insumos.'})
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json['agente'], 'recetas')
        self.assertNotIn('flujo_compra', response.json)

    def test_explicit_manual_mode_still_opens_optional_form(self):
        with patch.object(forms,'open_form',return_value={'recurso':'proveedores'}) as form,patch.object(routes.agent,'run') as agent:
            response=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,json={'instruccion':'Crear proveedor','modo':'formulario'})
        self.assertEqual(response.status_code,200,response.json)
        form.assert_called_once();agent.assert_not_called()

    def test_chat_does_not_offer_model_a_tool_that_forces_a_form(self):
        with self.app.test_request_context('/api/asistente-ia/preparar',json={'instruccion':'Crear presentación'}), \
             patch('app.multiagente.api.provider.respond',return_value=ANSWER) as model:
            SPECIALISTS['presentaciones'].run({},'Crear presentación de limonada de 500 mL')
        definitions={d['name'] for d in model.call_args.args[1]}
        self.assertNotIn('abrir_formulario',definitions)
        self.assertIn('preparar_cambio',definitions)
        self.assertIn('solicitar_especialista',definitions)

    def test_missing_requirement_delegates_conversation_and_preserves_parent_data(self):
        result={'agente':'presentaciones','respuesta':'Falta categoría','consultas':[],'plan':None,
                'traspaso':{'recurso':'categorias_carta','instruccion':'Proponer categoría Bebidas de temporada','motivo':'La categoría no existe.'}}
        with self.app.test_request_context('/api/asistente-ia/preparar',headers=self.headers,json={'instruccion':'Crear limonada'}), \
             patch.object(communication.drafts,'scope',return_value={'usuario':1,'perfil':2,'local':1}), \
             patch.object(communication,'invoke',return_value={'respuesta':'Sugiero el prefijo BT; puedes cambiarlo antes de confirmar.','consultas':[],'plan':None,'agente':'categorias_carta'}) as child, \
             patch.object(forms,'open_form') as form:
            response=communication.coordinate({},result,'Crear Limonada especial, 500 mL, S/15',context='Elegir menaje existente')
            state=communication.load(response['continuacion'])
        child.assert_called_once();form.assert_not_called()
        self.assertEqual(state['pila'][0]['instruccion'],'Crear Limonada especial, 500 mL, S/15')
        self.assertIn('menaje',state['pila'][0]['contexto'])
        self.assertNotIn('formulario',response)

    def test_conversational_proposal_reuses_validation_without_forcing_form_or_writing(self):
        call=[{'type':'function_call','call_id':'proposal','name':'preparar_cambio','arguments':json.dumps({
            'recurso':'menajes','accion':'crear','id':None,'datos_json':json.dumps({'nombre':' Vaso especial '})})}]
        plan={'recurso':'menajes','accion':'crear','id':None,'datos':{'nombre':'Vaso especial'}}
        with self.app.test_request_context('/api/asistente-ia/preparar',json={'instruccion':'Crear menaje'}), \
             patch('app.multiagente.api.provider.respond',return_value=call), \
             patch.object(forms,'open_form',return_value={'categorias':[],'menajes':[]}), \
             patch.object(routes.tools,'prepare',return_value=plan) as prepare, \
             patch.object(routes.tools,'execute') as execute:
            result=SPECIALISTS['menajes'].run({},'Crear menaje Vaso especial')
        self.assertIs(result['plan'],plan)
        self.assertEqual(prepare.call_args.args[4],{'nombre':'Vaso especial'})
        execute.assert_not_called()
        self.assertNotIn('formulario',result)

    def test_category_clarification_routes_to_conversation_and_keeps_original_context(self):
        with patch.object(routes.agent,'run',return_value={'respuesta':'Revisé categorías de productos.','consultas':[],'plan':None,'agente':'carta_recetas'}) as agent:
            response=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,json={
                'instruccion':'de productos','borrador_previo':forms.CATEGORY_QUESTION,'contexto_previo':'Crear categoría Vegetales frescos con prefijo VF'})
        self.assertEqual(response.status_code,200,response.json)
        self.assertIn('Crear categoría de productos',agent.call_args.args[1])
        self.assertIn('Vegetales frescos',agent.call_args.args[3])

    def test_existing_requirement_can_replace_creation_and_resume_original_task(self):
        scope={'usuario':1,'perfil':2,'local':1}
        state={'scope':scope,'paso':'step','conversacion':True,'mensajes':[],
               'actual':{'agente':'categorias_carta','recurso':'categorias_carta','instruccion':'Crear categoría','previo':'','contexto':''},
               'pila':[{'agente':'presentaciones','instruccion':'Limonada especial 500 mL a S/15','previo':'','contexto':'Menaje pendiente'}]}
        result={'agente':'categorias_carta','respuesta':'Usar Bebidas','consultas':[],'plan':None,
                'seleccion_existente':{'recurso':'categorias_carta','id':42}}
        with self.app.test_request_context('/api/asistente-ia/preparar',json={'instruccion':'Usa Bebidas existente'}), \
             patch.object(communication,'invoke',return_value={'respuesta':'Conservo la limonada; falta el menaje.','consultas':[],'plan':None,'agente':'presentaciones'}) as parent, \
             patch.object(routes.tools,'current_record',return_value={'id_categoria_carta':42,'nombre':'Bebidas','activo':True}), \
             patch.object(routes.tools,'execute') as execute:
            final=communication.coordinate({},result,'Usa Bebidas existente',state=state)
        self.assertEqual(final['agente'],'presentaciones')
        self.assertEqual(state['pila'],[])
        self.assertIn('500 mL',parent.call_args.args[1]['instruccion'])
        verified=parent.call_args.args[1]['resultados_confirmados'][0]['resultado']
        self.assertEqual(verified['id'],42)
        self.assertEqual(verified['registro']['nombre'],'Bebidas')
        execute.assert_not_called()

    def test_existing_reference_cannot_resolve_a_different_or_inactive_requirement(self):
        for resource, record in [('menajes',{'activo':True}),('categorias_carta',{'activo':False})]:
            state={'scope':{},'paso':'step','conversacion':True,'mensajes':[],
                   'actual':{'agente':'categorias_carta','recurso':'categorias_carta','instruccion':'Crear categoría','previo':'','contexto':''},
                   'pila':[{'agente':'presentaciones','instruccion':'Crear limonada','previo':'','contexto':''}]}
            result={'agente':'categorias_carta','respuesta':'Elegir','consultas':[],'plan':None,
                    'seleccion_existente':{'recurso':resource,'id':42}}
            with self.subTest(resource=resource),patch.object(routes.tools,'current_record',return_value=record), \
                 patch.object(communication,'invoke') as parent,self.assertRaises(AssistantError):
                communication.coordinate({},result,'Usar existente',state=state)
            parent.assert_not_called()
            self.assertEqual(len(state['pila']),1)

    def test_pending_reference_tool_is_scoped_to_the_actual_child(self):
        choose=[{'type':'function_call','call_id':'choose','name':'usar_registro_existente',
                 'arguments':json.dumps({'recurso':'menajes','id':4})}]
        with self.app.test_request_context('/api/asistente-ia/preparar',json={'instruccion':'Usar Vaso existente'}), \
             patch('app.multiagente.api.provider.respond',return_value=choose) as model, \
             patch.object(routes.tools,'current_record',return_value={'id_menaje':4,'nombre':'Vaso','activo':True}):
            result=communication.invoke({}, {'agente':'menajes','recurso':'menajes','instruccion':'Usar Vaso existente','previo':'','contexto':''})
        self.assertEqual(result['seleccion_existente'],{'recurso':'menajes','id':4})
        self.assertIsNone(communication.current_requirement())
        definition=next(d for d in model.call_args.args[1] if d['name']=='usar_registro_existente')
        self.assertEqual(definition['parameters']['properties']['recurso']['enum'],['menajes'])

    def test_catalog_requirement_keeps_the_supplier_request_for_after_confirmation(self):
        plan={'recurso':'categorias_productos','accion':'crear','id':None,'datos':{'nombre':'Vegetales','prefijo':'VEG'}}
        result={'agente':'carta_recetas','respuesta':'Revisa la categoría nueva.','consultas':[],'plan':plan}
        with self.app.test_request_context('/api/asistente-ia/preparar',json={'instruccion':'Crear proveedor Huerto'}), \
             patch.object(communication.drafts,'scope',return_value={'usuario':1,'perfil':2,'local':1}):
            response=communication.coordinate({},result,'Crear proveedor Huerto para Vegetales')
            state=communication.load(response['continuacion'])
        self.assertEqual(state['pila'][0]['instruccion'],'Crear proveedor Huerto para Vegetales')
        self.assertEqual(state['actual']['recurso'],'categorias_productos')
        self.assertEqual(response['tarea_pendiente'],'Crear proveedor Huerto para Vegetales')
        self.assertEqual(plan['_coordinacion'],state['paso'])

    def test_supplier_task_survives_a_question_before_preparing_its_category(self):
        initial={'agente':'carta_recetas','respuesta':'La categoría no existe. ¿Quieres proponer su creación?', 'consultas':[], 'plan':None}
        category={'recurso':'categorias_productos','accion':'crear','id':None,'datos':{'nombre':'Vegetales','prefijo':'VEG'}}
        with patch.object(routes.agent,'run',return_value=initial):
            first=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,
                json={'instruccion':'Crear proveedor Huerto para categoría Vegetales'})
        self.assertEqual(first.status_code,200,first.json)
        self.assertIn('continuacion',first.json)
        with patch.object(communication,'invoke',return_value={'agente':'carta_recetas','respuesta':'Revisa categoría','consultas':[],'plan':category}), \
             patch.object(routes.tools,'readable',return_value={}), \
             patch.object(routes.drafts,'save',return_value='11111111-1111-4111-8111-111111111111'):
            second=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,
                json={'instruccion':'Sí, créala','continuacion':first.json['continuacion']})
        self.assertEqual(second.status_code,200,second.json)
        self.assertEqual(second.json['tarea_pendiente'],'Crear proveedor Huerto para categoría Vegetales')
        signed=communication.serializer().loads(second.json['continuacion'])
        self.assertEqual(signed['pila'][0]['recurso_objetivo'],'proveedores')

    def test_existing_selection_cannot_oscillate_through_unlimited_handoffs(self):
        state={'scope':{},'paso':'step','conversacion':True,'mensajes':[],
               'actual':{'agente':'categorias_carta','recurso':'categorias_carta','instruccion':'Categoría','previo':'','contexto':''},
               'pila':[{'agente':'presentaciones','instruccion':'Limonada','previo':'','contexto':''}]}
        def result(frame):
            base={'agente':frame['agente'],'respuesta':'','consultas':[],'plan':None}
            if frame['agente']=='presentaciones':
                return {**base,'traspaso':{'recurso':'categorias_carta','instruccion':'Elegir Bebidas','motivo':'Repetir requisito'}}
            return {**base,'seleccion_existente':{'recurso':'categorias_carta','id':42}}
        with self.app.test_request_context('/api/asistente-ia/preparar',json={'instruccion':'Usa existente'}), \
             patch.object(communication,'invoke',side_effect=lambda session,frame:result(frame)) as invoke, \
             patch.object(routes.tools,'current_record',return_value={'id_categoria_carta':42,'activo':True}), \
             self.assertRaisesRegex(AssistantError,'secuencia repetida'):
            communication.coordinate({},result(state['actual']),'Usa existente',state=state)
        self.assertLessEqual(invoke.call_count,12)

    def test_optional_sheet_recovery_preserves_boolean_presentation_status(self):
        from app.multiagente.api import workspace
        saved={'frames':[{'form':{'recurso':'presentaciones'},'values':{'activo':False},'version':0}],
               'proposal':None,'dirty':False,'saved':None,'draftId':None}
        self.assertIs(workspace.workflow(saved)['frames'][0]['values']['activo'],False)
        saved['frames'][0]['values']['activo']='false'
        with self.assertRaises(AssistantError):workspace.workflow(saved)

    def test_full_specification_replaces_old_form_task_with_compact_reviewed_advice(self):
        from tests.test_presentation_advice import ROWS,REQUEST
        from app.multiagente.api import workspace
        legacy=communication.serializer().dumps({'scope':{'usuario':1,'perfil':2,'local':1},'paso':'old',
            'conversacion':False,'pila':[],'mensajes':[], 'actual':{'agente':'categorias_carta','instruccion':'Crear categoría','previo':'','contexto':''}})
        with patch.object(routes.tools,'records',side_effect=lambda session,resource:ROWS[resource]), \
             patch.object(forms,'open_form') as form,patch.object(routes.agent,'run') as model:
            response=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,
                json={'instruccion':REQUEST,'continuacion':legacy})
        self.assertEqual(response.status_code,200,response.json)
        form.assert_not_called();model.assert_not_called()
        self.assertNotIn('formulario',response.json)
        signed=communication.serializer().loads(response.json['continuacion'])
        self.assertEqual(signed['actual']['agente'],'presentaciones')
        self.assertEqual(signed['actual']['instruccion'],REQUEST)
        self.assertIn('opciones_revisadas',signed['actual']['contexto'])
        self.assertNotIn('_referencias_revisadas',response.json)
        workspace.result(response.json)

    def test_handoff_passes_latest_measure_price_and_reviewed_options_to_child(self):
        scope={'usuario':1,'perfil':2,'local':1}
        state={'scope':scope,'paso':'step','conversacion':True,'pila':[],'mensajes':[],
               'actual':{'agente':'presentaciones','recurso_objetivo':'presentaciones',
                         'instruccion':'Crear Limonada especial 500 mL a S/15',
                         'previo':'','contexto':'Referencia verificada: Vaso usado para 400 mL'}}
        handoff={'agente':'presentaciones','respuesta':'Revisar categoría','consultas':[],'plan':None,
                 'traspaso':{'recurso':'categorias_carta','instruccion':'Crear Bebidas de temporada',
                             'motivo':'Categoría pendiente'}}
        with self.app.test_request_context(json={'modo':'conversacion'}), \
             patch.object(communication.drafts,'scope',return_value=scope), \
             patch('app.multiagente.api.provider.respond',return_value=ANSWER) as model:
            result=communication.coordinate({},handoff,'Ajusta a 400 mL por S/12, usa Vaso',state=state)
        history=json.loads(json.loads(model.call_args.args[0][1]['content'])['contexto_previo'])
        parent=json.loads(history['contexto_original'])
        self.assertIn('Ajusta a 400 mL por S/12, usa Vaso',parent['aclaraciones'])
        self.assertIn('Vaso usado para 400 mL',parent['contexto_original'])
        self.assertEqual(communication.serializer().loads(result['continuacion'])['pila'][0]['aclaraciones'],
                         ['Ajusta a 400 mL por S/12, usa Vaso'])

    def test_resume_includes_corrections_made_while_category_was_pending(self):
        scope={'usuario':1,'perfil':2,'local':1}
        state={'scope':scope,'paso':'step','conversacion':True,'mensajes':[],
               'actual':{'agente':'categorias_carta','recurso':'categorias_carta',
                         'instruccion':'Crear Bebidas de temporada','previo':'','contexto':'',
                         'aclaraciones':['Usa BT y cambia la limonada a 400 mL por S/12']},
               'pila':[{'agente':'presentaciones','recurso_objetivo':'presentaciones',
                        'instruccion':'Crear Limonada especial 500 mL a S/15','previo':'','contexto':''}]}
        plan={'recurso':'categorias_carta','accion':'crear','datos':{'nombre':'Bebidas de temporada','prefijo':'BT'}}
        communication.bind_plan(state,plan)
        with self.app.test_request_context(json={'modo':'conversacion'}), \
             patch.object(communication.drafts,'scope',return_value=scope), \
             patch.object(communication.drafts,'load',return_value={'estado':'REALIZADO','plan':plan,
                         'resultado':{'id_categoria_carta':42}}), \
             patch('app.multiagente.api.provider.respond',return_value=ANSWER) as model:
            communication.resume({},communication.serializer().dumps(state),'draft-id')
        history=json.loads(json.loads(model.call_args.args[0][1]['content'])['contexto_previo'])
        self.assertEqual(history['aclaraciones_requisitos'][0]['aclaraciones'],
                         ['Usa BT y cambia la limonada a 400 mL por S/12'])
        self.assertEqual(history['resultados_confirmados'][0]['resultado']['id_categoria_carta'],42)

    def test_full_specification_in_active_chat_keeps_original_task_and_corrections(self):
        from tests.test_presentation_advice import REQUEST
        state={'scope':{'usuario':1,'perfil':2,'local':1},'paso':'step','conversacion':True,
               'pila':[],'mensajes':[], 'actual':{'agente':'presentaciones','recurso_objetivo':'presentaciones',
               'instruccion':'Crear Limonada especial de 500 mL','previo':'','contexto':'Menaje elegido: Vaso',
               'aclaraciones':['El precio debe ser S/12']}}
        with patch('app.multiagente.api.provider.respond',return_value=ANSWER):
            response=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,
                json={'instruccion':REQUEST,'continuacion':communication.serializer().dumps(state)})
        self.assertEqual(response.status_code,200,response.json)
        updated=communication.serializer().loads(response.json['continuacion'])['actual']
        self.assertEqual(updated['instruccion'],'Crear Limonada especial de 500 mL')
        self.assertEqual(updated['aclaraciones'],['El precio debe ser S/12',REQUEST])
        self.assertIn('Vaso',updated['contexto'])

    def test_full_specification_cannot_bypass_continuation_scope_check(self):
        from tests.test_presentation_advice import ROWS,REQUEST
        state={'scope':{'usuario':99,'perfil':2,'local':1},'paso':'old','conversacion':False,
               'pila':[],'mensajes':[], 'actual':{'agente':'categorias_carta','instruccion':'Crear categoría',
                                               'previo':'','contexto':''}}
        with patch.object(routes.tools,'records',side_effect=lambda session,resource:ROWS[resource]):
            response=self.app.test_client().post('/api/asistente-ia/preparar',headers=self.headers,
                json={'instruccion':REQUEST,'continuacion':communication.serializer().dumps(state)})
        self.assertEqual(response.status_code,403,response.json)


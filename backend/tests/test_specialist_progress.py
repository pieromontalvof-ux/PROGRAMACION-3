import json
import unittest
from unittest.mock import patch
from flask import Flask
from app.multiagente.agents.catalog_specialists import SPECIALISTS


def call(name,args,identity='call'):
    return [{'type':'function_call','call_id':identity,'name':name,'arguments':json.dumps(args)}]


class SpecialistProgressTests(unittest.TestCase):
    def test_recipe_read_limit_synthesizes_existing_evidence_without_more_tools(self):
        outputs=[call('consultar',{'recurso':'recetas','busqueda':'Mojito','desde':i},str(i)) for i in range(7)]
        outputs.append([{'type':'message','content':[{'type':'output_text','text':'Mojito registrado. Que ingrediente quieres cambiar?'}]}])
        with patch('app.multiagente.api.provider.respond',side_effect=outputs) as model, \
             patch('app.multiagente.api.tools.query',return_value={'recurso':'recetas','registros':[{'item_carta':'Mojito','componentes':[]}]}):
            result=SPECIALISTS['recetas'].run({},'Revisa Mojito y evalua cambiar un ingrediente, sin guardar')
        self.assertEqual(model.call_count,8)
        self.assertEqual(model.call_args.args[1],[])
        self.assertIn('Mojito registrado',result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_recipe_repeated_reads_keep_recipe_when_final_generation_fails(self):
        from app.multiagente.api.provider import AssistantError
        lookup=call('consultar',{'recurso':'recetas','busqueda':'Mojito','desde':0})
        with patch('app.multiagente.api.provider.respond',side_effect=[lookup,lookup,lookup,AssistantError('offline')]), \
             patch('app.multiagente.api.tools.query',return_value={'recurso':'recetas','registros':[{'item_carta':'Mojito','componentes':[{'nombre_componente':'Limon','cantidad':.05,'unidad':'KGM'}]}]}):
            result=SPECIALISTS['recetas'].run({},'Revisa Mojito y alternativas sin guardar')
        self.assertIn('Mojito',result['respuesta'])
        self.assertIn('Limon',result['respuesta'])
        self.assertNotIn('limite de consultas',result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_native_product_analysis_is_rendered_without_another_model_round(self):
        from app.multiagente.agents.demanda.agent import run
        query={'recurso':'demanda_rotacion','contexto':{'desde':'2026-07-18','hasta':'2026-11-17',
            'analisis_productos':{'articulos':[],'insumos':[],'periodos':{},'nota':'Consumo compartido de toda la carta.'}}}
        with patch('app.multiagente.api.provider.respond',return_value=call('analizar_demanda',{'filtros_json':'{"desde":"2026-07-18","hasta":"2026-11-17"}'})) as model, \
             patch('app.multiagente.api.demand.read',return_value=query) as read:
            result=run({},'Los últimos cuatro meses')
        model.assert_called_once()
        self.assertTrue(read.call_args.args[1]['detalle_productos'])
        self.assertIn('Productos más vendidos: tendencia',result['respuesta'])
        self.assertIn('Insumos de estos productos',result['respuesta'])
        self.assertIsNone(result['plan'])

    def test_analysis_without_period_asks_before_reading_sales(self):
        for name in ('analizar_demanda_global','analizar_demanda'):
            with self.subTest(tool=name), \
                 patch('app.multiagente.api.provider.respond',return_value=call(name,{'filtros_json':'{}'})), \
                 patch('app.multiagente.api.global_demand.read') as global_read, \
                 patch('app.multiagente.api.demand.read') as local_read:
                result=SPECIALISTS['promociones'].run({},'Analiza lo más vendido para una promoción')
            global_read.assert_not_called()
            local_read.assert_not_called()
            self.assertIn('período',result['respuesta'])
            self.assertEqual(result['consultas'],[])
            self.assertIsNone(result['plan'])

    def test_analysis_with_period_reads_without_asking_again(self):
        outputs=[call('analizar_demanda_global',{'filtros_json':json.dumps({'desde':'2026-07-17','hasta':'2026-11-16'})}),
                 [{'type':'message','content':[{'type':'output_text','text':'Comparación de cuatro meses.'}]}]]
        with patch('app.multiagente.api.provider.respond',side_effect=outputs), \
             patch('app.multiagente.api.global_demand.read',return_value={'recurso':'demanda_global'}) as read:
            result=SPECIALISTS['promociones'].run({},'Revisa los últimos cuatro meses')
        read.assert_called_once_with({}, {'desde':'2026-07-17','hasta':'2026-11-16'})
        self.assertEqual(result['respuesta'],'Comparación de cuatro meses.')

    def test_global_promotion_closes_read_phase_with_tool_free_synthesis(self):
        outputs=[call('consultar',{'recurso':'recetas','busqueda':str(i),'desde':0},str(i)) for i in range(12)]
        outputs.append([{'type':'message','content':[{'type':'output_text','text':'Dos opciones para 21 días, con ventas de cuatro meses.'}]}])
        report={'recurso':'recetas','total':0,'registros':[]}
        with patch('app.multiagente.api.provider.respond',side_effect=outputs) as model, \
             patch('app.multiagente.api.tools.query',return_value=report):
            result=SPECIALISTS['promociones'].run({},'Empecemos con 3 semanas')
        self.assertEqual(model.call_count,13)
        self.assertEqual(model.call_args.args[1],[])
        self.assertEqual(len(result['consultas']),12)
        self.assertIsNone(result['plan'])
        self.assertIn('Dos opciones',result['respuesta'])
        self.assertEqual(sum(m.get('type')=='function_call_output' for m in model.call_args.args[0]),12)

    def setUp(self):
        self.ctx=Flask(__name__).test_request_context()
        self.ctx.push();self.addCleanup(self.ctx.pop)
        for target,kwargs in [
            ('app.multiagente.api.tools.allowed',{'return_value':True}),
            ('app.multiagente.api.configuration.saved',{'return_value':None}),
            ('app.multiagente.api.library.for_skills',{'return_value':''}),
            ('app.multiagente.agents.runtime.db.session.rollback',{}),
        ]:
            p=patch(target,**kwargs);p.start();self.addCleanup(p.stop)

    def test_repeated_lookup_stops_without_losing_the_consulted_results(self):
        lookup=call('consultar',{'recurso':'categorias_carta','busqueda':'Bebidas de temporada','desde':0})
        report={'recurso':'categorias_carta','total':0,'registros':[],'hay_mas':False}
        with patch('app.multiagente.api.provider.respond',return_value=lookup) as model, \
             patch('app.multiagente.api.tools.query',return_value=report) as query:
            result=SPECIALISTS['presentaciones'].run({},'Quiero crear una presentación de Limonada especial')
        self.assertLessEqual(model.call_count,3)
        query.assert_called_once()
        self.assertIsNone(result['plan'])
        self.assertEqual(result['consultas'],[report])
        self.assertIn('pendiente',result['respuesta'])
        self.assertTrue(result.get('opciones'))

    def test_lookup_of_two_requirements_then_handoff_is_preserved(self):
        outputs=[call('consultar',{'recurso':'categorias_carta','busqueda':'Bebidas de temporada','desde':0},'category'),
                 call('consultar',{'recurso':'menajes','busqueda':'','desde':0},'menaje'),
                 call('solicitar_especialista',{'recurso':'categorias_carta','instruccion':'Crear Bebidas de temporada','motivo':'La categoría no existe y el usuario desea crearla.'},'handoff')]
        with patch('app.multiagente.api.provider.respond',side_effect=outputs), \
             patch('app.multiagente.api.tools.query',side_effect=[{'recurso':'categorias_carta','total':0,'registros':[]},{'recurso':'menajes','total':1,'registros':[{'nombre':'Vaso'}]}]):
            result=SPECIALISTS['presentaciones'].run({},'Crear Limonada y crear primero la categoría que falta')
        self.assertEqual(result['traspaso']['recurso'],'categorias_carta')
        self.assertEqual(len(result['consultas']),2)

    def test_exhausted_unique_lookups_return_partial_answer_without_exhaustive_claim(self):
        outputs=[call('consultar',{'recurso':'menajes','busqueda':'','desde':i*30},str(i)) for i in range(7)]
        with patch('app.multiagente.api.provider.respond',side_effect=outputs), \
             patch('app.multiagente.api.tools.query',return_value={'recurso':'menajes','total':300,'registros':[],'hay_mas':True}):
            result=SPECIALISTS['presentaciones'].run({},'Consultar menajes')
        self.assertIsNone(result['plan'])
        self.assertIn('parcial',result['respuesta'])
        self.assertNotIn('opciones',result)

    def test_cached_lookup_can_recover_into_a_real_handoff(self):
        lookup=call('consultar',{'recurso':'categorias_carta','busqueda':'Bebidas de temporada','desde':0})
        delegation=call('solicitar_especialista',{'recurso':'categorias_carta','instruccion':'Crear Bebidas de temporada','motivo':'Falta la categoría solicitada.'},'delegate')
        with patch('app.multiagente.api.provider.respond',side_effect=[lookup,lookup,delegation]) as model, \
             patch('app.multiagente.api.tools.query',return_value={'recurso':'categorias_carta','total':0,'registros':[]}) as query:
            result=SPECIALISTS['presentaciones'].run({},'Crear presentación y crear primero la categoría')
        query.assert_called_once()
        self.assertEqual(result['traspaso']['recurso'],'categorias_carta')
        self.assertEqual(len(result['consultas']),1)
        output=next(m for m in reversed(model.call_args.args[0]) if m.get('type')=='function_call_output')
        self.assertIn('ya se realizó',json.loads(output['output'])['aviso'])

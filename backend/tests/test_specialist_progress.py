import json
import unittest
from unittest.mock import patch
from flask import Flask
from app.agents.catalog_specialists import SPECIALISTS


def call(name,args,identity='call'):
    return [{'type':'function_call','call_id':identity,'name':name,'arguments':json.dumps(args)}]


class SpecialistProgressTests(unittest.TestCase):
    def setUp(self):
        self.ctx=Flask(__name__).test_request_context()
        self.ctx.push();self.addCleanup(self.ctx.pop)
        for target,kwargs in [
            ('app.modules.asistente_ia.tools.allowed',{'return_value':True}),
            ('app.modules.asistente_ia.configuration.saved',{'return_value':None}),
            ('app.modules.asistente_ia.library.for_skills',{'return_value':''}),
            ('app.agents.runtime.db.session.rollback',{}),
        ]:
            p=patch(target,**kwargs);p.start();self.addCleanup(p.stop)

    def test_repeated_lookup_stops_without_losing_the_consulted_results(self):
        lookup=call('consultar',{'recurso':'categorias_carta','busqueda':'Bebidas de temporada','desde':0})
        report={'recurso':'categorias_carta','total':0,'registros':[],'hay_mas':False}
        with patch('app.modules.asistente_ia.provider.respond',return_value=lookup) as model, \
             patch('app.modules.asistente_ia.tools.query',return_value=report) as query:
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
        with patch('app.modules.asistente_ia.provider.respond',side_effect=outputs), \
             patch('app.modules.asistente_ia.tools.query',side_effect=[{'recurso':'categorias_carta','total':0,'registros':[]},{'recurso':'menajes','total':1,'registros':[{'nombre':'Vaso'}]}]):
            result=SPECIALISTS['presentaciones'].run({},'Crear Limonada y crear primero la categoría que falta')
        self.assertEqual(result['traspaso']['recurso'],'categorias_carta')
        self.assertEqual(len(result['consultas']),2)

    def test_exhausted_unique_lookups_return_partial_answer_without_exhaustive_claim(self):
        outputs=[call('consultar',{'recurso':'menajes','busqueda':'','desde':i*30},str(i)) for i in range(7)]
        with patch('app.modules.asistente_ia.provider.respond',side_effect=outputs), \
             patch('app.modules.asistente_ia.tools.query',return_value={'recurso':'menajes','total':300,'registros':[],'hay_mas':True}):
            result=SPECIALISTS['presentaciones'].run({},'Consultar menajes')
        self.assertIsNone(result['plan'])
        self.assertIn('parcial',result['respuesta'])
        self.assertNotIn('opciones',result)

    def test_cached_lookup_can_recover_into_a_real_handoff(self):
        lookup=call('consultar',{'recurso':'categorias_carta','busqueda':'Bebidas de temporada','desde':0})
        delegation=call('solicitar_especialista',{'recurso':'categorias_carta','instruccion':'Crear Bebidas de temporada','motivo':'Falta la categoría solicitada.'},'delegate')
        with patch('app.modules.asistente_ia.provider.respond',side_effect=[lookup,lookup,delegation]) as model, \
             patch('app.modules.asistente_ia.tools.query',return_value={'recurso':'categorias_carta','total':0,'registros':[]}) as query:
            result=SPECIALISTS['presentaciones'].run({},'Crear presentación y crear primero la categoría')
        query.assert_called_once()
        self.assertEqual(result['traspaso']['recurso'],'categorias_carta')
        self.assertEqual(len(result['consultas']),1)
        output=next(m for m in reversed(model.call_args.args[0]) if m.get('type')=='function_call_output')
        self.assertIn('ya se realizó',json.loads(output['output'])['aviso'])

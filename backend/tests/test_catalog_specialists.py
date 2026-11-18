import json
import unittest
from unittest.mock import patch

from app import create_app
from app.multiagente.agents.catalog_specialists import SPECIALISTS
from app.multiagente.agents.manifest import catalog
from app.multiagente.agents.orchestrator.router import run
from app.multiagente.api.provider import AssistantError


ANSWER = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Consulta lista.'}]}]


class CatalogSpecialistTests(unittest.TestCase):
    def setUp(self):
        self.app = create_app()

    def test_presentation_prompt_requires_complete_native_type_choices_even_with_saved_config(self):
        config={'accesos':{'presentaciones':['consultar','crear']},'skills':[],
                'instrucciones':'Pregunta solo DIRECTO o PREPARADO.'}
        with self.app.test_request_context(), \
             patch('app.multiagente.api.configuration.saved',return_value=config), \
             patch('app.multiagente.api.tools.allowed',return_value=True), \
             patch('app.multiagente.api.provider.respond',return_value=ANSWER) as model:
            SPECIALISTS['presentaciones'].run({'menu':[]},'Quiero usar la categoria existente')
        system=model.call_args.args[0][0]['content']
        self.assertIn('lista completa de tipos',system)
        self.assertIn('PORCIONADO',system)
        self.assertIn('abrir_formulario',system)

    def test_each_specialist_only_exposes_its_own_write_resource(self):
        for agent in SPECIALISTS.values():
            with self.subTest(agent=agent.identity), self.app.test_request_context(), \
                 patch('app.multiagente.api.tools.allowed', return_value=True), \
                 patch('app.multiagente.api.provider.respond', return_value=ANSWER) as model:
                agent.run({'menu': []}, 'Consulta')
                definitions = {t['name']: t for t in model.call_args.args[1]}
                self.assertEqual(definitions['preparar_cambio']['parameters']['properties']['recurso']['enum'], [agent.resource])
                catalog_reads = definitions['consultar']['parameters']['properties']['recurso']['enum']
                inventory_reads = definitions.get('consultar_inventario', {}).get('parameters', {}).get('properties', {}).get('recurso', {}).get('enum', [])
                self.assertEqual(set(catalog_reads + inventory_reads), set(agent.resources))
                self.assertNotIn('stock', catalog_reads)
                if agent.resource in ('categorias_carta', 'menajes', 'presentaciones'):
                    self.assertEqual(definitions['abrir_formulario']['parameters']['properties']['recurso']['enum'], [agent.resource])
                else:
                    self.assertNotIn('abrir_formulario', definitions)
                self.assertTrue(agent.skills[0].is_file())

    def test_dependency_write_is_rejected_before_prepare(self):
        call = {'type': 'function_call', 'call_id': 'foreign', 'name': 'preparar_cambio',
                'arguments': json.dumps({'recurso': 'productos', 'accion': 'crear', 'id': None,
                                         'datos_json': '{"nombre":"No permitido"}'})}
        with self.app.test_request_context(), \
             patch('app.multiagente.api.tools.allowed', return_value=True), \
             patch('app.multiagente.api.provider.respond', side_effect=[[call], ANSWER]), \
             patch('app.multiagente.api.tools.prepare') as prepare:
            result = SPECIALISTS['recetas'].run({'menu': []}, 'Crear receta')
        self.assertIsNone(result['plan'])
        prepare.assert_not_called()

    def test_unrelated_query_is_rejected_before_query(self):
        call = {'type': 'function_call', 'call_id': 'foreign', 'name': 'consultar',
                'arguments': json.dumps({'recurso': 'usuarios', 'busqueda': '', 'desde': 0})}
        with self.app.test_request_context(), \
             patch('app.multiagente.api.tools.allowed', return_value=True), \
             patch('app.multiagente.api.provider.respond', side_effect=[[call], ANSWER]), \
             patch('app.multiagente.api.tools.query') as query:
            SPECIALISTS['menajes'].run({'menu': []}, 'Consulta menajes')
        query.assert_not_called()

    def test_dependency_read_permission_does_not_grant_access_to_agent(self):
        with patch('app.multiagente.api.tools.allowed', side_effect=lambda s, r: r == 'productos'), \
             self.assertRaises(AssistantError):
            run({'menu': []}, 'Crear receta')

    def test_read_only_session_has_no_write_tool(self):
        with self.app.test_request_context(), \
             patch('app.multiagente.api.tools.allowed', side_effect=lambda s, r, a='consultar': a == 'consultar'), \
             patch('app.multiagente.api.provider.respond', return_value=ANSWER) as model:
            SPECIALISTS['recetas'].run({'menu': []}, 'Consulta recetas')
        self.assertNotIn('preparar_cambio', [t['name'] for t in model.call_args.args[1]])

    def test_inspector_lists_five_independent_agents_and_skills(self):
        agents = {a['id']: a for a in catalog()['agentes']}
        for identity, specialist in SPECIALISTS.items():
            self.assertEqual(agents[identity]['recursos_modificables'], [specialist.resource])
            self.assertEqual(len(agents[identity]['skills']), 1)
        self.assertTrue(set(SPECIALISTS).isdisjoint(agents['carta_recetas']['recursos']))

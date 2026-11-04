import io
from unittest.mock import patch
import unittest
import test_agent_library
from app.modules.asistente_ia import configuration, library


REPORT = {'resumen': 'Sin bloqueos.', 'informacion_faltante': [],
          'accesos_necesarios': [], 'recomendaciones': ['Consultar Compras'], 'conflictos': []}


class AgentConfigurationTests(unittest.TestCase):
    setUp = test_agent_library.AgentLibraryTests.setUp
    token = test_agent_library.AgentLibraryTests.token
    def config(self, agent='compras'):
        return self.client.get('/api/asistente-ia/biblioteca/' + agent, headers=self.headers).json['configuracion']

    def review(self, config, revision=0, agent='compras'):
        with patch('app.agents.configuracion.agent.review', return_value=REPORT):
            return self.client.post(f'/api/asistente-ia/biblioteca/{agent}/skills/validar', headers=self.headers,
                                    json={'skills': config['skills'], 'revision': revision})

    def test_current_instructions_and_skills_are_loaded_instead_of_blank(self):
        config = self.config()
        self.assertIn('compras', config['instrucciones'])
        self.assertTrue(config['skills'][0]['contenido'])
        self.assertIn('ordenes_compra', config['accesos'])

    def test_review_does_not_apply_and_apply_updates_effective_configuration(self):
        config = self.config()
        original = config['instrucciones']
        config['instrucciones'] = 'Usar plazos confirmados.'
        config['skills'][0]['contenido'] = 'Preguntar por los días de entrega.'
        response = self.review(config)
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(self.config()['instrucciones'], original)
        saved = self.client.post('/api/asistente-ia/biblioteca/compras/skills/guardar', headers=self.headers,
                                json={'skills': config['skills'], 'revision': 0, 'revision_ia': response.json['revision_ia']})
        self.assertEqual(saved.status_code, 200, saved.json)
        self.assertEqual(self.config()['instrucciones'], original)
        self.assertEqual(self.config()['skills'][0]['contenido'], 'Preguntar por los días de entrega.')

    def test_unreviewed_or_modified_configuration_cannot_be_applied(self):
        config = self.config()
        review = self.review(config).json
        config['skills'][0]['contenido'] += ' Modificado después.'
        response = self.client.post('/api/asistente-ia/biblioteca/compras/skills/guardar', headers=self.headers,
                                   json={'skills': config['skills'], 'revision': 0, 'revision_ia': review['revision_ia']})
        self.assertEqual(response.status_code, 409)

    def test_unsupported_resource_cannot_be_granted(self):
        config = self.config()
        config['accesos']['usuarios'] = ['editar']
        response = self.client.put('/api/asistente-ia/biblioteca/compras/accesos', headers=self.headers, json={'accesos': config['accesos'], 'revision': 0})
        self.assertEqual(response.status_code, 400)

    def test_new_document_is_pending_until_its_snapshot_is_reviewed_and_applied(self):
        path = '/api/asistente-ia/biblioteca/compras'
        uploaded = self.client.post(path + '/documentos', headers=self.headers,
                                    data={'archivo': (io.BytesIO(b'Entrega viernes.'), 'entregas.txt'), 'revision': '0'})
        self.assertEqual(uploaded.status_code, 201)
        self.assertNotIn('Entrega viernes.', library.context('compras'))
        config = self.config()
        review = self.review(config, 1).json
        saved = self.client.post(path + '/skills/guardar', headers=self.headers, json={'skills': config['skills'], 'revision': 1, 'revision_ia': review['revision_ia']})
        self.assertEqual(saved.status_code, 200, saved.json)
        self.assertIn('Entrega viernes.', library.context('compras'))

    def test_changed_documents_invalidate_old_review(self):
        config = self.config()
        review = self.review(config).json
        self.client.post('/api/asistente-ia/biblioteca/compras/documentos', headers=self.headers,
                         data={'archivo': (io.BytesIO(b'Nuevo texto'), 'nuevo.md'), 'revision': '0'})
        response = self.client.post('/api/asistente-ia/biblioteca/compras/skills/guardar', headers=self.headers,
                                   json={'skills': config['skills'], 'revision': 0, 'revision_ia': review['revision_ia']})
        self.assertEqual(response.status_code, 409)

    def publish(self, config, agent='compras'):
        permissions = self.client.put(f'/api/asistente-ia/biblioteca/{agent}/accesos', headers=self.headers, json={'accesos': config['accesos'], 'revision': 0})
        self.assertEqual(permissions.status_code, 200, permissions.json)
        reviewed = self.review(config, revision=1, agent=agent)
        self.assertEqual(reviewed.status_code, 200, reviewed.json)
        applied = self.client.post(f'/api/asistente-ia/biblioteca/{agent}/skills/guardar', headers=self.headers,
                                  json={'skills': config['skills'], 'revision': 1, 'revision_ia': reviewed.json['revision_ia']})
        self.assertEqual(applied.status_code, 200, applied.json)

    def test_disabled_owner_access_blocks_all_form_paths_and_direct_drafts(self):
        from app.modules.asistente_ia import tools
        config = self.config('carta_recetas')
        config['accesos']['productos'] = []
        self.publish(config, 'carta_recetas')
        with patch.object(tools, 'allowed', return_value=True), patch.object(tools, 'native') as native:
            for route, data in (('preparar', {'instruccion': 'Crear producto'}),
                                ('formulario', {'recurso': 'productos'}),
                                ('formulario/preparar', {'recurso': 'productos', 'datos': {}})):
                result = self.client.post('/api/asistente-ia/' + route, headers=self.headers, json=data)
                self.assertEqual(result.status_code, 403, result.json)
            from app.modules.asistente_ia.provider import AssistantError
            with self.assertRaises(AssistantError):
                tools.prepare({}, 'productos', 'crear', None, {})
            with self.assertRaises(AssistantError):
                tools.execute({}, {'recurso': 'productos', 'accion': 'crear', 'id': None, 'datos': {}})
            native.assert_not_called()

    def test_effective_prompts_and_selected_accesses_reach_runtime_and_map(self):
        from app.agents.compras.agent import SKILLS, RESOURCES, INSTRUCTIONS
        from app.agents.runtime import run_specialist
        from app.modules.asistente_ia import tools
        config = self.config()
        original_instruction = config['instrucciones']
        config['instrucciones'] = 'Consultar plazos vigentes.'
        config['skills'][0]['contenido'] = 'Pedir horizonte de reposición.'
        config['accesos']['ordenes_compra'] = ['consultar']
        self.publish(config)
        answer = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Consulta.'}]}]
        with patch.object(tools, 'allowed', return_value=True), patch('app.modules.asistente_ia.provider.respond', return_value=answer) as model:
            run_specialist({'local_activo': None}, 'Consultar', '', '', RESOURCES, INSTRUCTIONS, SKILLS, writable_resources=('ordenes_compra',))
        self.assertIn(original_instruction.strip(), model.call_args.args[0][0]['content'])
        self.assertIn('Pedir horizonte de reposición.', model.call_args.args[0][0]['content'])
        self.assertNotIn('preparar_cambio', [tool['name'] for tool in model.call_args.args[1]])
        response = self.client.get('/api/asistente-ia/agentes', headers=self.headers)
        agent = next(item for item in response.json['agentes'] if item['id'] == 'compras')
        self.assertEqual(agent['instrucciones'].strip(), original_instruction.strip())
        self.assertEqual(agent['skills'][0]['contenido'], 'Pedir horizonte de reposición.')

    def test_reviewer_invalid_output_cannot_authorize_a_change(self):
        answer = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'No es JSON.'}]}]
        with patch('app.modules.asistente_ia.provider.respond', return_value=answer) as model:
            response = self.client.post('/api/asistente-ia/biblioteca/compras/skills/validar', headers=self.headers,
                                        json={'skills': self.config()['skills'], 'revision': 0})
        self.assertEqual(response.status_code, 502)
        self.assertEqual(model.call_args.args[1], [])
        self.assertEqual(library.read('compras')['revision'], 0)

    def test_review_from_another_local_cannot_be_used(self):
        from flask_jwt_extended import create_access_token
        config = self.config()
        result = self.review(config).json
        headers = {'Authorization': 'Bearer ' + create_access_token(identity='1', additional_claims={
            'tipo_token': 'operativo', 'id_perfil': 1, 'id_local': 2})}
        response = self.client.post('/api/asistente-ia/biblioteca/compras/skills/guardar', headers=headers,
                                   json={'skills': config['skills'], 'revision': 0, 'revision_ia': result['revision_ia']})
        self.assertEqual(response.status_code, 403)

    def test_reviewer_refuses_oversized_complete_input_without_calling_model(self):
        from werkzeug.datastructures import FileStorage
        library.upload('compras', FileStorage(stream=io.BytesIO(b'a' * 120001), filename='grande.txt'), 0)
        with patch('app.agents.configuracion.agent.review') as model:
            response = self.client.post('/api/asistente-ia/biblioteca/compras/skills/validar', headers=self.headers,
                                        json={'skills': self.config()['skills'], 'revision': 1})
        self.assertEqual(response.status_code, 413)
        model.assert_not_called()

    def test_disabled_dependency_catalogs_are_not_exposed_by_aggregate_forms(self):
        from app.modules.asistente_ia import tools
        config = self.config('carta_recetas')
        config['accesos']['proveedores'] = []
        self.publish(config, 'carta_recetas')
        with patch.object(tools, 'allowed', return_value=True), patch.object(tools, 'native') as native:
            response = self.client.post('/api/asistente-ia/formulario', headers=self.headers, json={'recurso': 'productos'})
            self.assertEqual(response.status_code, 403, response.json)
            native.assert_not_called()

    def test_recipe_form_tool_cannot_expose_disabled_product_catalog(self):
        from app.agents.catalog_specialists import SPECIALISTS
        from app.agents.runtime import run_specialist
        from app.modules.asistente_ia import tools
        import json
        config = self.config('recetas')
        config['accesos']['productos'] = []
        self.publish(config, 'recetas')
        specialist = SPECIALISTS['recetas']
        forged = [{'type': 'function_call', 'call_id': 'form', 'name': 'formulario', 'arguments': json.dumps({'recurso': 'recetas'})}]
        answer = [{'type': 'message', 'content': [{'type': 'output_text', 'text': 'Falta acceso.'}]}]
        with patch.object(tools, 'allowed', return_value=True), patch.object(tools, 'native') as native, patch('app.modules.asistente_ia.provider.respond', side_effect=[forged, answer]):
            run_specialist({'local_activo': None}, 'Crear receta', '', '', specialist.resources,
                           specialist.instructions, specialist.skills, writable_resources=('recetas',))
            native.assert_not_called()

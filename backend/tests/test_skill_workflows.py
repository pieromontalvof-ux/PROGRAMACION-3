import base64
import io
import unittest
from unittest.mock import patch
import test_agent_library
from app.multiagente.api import library, configuration

OK = {'resumen': 'Sin problemas.', 'informacion_faltante': [], 'accesos_necesarios': [], 'recomendaciones': [], 'conflictos': []}
BLOCKED = {**OK, 'accesos_necesarios': ['Consultar stock para calcular cobertura.']}
PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aF1cAAAAASUVORK5CYII=')


class SkillWorkflowTests(unittest.TestCase):
    setUp = test_agent_library.AgentLibraryTests.setUp
    token = test_agent_library.AgentLibraryTests.token

    def folder(self):
        return self.client.get('/api/asistente-ia/biblioteca/compras', headers=self.headers).json

    def test_skill_validation_save_preserves_permissions_and_instructions(self):
        before = self.folder()['configuracion']
        skills = [{**skill, 'contenido': 'Consultar plazos reales antes de proponer reposición.'} for skill in before['skills']]
        with patch('app.multiagente.agents.configuracion.agent.review', return_value=OK):
            checked = self.client.post('/api/asistente-ia/biblioteca/compras/skills/validar', headers=self.headers, json={'skills': skills, 'revision': 0})
        self.assertEqual(checked.status_code, 200, checked.json)
        self.assertTrue(checked.json['puede_guardar'])
        response = self.client.post('/api/asistente-ia/biblioteca/compras/skills/guardar', headers=self.headers,
                                    json={'skills': skills, 'revision': 0, 'revision_ia': checked.json['revision_ia']})
        self.assertEqual(response.status_code, 200, response.json)
        after = self.folder()['configuracion']
        self.assertEqual(after['instrucciones'], before['instrucciones'])
        self.assertEqual(after['accesos'], before['accesos'])
        self.assertEqual(after['skills'][0]['contenido'], skills[0]['contenido'])

    def test_missing_permission_blocks_save_instead_of_granting_it(self):
        config = self.folder()['configuracion']
        with patch('app.multiagente.agents.configuracion.agent.review', return_value=BLOCKED):
            checked = self.client.post('/api/asistente-ia/biblioteca/compras/skills/validar', headers=self.headers, json={'skills': config['skills'], 'revision': 0})
        self.assertFalse(checked.json['puede_guardar'])
        response = self.client.post('/api/asistente-ia/biblioteca/compras/skills/guardar', headers=self.headers,
                                    json={'skills': config['skills'], 'revision': 0, 'revision_ia': checked.json['revision_ia']})
        self.assertEqual(response.status_code, 409)
        self.assertEqual(library.read('compras')['revision'], 0)

    def test_image_upload_original_preview_is_authenticated(self):
        response = self.client.post('/api/asistente-ia/biblioteca/compras/documentos', headers=self.headers,
                                    data={'archivo': (io.BytesIO(PNG), 'referencia.png'), 'revision': '0'})
        self.assertEqual(response.status_code, 201, response.json)
        row = response.json['documentos'][0]
        self.assertNotIn('original_b64', row)
        path = '/api/asistente-ia/biblioteca/compras/documentos/' + row['id'] + '/original'
        original = self.client.get(path, headers=self.headers)
        self.assertEqual(original.data, PNG)
        self.assertEqual(original.mimetype, 'image/png')
        self.assertEqual(self.client.get(path, headers=self.token(3)).status_code, 403)

    def test_file_updater_only_returns_skill_proposal_and_does_not_save(self):
        from werkzeug.datastructures import FileStorage
        library.upload('compras', FileStorage(stream=io.BytesIO(b'Entrega los jueves.'), filename='entregas.txt'), 0)
        folder = self.folder()
        with patch('app.multiagente.agents.actualizador_skills.agent.update', return_value={'contenido': 'Verificar entrega los jueves.', 'resumen': 'Añadido día de entrega.', 'informacion_faltante': []}):
            result = self.client.post('/api/asistente-ia/biblioteca/compras/skills/actualizar', headers=self.headers,
                                      json={'skills': folder['configuracion']['skills'], 'archivo_skill': folder['configuracion']['skills'][0]['archivo'],
                                            'documentos': [folder['documentos'][0]['id']], 'revision': 1})
        self.assertEqual(result.status_code, 200, result.json)
        self.assertEqual(result.json['contenido'], 'Verificar entrega los jueves.')
        self.assertNotIn('accesos', result.json)
        self.assertNotEqual(self.folder()['configuracion']['skills'][0]['contenido'], result.json['contenido'])

    def test_permissions_are_saved_by_the_separate_endpoint_without_updating_skills(self):
        before = self.folder()['configuracion']
        accesses = {**before['accesos'], 'ordenes_compra': ['consultar']}
        response = self.client.put('/api/asistente-ia/biblioteca/compras/accesos', headers=self.headers, json={'accesos': accesses, 'revision': 0})
        self.assertEqual(response.status_code, 200, response.json)
        after = response.json['configuracion']
        self.assertEqual(after['skills'], before['skills'])
        self.assertEqual(after['instrucciones'], before['instrucciones'])
        self.assertEqual(after['accesos']['ordenes_compra'], ['consultar'])

    def test_legacy_combined_mutations_cannot_bypass_blocking_validation(self):
        for method, path in (('POST', '/revisar'), ('PUT', '')):
            response = self.client.open('/api/asistente-ia/biblioteca/compras' + path, method=method, headers=self.headers,
                                        json={'configuracion': self.folder()['configuracion'], 'revision': 0})
            self.assertEqual(response.status_code, 410)
        self.assertEqual(library.read('compras')['revision'], 0)

    def test_originals_are_attached_as_media_not_base64_text_for_both_agents(self):
        from werkzeug.datastructures import FileStorage
        from app.multiagente.agents.document_inputs import messages
        library.upload('compras', FileStorage(stream=io.BytesIO(PNG), filename='foto.png'), 0)
        library.upload('compras', FileStorage(stream=io.BytesIO(b'%PDF-1.4\n%%EOF'), filename='manual.pdf'), 1)
        payload = messages('Reglas protegidas.', {'documentos': library.read('compras')['documentos']})
        parts = payload[1]['content']
        self.assertTrue(any(part['type'] == 'input_image' and part['image_url'].startswith('data:image/png;base64,') for part in parts))
        self.assertTrue(any(part['type'] == 'input_file' and part['file_data'].startswith('data:application/pdf;base64,') for part in parts))
        self.assertNotIn('original_b64', parts[0]['text'])

    def test_mislabelled_image_is_rejected_and_original_is_not_exposed_in_metadata(self):
        response = self.client.post('/api/asistente-ia/biblioteca/compras/documentos', headers=self.headers,
                                    data={'archivo': (io.BytesIO(b'<script>bad</script>'), 'fake.png'), 'revision': '0'})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(library.read('compras')['documentos'], [])

    def test_new_skill_routes_and_permission_edits_are_admin_only(self):
        for suffix in ('skills/actualizar', 'skills/validar', 'skills/guardar'):
            response = self.client.post('/api/asistente-ia/biblioteca/compras/' + suffix, headers=self.token(3), json={})
            self.assertEqual(response.status_code, 403)
        self.assertEqual(self.client.put('/api/asistente-ia/biblioteca/compras/accesos', headers=self.token(3), json={}).status_code, 403)

    def test_updater_cannot_return_permissions_or_write_configuration(self):
        from app.multiagente.agents.actualizador_skills.agent import update
        from app.multiagente.api.provider import AssistantError
        import json
        response = [{'type': 'message', 'content': [{'type': 'output_text', 'text': json.dumps({'contenido': 'Cambiar', 'resumen': 'Cambios', 'informacion_faltante': [], 'accesos': {'usuarios': ['editar']}})}]}]
        with patch('app.multiagente.api.provider.respond', return_value=response), self.assertRaises(AssistantError):
            update({'documentos': []})
        self.assertEqual(library.read('compras')['revision'], 0)

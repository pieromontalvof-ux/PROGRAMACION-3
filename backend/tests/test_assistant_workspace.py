"""Workspace API regressions using real SQLite transactions, JWT and storage."""
import unittest
import tempfile
from unittest.mock import patch

from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
from sqlalchemy import text

from app.core.extensions import db
from app.modules.asistente_ia import routes
from app.agents.orchestrator import communication


DRAFT = '73f497ae-c692-4e14-a89f-7db565cad044'
PLAN = {'recurso': 'menajes', 'accion': 'crear', 'id': None,
        'datos': {'nombre': 'Servidor'}, 'anterior': None}


class AssistantWorkspaceTests(unittest.TestCase):
    def test_supervisor_preparation_query_reads_recipes_without_model(self):
        from test_recipe_answers import recipe
        headers = self.token(profile=3)
        with patch.object(routes.tools, 'authorize'), patch.object(routes.tools, 'records', return_value=[recipe()]), \
                patch('app.modules.asistente_ia.provider.respond') as model:
            response = self.client.post('/api/asistente-ia/preparar', headers=headers,
                                        json={'instruccion': 'quiero saber como se prepra una hamburguesa'})
        self.assertEqual(response.status_code, 200, response.json)
        self.assertEqual(response.json['agente'], 'recetas')
        self.assertIn('Usar la preparación registrada.', response.json['respuesta'])
        self.assertIsNone(response.json['borrador'])
        model.assert_not_called()

    def test_purchase_flow_survives_workspace_restore_and_resumes_to_margin(self):
        from app.agents.orchestrator import purchase_flow
        with patch.object(purchase_flow.tools, 'authorize'), patch.object(purchase_flow.event_agent, 'run', return_value={
                'respuesta': 'Eventos cercanos verificados', 'consultas': [], 'plan': None}):
            started = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                                       json={'instruccion': 'Quiero hacer un pedido'})
            self.assertEqual(started.status_code, 200, started.json)
            result = started.json
            self.assertIn('flujo_compra', result)
            saved = self.put(self.snapshot(result=result))
            self.assertEqual(saved.status_code, 200, saved.json)
            restored = self.get()
            self.assertEqual(restored.status_code, 200, restored.json)
            token = restored.json['workspace']['result']['flujo_compra']
            response = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                                        json={'instruccion': 'Continuar con el pedido', 'flujo_compra': token})
            self.assertEqual(response.status_code, 200, response.json)
            self.assertIn('porcentaje', response.json['respuesta'])
            self.assertIsNone(response.json['borrador'])

    def setUp(self):
        self.app = Flask(__name__)
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.app.config['APP_DATA_DIR'] = temporary.name
        self.app.config.update(SQLALCHEMY_DATABASE_URI='sqlite://',
                               JWT_SECRET_KEY='workspace-test-secret-key-at-least-32',
                               SECRET_KEY='workspace-signing-test-secret')
        db.init_app(self.app)
        JWTManager(self.app)
        self.app.register_blueprint(routes.asistente_ia_bp, url_prefix='/api/asistente-ia')
        self.ctx = self.app.app_context()
        self.ctx.push()
        self.addCleanup(self.ctx.pop)
        self.addCleanup(db.session.remove)
        db.session.execute(text('''CREATE TABLE asistente_ia_workspace (
            id_usuario INTEGER NOT NULL, id_perfil INTEGER NOT NULL, id_local INTEGER NOT NULL,
            snapshot JSON, revision BIGINT NOT NULL DEFAULT 0,
            actualizado_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            vence_en TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id_usuario, id_perfil, id_local))'''))
        db.session.commit()
        auth = patch.object(routes, 'obtener_sesion_actual', return_value=({'menu': []}, 200))
        auth.start()
        self.addCleanup(auth.stop)
        self.client = self.app.test_client()
        self.headers = self.token()
        routes._attempts.clear()
        routes._workspace_attempts.clear()

    def token(self, user=1, profile=1, local=1):
        return {'Authorization': 'Bearer ' + create_access_token(identity=str(user), additional_claims={
            'tipo_token': 'operativo', 'id_perfil': profile, 'id_local': local})}

    def get(self, headers=None):
        return self.client.get('/api/asistente-ia/workspace', headers=headers or self.headers)

    def put(self, workspace, revision=0, headers=None):
        return self.client.put('/api/asistente-ia/workspace', headers=headers or self.headers,
                               json={'workspace': workspace, 'revision': revision})

    def snapshot(self, **extra):
        return {'version': 1, 'instruction': 'Crear menaje', **extra}

    def row(self, state='PENDIENTE', **extra):
        return {'id': DRAFT, 'estado': state, 'vigente': True, 'plan': PLAN,
                'resultado': {'mensaje': 'Creado', 'id_menaje': 7}, **extra}

    def test_empty_workspace_and_authenticated_scope_isolation(self):
        self.assertEqual(self.get().status_code, 200)
        self.assertEqual(self.get().json, {'workspace': None, 'revision': 0})
        self.assertEqual(self.put(self.snapshot()).status_code, 200)
        for headers in (self.token(user=2), self.token(profile=2), self.token(local=2)):
            self.assertEqual(self.get(headers).json, {'workspace': None, 'revision': 0})
        self.assertEqual(self.get().json['workspace']['instruction'], 'Crear menaje')
        self.assertEqual(self.client.get('/api/asistente-ia/workspace').status_code, 401)

    def test_revision_conflicts_and_clear_tombstone_prevent_late_save(self):
        self.assertEqual(self.put(self.snapshot()).json['revision'], 1)
        conflict = self.put(self.snapshot(instruction='Viejo'))
        self.assertEqual(conflict.status_code, 409)
        self.assertEqual(conflict.json['revision'], 1)
        self.assertEqual(self.put(None, 1).json, {'workspace': None, 'revision': 2})
        self.assertEqual(self.put(self.snapshot(), 1).status_code, 409)
        self.assertEqual(self.get().json, {'workspace': None, 'revision': 2})

    def test_expiration_clears_snapshot_and_advances_revision(self):
        self.put(self.snapshot())
        db.session.execute(text("UPDATE asistente_ia_workspace SET vence_en=datetime('now','-1 second')"))
        db.session.commit()
        response = self.get()
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(response.json['workspace'])
        self.assertEqual(response.json['revision'], 2)
        self.assertIn('venci', response.json['mensaje'])
        self.assertEqual(self.put(self.snapshot(), 1).status_code, 409)

    def test_rejects_malformed_versions_fields_types_and_oversized_snapshots(self):
        for snapshot in ([], {'version': 2}, {'version': 1, 'instruction': 4},
                         self.snapshot(checked=True), self.snapshot(token='secret'),
                         self.snapshot(workflow={'frames': []}),
                         self.snapshot(instruction='x' * 8001)):
            with self.subTest(snapshot=str(snapshot)[:80]):
                self.assertEqual(self.put(snapshot).status_code, 400)
        self.assertEqual(self.put(self.snapshot(), True).status_code, 400)
        large = self.snapshot(context='x' * 210000)
        self.assertEqual(self.put(large).status_code, 413)
        self.assertEqual(self.get().json['revision'], 0)

    def test_signed_continuation_cannot_be_forged_or_shared_with_another_scope(self):
        self.assertEqual(self.put(self.snapshot(continuation='forged')).status_code, 409)
        token = communication.serializer().dumps({'scope': {'usuario': 1, 'perfil': 1, 'local': 1},
                                                  'pila': [], 'actual': {}, 'paso': 'step'})
        self.assertEqual(self.put(self.snapshot(continuation=token)).status_code, 200)
        self.assertEqual(self.put(self.snapshot(continuation=token), headers=self.token(local=2)).status_code, 403)

    def test_expired_signed_continuation_is_cleared_without_replaying_creation(self):
        token = communication.serializer().dumps({'scope': {'usuario': 1, 'perfil': 1, 'local': 1},
                                                  'pila': [], 'actual': {}, 'paso': 'step'})
        self.assertEqual(self.put(self.snapshot(continuation=token)).status_code, 200)
        with patch('itsdangerous.timed.time.time', return_value=9999999999), \
             patch.object(routes.tools, 'execute') as execute:
            restored = self.get()
        self.assertEqual(restored.status_code, 200)
        self.assertIsNone(restored.json['workspace'])
        self.assertEqual(restored.json['revision'], 2)
        self.assertIn('venci', restored.json['mensaje'])
        execute.assert_not_called()

    def test_storage_requests_have_separate_quota_and_are_eventually_rate_limited(self):
        for _ in range(9):
            self.assertEqual(self.get().status_code, 200)
        self.assertEqual(routes._attempts, {})
        responses = [self.get().status_code for _ in range(120)]
        self.assertIn(429, responses)
        self.assertEqual(self.get(self.token(local=2)).status_code, 200)

    def test_draft_plan_and_view_are_restored_from_server_not_snapshot(self):
        forged = {'id_borrador': DRAFT, 'datos': {'nombre': 'Forjado'}, 'vista': {'nombre': 'Forjado'},
                  'recurso': 'usuarios', 'accion': 'crear'}
        with patch.object(routes.drafts, 'load', return_value=self.row()), \
             patch.object(routes.tools, 'authorize'), patch.object(routes.tools, 'execute') as execute:
            saved = self.put(self.snapshot(result={'respuesta': 'Revisar', 'consultas': [], 'borrador': forged}))
            self.assertEqual(saved.status_code, 200, saved.json)
            restored = self.get().json
        draft = restored['workspace']['result']['borrador']
        self.assertEqual(draft['recurso'], 'menajes')
        self.assertEqual(draft['datos'], {'nombre': 'Servidor'})
        self.assertEqual(draft['vista'], {'nombre': 'Servidor'})
        self.assertEqual(restored['draft_state']['estado'], 'PENDIENTE')
        stored = db.session.execute(text('SELECT snapshot FROM asistente_ia_workspace')).scalar()
        self.assertNotIn('Forjado', stored)
        execute.assert_not_called()

    def test_realizado_and_unknown_outcomes_never_restore_an_executable_proposal(self):
        for state in ('REALIZADO', 'EJECUTANDO', 'FALLIDO', 'CANCELADO'):
            with self.subTest(state=state), patch.object(routes.drafts, 'load', return_value=self.row(state)), \
                 patch.object(routes.tools, 'authorize'), patch.object(routes.tools, 'execute') as execute:
                revision = self.get().json['revision']
                self.assertEqual(self.put(self.snapshot(draftId=DRAFT, result={
                    'respuesta': 'Revisar', 'consultas': [], 'borrador': {'id_borrador': DRAFT}}), revision).status_code, 200)
                restored = self.get().json
                self.assertIsNone(restored['workspace']['result']['borrador'])
                self.assertEqual(restored['workspace']['confirmed'], state == 'REALIZADO')
                self.assertEqual(restored['draft_state']['estado'], state)
                execute.assert_not_called()

    def test_completed_requirement_only_restores_matching_signed_return(self):
        task = {'scope': {'usuario': 1, 'perfil': 1, 'local': 1}, 'paso': 'bound-step',
                'pila': [{'agente': 'recetas'}], 'actual': {'recurso': 'menajes'}}
        token = communication.serializer().dumps(task)
        for bound_step in ('bound-step', 'another-step'):
            with self.subTest(bound_step=bound_step), \
                 patch.object(routes.drafts, 'load', return_value=self.row('REALIZADO',
                     plan={**PLAN, '_coordinacion': bound_step})), \
                 patch.object(routes.tools, 'authorize'), patch.object(routes.tools, 'execute') as execute:
                revision = self.get().json['revision']
                response = self.put(self.snapshot(draftId=DRAFT, continuation=token), revision)
                self.assertEqual(response.status_code, 200, response.json)
                recovered = self.get().json['workspace']
                self.assertEqual(recovered['resumeDraft'], DRAFT if bound_step == 'bound-step' else None)
                self.assertTrue(recovered['confirmed'])
                execute.assert_not_called()

    def test_nested_forms_refresh_options_and_verify_saved_creation(self):
        workflow = {'frames': [{'form': {'recurso': 'productos', 'categorias': ['forged']},
                                'values': {'nombre': 'Conservado', 'categoria': '4'}, 'version': 1},
                               {'form': {'recurso': 'menajes'}, 'values': {'nombre': 'Plato'}, 'version': 0}],
                    'proposal': None, 'saved': {'id_menaje': 999, 'mensaje': 'Forjado'},
                    'draftId': DRAFT, 'dirty': False}
        with patch.object(routes.drafts, 'load', return_value=self.row('REALIZADO')), \
             patch.object(routes.tools, 'authorize'), \
             patch.object(routes.forms, 'open_form', side_effect=lambda s, r: {'recurso': r, 'categorias': ['fresh']}):
            self.assertEqual(self.put(self.snapshot(workflow=workflow)).status_code, 200)
            restored = self.get().json['workspace']['workflow']
        self.assertEqual(restored['frames'][0]['form']['categorias'], ['fresh'])
        self.assertEqual(restored['frames'][0]['values']['nombre'], 'Conservado')
        self.assertEqual(restored['saved']['id_menaje'], 7)
        self.assertEqual(restored['draft_state']['estado'], 'REALIZADO')

    def test_nested_proposal_is_scoped_and_expired_pending_draft_is_not_executable(self):
        workflow = {'frames': [{'form': {'recurso': 'menajes'}, 'values': {}, 'version': 0}],
                    'proposal': {'respuesta': 'Revisar', 'borrador': {'id_borrador': DRAFT}, 'consultas': []}}
        with patch.object(routes.drafts, 'load', return_value=self.row(vigente=False)), \
             patch.object(routes.tools, 'authorize'), \
             patch.object(routes.forms, 'open_form', return_value={'recurso': 'menajes'}):
            self.assertEqual(self.put(self.snapshot(workflow=workflow)).status_code, 200)
            restored = self.get().json['workspace']['workflow']
        self.assertIsNone(restored['proposal']['borrador'])
        self.assertFalse(restored['draft_state']['vigente'])

    def test_all_draft_references_are_scoped_even_when_another_draft_is_present(self):
        from app.modules.asistente_ia.provider import AssistantError
        foreign_id = '2bb5fc9e-fb80-41de-b651-e2091f1f6bd2'
        def lookup(draft_id):
            if draft_id == foreign_id:
                raise AssistantError('No pertenece a esta sesión.', 404)
            return self.row()
        with patch.object(routes.drafts, 'load', side_effect=lookup), \
             patch.object(routes.tools, 'authorize'):
            response = self.put(self.snapshot(draftId=foreign_id, result={
                'respuesta': 'Revisar', 'consultas': [], 'borrador': {'id_borrador': DRAFT}}))
        self.assertEqual(response.status_code, 404)
        self.assertEqual(self.get().json['revision'], 0)


    def test_activity_export_is_authoritative_scoped_and_recovers_with_workspace(self):
        from app.agents import activity
        @activity.agent('demanda')
        def real_execution(session, instruction, previous='', context=''):
            @activity.tool('analizar_demanda')
            def read():
                return {'total': 2, 'registros': []}
            read()
            return {'respuesta': 'Dos registros consultados.', 'consultas': [], 'plan': None, 'agente': 'demanda'}
        with patch.object(routes.agent, 'run', side_effect=real_execution):
            response = self.client.post('/api/asistente-ia/preparar', headers=self.headers,
                                        json={'instruccion': 'Analiza la demanda'})
        self.assertEqual(response.status_code, 200, response.json)
        result = response.json
        trace = result['actividad']
        self.assertEqual(trace['agentes'], ['orquestador', 'demanda'])
        url = '/api/asistente-ia/actividad/' + trace['id']
        self.assertEqual(self.client.get(url, headers=self.headers).json, trace)
        self.assertEqual(self.client.get(url, headers=self.token(user=2)).status_code, 404)
        self.assertEqual(self.client.get(url, headers=self.token(profile=2)).status_code, 404)
        self.assertEqual(self.client.get(url, headers=self.token(local=2)).status_code, 404)
        result['actividad']['entrada'] = 'Texto manipulado en el navegador'
        saved = self.put(self.snapshot(result=result, history=[{
            'prompt': 'Consulta', 'response': 'Dos registros', 'time': '10:00', 'done': False,
            'queries': [], 'actividad': trace}]))
        self.assertEqual(saved.status_code, 200, saved.json)
        restored = self.get().json['workspace']
        self.assertEqual(restored['result']['actividad']['entrada'], 'Analiza la demanda')
        self.assertEqual(restored['history'][0]['actividad']['entrada'], 'Analiza la demanda')


if __name__ == '__main__':
    unittest.main()

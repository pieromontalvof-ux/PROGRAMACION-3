import unittest
import json
import os
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch, MagicMock
from datetime import datetime, timezone


class QuotaRulesTests(unittest.TestCase):
    def test_budget_denial_happens_before_http(self):
        from app.multiagente.api import provider
        with patch.dict(os.environ, {'OPENAI_API_KEY': 'test'}), patch('app.multiagente.api.quotas.reserve', side_effect=provider.AssistantError('Sin saldo', 429)), patch.object(provider, 'urlopen') as request:
            with self.assertRaises(provider.AssistantError):
                provider.call('responses', b'{}')
            request.assert_not_called()

    def test_uncertain_transport_is_not_retried_and_keeps_reservation(self):
        from app.multiagente.api import provider
        with patch.dict(os.environ, {'OPENAI_API_KEY': 'test'}), patch('app.multiagente.api.quotas.reserve', return_value='reservation'), patch('app.multiagente.api.quotas.settle') as settle, patch.object(provider, 'urlopen', side_effect=TimeoutError) as request:
            with self.assertRaises(provider.AssistantError):
                provider.call('responses', b'{}')
            self.assertEqual(request.call_count, 1)
            settle.assert_called_once_with('reservation')

    def test_provider_result_settles_real_usage(self):
        from app.multiagente.api import provider
        response = MagicMock()
        response.__enter__.return_value.read.return_value = b'{"usage":{"input_tokens":10,"output_tokens":3}}'
        with patch.dict(os.environ, {'OPENAI_API_KEY': 'test'}), patch('app.multiagente.api.quotas.reserve', return_value='reservation'), patch('app.multiagente.api.quotas.settle') as settle, patch.object(provider, 'urlopen', return_value=response):
            provider.call('responses', b'{}')
            settle.assert_called_once_with('reservation', {'usage': {'input_tokens': 10, 'output_tokens': 3}})

    def test_lima_day_and_month_boundaries(self):
        from app.multiagente.api.quotas import periods
        day, month = periods(datetime(2026, 12, 1, 3, tzinfo=timezone.utc))
        self.assertEqual(day.isoformat(), '2026-11-30')
        self.assertEqual(month.isoformat(), '2026-11-01')

    def test_zero_blocks_and_none_is_unlimited(self):
        from app.multiagente.api.quotas import validate_limit, exceeds
        self.assertEqual(validate_limit(0), 0)
        self.assertIsNone(validate_limit(None))
        self.assertTrue(exceeds(0, 0, 1))
        self.assertFalse(exceeds(None, 9000, 1))
        for value in (True, -1, 1.2, '100'):
            with self.assertRaises(ValueError):
                validate_limit(value)

    def test_text_reservation_includes_full_payload_and_output(self):
        from app.multiagente.api.quotas import reservation_size
        body = b'{"model":"test","input":"hello","max_output_tokens":100}'
        self.assertEqual(reservation_size(body), len(body) + 100)


@unittest.skipUnless(os.getenv('LOCAL_SCOPE_TEST_DB') == '1', 'PostgreSQL aislado')
class QuotaIntegrationTests(unittest.TestCase):
    def setUp(self):
        from app import create_app
        from app.core.extensions import db
        from sqlalchemy import text
        self.app = create_app()
        self.app.config['JWT_SECRET_KEY'] = 'quota-tests-secret-longer-than-32-characters'
        self.ctx = self.app.app_context(); self.ctx.push()
        sql = (Path(__file__).resolve().parents[2] / 'database/migrations/20261124_ai_quotas.sql').read_text(encoding='utf-8')
        db.session.execute(text(sql.replace('BEGIN;', '').replace('COMMIT;', '')))
        db.session.execute(text('DELETE FROM ia_consumo; DELETE FROM ia_cuota_usuario; DELETE FROM ia_cuota_auditoria; UPDATE ia_cuota_config SET activo=false, diario=NULL,mensual=NULL,global_diario=NULL,global_mensual=NULL'))
        db.session.commit()

    def tearDown(self):
        from app.core.extensions import db
        db.session.remove(); self.ctx.pop()

    def authenticated(self, user=2, profile=2, local=1):
        from flask_jwt_extended import create_access_token
        return create_access_token(identity=str(user), additional_claims={'tipo_token': 'operativo', 'id_perfil': profile, 'id_local': local})

    def reserve(self, body, user=2, profile=2, local=1):
        from flask_jwt_extended import verify_jwt_in_request
        from app.multiagente.api import quotas
        with self.app.test_request_context(headers={'Authorization': 'Bearer ' + self.authenticated(user, profile, local)}):
            verify_jwt_in_request()
            return quotas.reserve(body)

    def config(self, **changes):
        from app.multiagente.api import quotas
        config = dict(activo=True, diario=None, mensual=None, global_diario=None, global_mensual=None)
        quotas.save({**config, **changes}, 1)

    def test_concurrent_reservations_cannot_double_spend(self):
        from app.multiagente.api import quotas
        from app.multiagente.api.provider import AssistantError
        payload = json.dumps({'model': 'test', 'input': 'text', 'max_output_tokens': 100}).encode()
        self.config(diario=quotas.reservation_size(payload))
        def attempt(_):
            with self.app.app_context():
                try:
                    return bool(self.reserve(payload))
                except AssistantError as error:
                    self.assertEqual(error.status, 429)
                    return False
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(attempt, range(4)))
        self.assertEqual(sum(results), 1)

    def test_real_usage_replaces_reservation_and_unknown_keeps_it(self):
        from app.multiagente.api import quotas
        payload = json.dumps({'model': 'test', 'input': 'text', 'max_output_tokens': 100}).encode()
        identity = self.reserve(payload)
        quotas.settle(identity, {'usage': {'input_tokens': 8, 'output_tokens': 3}})
        quotas.settle(identity, released=True)  # terminal records cannot be overwritten
        uncertain = self.reserve(payload)
        quotas.settle(uncertain)
        row = next(r for r in quotas.report()['usuarios'] if r['id_usuario'] == 2)
        self.assertEqual(row['consumo_diario'], 11 + quotas.reservation_size(payload))
        self.assertEqual(row['pendiente'], quotas.reservation_size(payload))

    def test_global_cap_shared_between_users_and_roles(self):
        from app.multiagente.api import quotas
        from app.multiagente.api.provider import AssistantError
        payload = json.dumps({'model': 'test', 'input': 'text', 'max_output_tokens': 100}).encode()
        self.config(global_mensual=quotas.reservation_size(payload))
        self.reserve(payload)
        with self.assertRaises(AssistantError):
            self.reserve(payload, user=1, profile=1, local=2)

    def test_threaded_batches_keep_the_responsible_user(self):
        from flask_jwt_extended import verify_jwt_in_request
        from app.multiagente.api import quotas
        from app.multiagente.agents.eventos import batches
        recorded = []
        def search(payload):
            identity = quotas.reserve(json.dumps(payload).encode())
            recorded.append(identity)
            quotas.settle(identity, {'usage': {'input_tokens': 4, 'output_tokens': 1}})
            return {'status': 'completed', 'output': []}
        with self.app.test_request_context(headers={'Authorization': 'Bearer ' + self.authenticated()}):
            verify_jwt_in_request()
            batches.run([{'model': 'test', 'input': 'text', 'max_output_tokens': 10}] * 3, search)
        row = next(r for r in quotas.report()['usuarios'] if r['id_usuario'] == 2)
        self.assertEqual(len(recorded), 3)
        self.assertEqual(row['consumo_diario'], 15)

    def test_hosted_tools_do_not_bypass_a_hard_budget(self):
        from app.multiagente.api.provider import AssistantError
        self.config(diario=1000000)
        with self.assertRaises(AssistantError):
            self.reserve(json.dumps({'model': 'test', 'input': 'search', 'max_output_tokens': 100, 'tools': [{'type': 'web_search'}]}).encode())

    def test_individual_override_and_return_to_default_are_audited(self):
        from app.multiagente.api import quotas
        from app.multiagente.api.provider import AssistantError
        from app.core.extensions import db
        from sqlalchemy import text
        self.config(diario=0)
        payload = json.dumps({'model': 'test', 'input': 'text', 'max_output_tokens': 10}).encode()
        with self.assertRaises(AssistantError):
            self.reserve(payload)
        quotas.save({'diario': None, 'mensual': None}, 1, 2)
        self.assertIsNotNone(self.reserve(payload))
        quotas.inherit(2, 1)
        with self.assertRaises(AssistantError):
            self.reserve(payload)
        self.assertEqual(db.session.execute(text('SELECT count(*) FROM ia_cuota_auditoria WHERE id_usuario=2')).scalar(), 2)

    def test_only_admin_can_read_or_update_limits(self):
        client = self.app.test_client()
        headers = {'Authorization': 'Bearer ' + self.authenticated()}
        self.assertEqual(client.get('/api/asistente-ia/limites', headers=headers).status_code, 403)
        self.assertEqual(client.put('/api/asistente-ia/limites', headers=headers, json={}).status_code, 403)
        headers = {'Authorization': 'Bearer ' + self.authenticated(1, 1)}
        response = client.get('/api/asistente-ia/limites', headers=headers)
        self.assertEqual(response.status_code, 200, response.get_json())
        self.assertIn('no-store', response.headers['Cache-Control'])
        for row in response.get_json()['usuarios']:
            for field in ('consumo_diario', 'consumo_mensual', 'pendiente'):
                self.assertIs(type(row[field]), int)
        saved = client.put('/api/asistente-ia/limites/usuarios/2', headers=headers,
                           json={'diario': 200000, 'mensual': 2000000})
        self.assertEqual(saved.status_code, 200, saved.get_json())
        users = client.get('/api/asistente-ia/limites', headers=headers).get_json()['usuarios']
        row = next(user for user in users if user['id_usuario'] == 2)
        self.assertEqual(row['diario'], 200000)
        self.assertEqual(row['mensual'], 2000000)
        self.assertTrue(row['personalizado'])
        self.assertEqual([role['id'] for role in row['roles']], [2])
        self.assertEqual([local['id'] for local in row['locales']], [1])
        administrator = next(user for user in users if user['id_usuario'] == 1)
        self.assertEqual({local['id'] for local in administrator['locales']}, {1, 2})

    def test_global_shutdown_blocks_queries_and_dictation_but_admin_can_reactivate(self):
        client = self.app.test_client()
        admin = {'Authorization': 'Bearer ' + self.authenticated(1, 1)}
        manager = {'Authorization': 'Bearer ' + self.authenticated()}
        self.assertEqual(client.put('/api/asistente-ia/limites/estado', headers=manager, json={'habilitado': False}).status_code, 403)
        result = client.put('/api/asistente-ia/limites/estado', headers=admin, json={'habilitado': False})
        self.assertEqual(result.status_code, 200, result.get_json())
        try:
            for path in ('preparar', 'transcribir', 'realizar'):
                response = client.post('/api/asistente-ia/' + path, headers=manager, json={})
                self.assertEqual(response.status_code, 503, response.get_json())
                self.assertIn('desactivado', response.get_json()['mensaje'])
            self.assertEqual(client.get('/api/asistente-ia/limites', headers=admin).status_code, 200)
        finally:
            self.assertEqual(client.put('/api/asistente-ia/limites/estado', headers=admin, json={'habilitado': True}).status_code, 200)

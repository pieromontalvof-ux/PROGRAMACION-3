import unittest
from unittest.mock import patch
from flask import Flask
from flask_jwt_extended import JWTManager, create_access_token
from app.core.telemetry import RuntimeMetrics
from app.core.telemetry import register_http_telemetry


class RuntimeMetricsTest(unittest.TestCase):
    def test_retains_only_bounded_recent_samples(self):
        metrics = RuntimeMetrics(capacity=2, retention_seconds=10)
        metrics.record('GET', '/one', 200, 10, now=0)
        metrics.record('GET', '/two', 500, 20, now=1)
        metrics.record('GET', '/two', 200, 30, now=2)
        result = metrics.snapshot(now=3)
        self.assertEqual(result['requests'], 2)
        self.assertEqual(result['errors'], 1)
        self.assertEqual(result['routes'][0]['p95_ms'], 30)
        self.assertEqual(metrics.snapshot(now=20)['requests'], 0)

    def test_instances_do_not_share_data(self):
        first = RuntimeMetrics()
        first.record('GET', '/health', 200, 1)
        self.assertEqual(RuntimeMetrics().snapshot()['requests'], 0)

    def test_diagnostics_requires_active_admin_permission(self):
        app = Flask(__name__)
        app.config['JWT_SECRET_KEY'] = 'test-only-key-long-enough-for-signing'
        JWTManager(app)
        register_http_telemetry(app)
        client = app.test_client()
        self.assertEqual(client.get('/api/diagnostico').status_code, 401)
        with app.app_context():
            admin = create_access_token(identity='1', additional_claims={'tipo_token': 'operativo', 'id_perfil': 1})
            manager = create_access_token(identity='1', additional_claims={'tipo_token': 'operativo', 'id_perfil': 2})
        with patch('app.core.permissions.db') as database:
            database.session.execute.return_value.scalar.return_value = True
            self.assertEqual(client.get('/api/diagnostico', headers={'Authorization': f'Bearer {manager}'}).status_code, 403)
            self.assertEqual(client.get('/api/diagnostico', headers={'Authorization': f'Bearer {admin}'}).status_code, 200)
            database.session.execute.return_value.scalar.return_value = False
            self.assertEqual(client.get('/api/diagnostico', headers={'Authorization': f'Bearer {admin}'}).status_code, 403)

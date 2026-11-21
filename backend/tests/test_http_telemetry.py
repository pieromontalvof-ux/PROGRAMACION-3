import unittest
import logging
from unittest.mock import patch
from flask import Flask
from app.core.telemetry import register_http_telemetry


class HttpTelemetryTest(unittest.TestCase):
    def test_correlates_response_without_logging_private_values(self):
        app = Flask(__name__)
        register_http_telemetry(app)
        self.assertTrue(app.logger.isEnabledFor(logging.INFO))
        app.add_url_rule('/api/clientes/<int:cliente>', view_func=lambda cliente: {'ok': True})
        with patch.object(app.logger, 'info') as log:
            response = app.test_client().get('/api/clientes/123?dni=secret', headers={'Authorization': 'secret'})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.headers['X-Request-ID']), 32)
        self.assertIn('Server-Timing', response.headers)
        self.assertNotIn('secret', str(log.call_args))
        self.assertIn('/api/clientes/<int:cliente>', str(log.call_args))

    def test_missing_route_is_measured_without_raw_path(self):
        app = Flask(__name__)
        register_http_telemetry(app)
        with patch.object(app.logger, 'info') as log:
            response = app.test_client().get('/api/not-found-private')
        self.assertEqual(response.status_code, 404)
        self.assertIn('X-Request-ID', response.headers)
        self.assertNotIn('not-found-private', str(log.call_args))

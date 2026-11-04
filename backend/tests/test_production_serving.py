import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from app import create_app
from app.core.config import Config


class ProductionServingTests(unittest.TestCase):
    def test_serves_frontend_routes_and_assets_without_masking_api_errors(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'index.html').write_text('<html>Barbarito</html>', encoding='utf-8')
            (root / 'assets').mkdir()
            (root / 'assets/app.js').write_text('console.log("ok")', encoding='utf-8')
            (root / '.env').write_text('PRIVATE', encoding='utf-8')
            with patch.dict(os.environ, {'FRONTEND_DIST': folder, 'APP_DATA_DIR': str(root / 'data')}), patch.object(Config, 'SQLALCHEMY_DATABASE_URI', 'sqlite://'):
                app = create_app()
                self.assertEqual(app.instance_path, str(root / 'data'))
                with app.test_client() as client:
                    with client.get('/home/asistente-ia/mapa') as response:
                        self.assertIn(b'Barbarito', response.data)
                    with client.get('/assets/app.js') as response:
                        self.assertEqual(response.status_code, 200)
                    for path in ('/api/no-existe', '/api', '/assets/no-existe.js', '/.env'):
                        self.assertEqual(client.get(path).status_code, 404, path)

    def test_production_rejects_missing_or_weak_secrets(self):
        from app.core.production import validate_environment
        for values in ({}, {'DATABASE_URL': 'postgresql://test', 'SECRET_KEY': 'short', 'JWT_SECRET_KEY': 'short'}):
            with patch.dict(os.environ, values, clear=True):
                with self.assertRaises(RuntimeError):
                    validate_environment()
        with patch.dict(os.environ, {'DATABASE_URL': 'postgresql://test', 'SECRET_KEY': 'a' * 48, 'JWT_SECRET_KEY': 'b' * 48}, clear=True):
            validate_environment()

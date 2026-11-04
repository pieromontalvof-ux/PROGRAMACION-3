"""Production entry checks and same-origin React delivery."""
import os
from pathlib import Path
from flask import abort, send_from_directory
from werkzeug.utils import safe_join


def validate_environment():
    if not os.getenv('DATABASE_URL', '').strip():
        raise RuntimeError('Configura DATABASE_URL en el servicio de alojamiento.')
    for key in ('SECRET_KEY', 'JWT_SECRET_KEY'):
        value = os.getenv(key, '')
        if len(value) < 32 or value.startswith('REEMPLAZAR'):
            raise RuntimeError(f'Configura {key} con un secreto aleatorio de al menos 32 caracteres.')


def register_frontend(app):
    default = Path(__file__).resolve().parents[3] / 'frontend' / 'dist'
    folder = Path(os.getenv('FRONTEND_DIST') or default).resolve()
    if not (folder / 'index.html').is_file():
        return

    @app.get('/', defaults={'path': ''})
    @app.get('/<path:path>')
    def frontend(path):
        if path == 'api' or path.startswith('api/') or any(part.startswith('.') for part in path.split('/') if part):
            abort(404)
        filename = safe_join(str(folder), path)
        if filename and Path(filename).is_file():
            return send_from_directory(folder, path)
        if path.startswith('assets/') or '.' in Path(path).name:
            abort(404)
        response = send_from_directory(folder, 'index.html')
        response.headers['Cache-Control'] = 'no-cache'
        return response

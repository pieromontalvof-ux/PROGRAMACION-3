"""Process the durable queue of external directory queries."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app import create_app
from app.modules.facturacion.scaling import worker_loop
from app.modules.integraciones.routes import procesar_consulta


if __name__ == '__main__':
    app = create_app()

    def process():
        try:
            with app.app_context():
                return procesar_consulta()
        except Exception as error:
            app.logger.error('Integration worker failed (%s); the job remains queued.', type(error).__name__)
            return False

    worker_loop(process, once='--once' in sys.argv)

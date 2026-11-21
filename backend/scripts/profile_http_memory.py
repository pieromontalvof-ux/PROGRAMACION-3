"""Diagnóstico local de asignaciones Python sobre lecturas de salud (sin escrituras)."""
import gc
import json
import logging
from pathlib import Path
import sys
import tracemalloc
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import create_app

app = create_app()
app.logger.setLevel(logging.WARNING)
client = app.test_client()
for _ in range(500):
    assert client.get('/api/health').status_code == 200
tracemalloc.start()
measurements = []
for _ in range(3):
    for _ in range(300):
        assert client.get('/api/health').status_code == 200
    gc.collect()
    current, peak = tracemalloc.get_traced_memory()
    measurements.append({'requests': 300, 'retained_kib': round(current / 1024, 1), 'peak_kib': round(peak / 1024, 1),
                         'metric_samples': app.extensions['runtime_metrics'].snapshot()['requests']})
tracemalloc.stop()
print(json.dumps({'scope': 'Python allocations: health endpoint only; not browser memory or RSS', 'batches': measurements}, indent=2))

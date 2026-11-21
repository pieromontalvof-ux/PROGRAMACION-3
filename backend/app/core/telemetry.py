"""Mediciones HTTP sin cuerpos, documentos, tokens ni parámetros personales."""
from time import perf_counter, monotonic
from collections import deque, defaultdict
from threading import Lock
from math import ceil
from uuid import uuid4
import logging
from flask import g, request


class RuntimeMetrics:
    """Ventana acotada por proceso; no conserva datos de clientes ni solicitudes."""
    def __init__(self, capacity=500, retention_seconds=900):
        self.samples = deque(maxlen=capacity)
        self.retention_seconds = retention_seconds
        self.lock = Lock()

    def record(self, method, route, status, duration_ms, now=None):
        with self.lock:
            self.samples.append((monotonic() if now is None else now,
                                 method, route, status, duration_ms))

    def snapshot(self, now=None):
        now = monotonic() if now is None else now
        with self.lock:
            while self.samples and self.samples[0][0] < now - self.retention_seconds:
                self.samples.popleft()
            samples = list(self.samples)
        groups = defaultdict(list)
        for _, method, route, status, duration in samples:
            groups[(method, route)].append((status, duration))
        routes = []
        for (method, route), rows in groups.items():
            durations = sorted(duration for _, duration in rows)
            routes.append(dict(method=method, route=route, requests=len(rows),
                               errors=sum(status >= 500 for status, _ in rows),
                               p95_ms=round(durations[ceil(len(rows) * .95) - 1], 2)))
        return dict(requests=len(samples), errors=sum(s[3] >= 500 for s in samples),
                    retention_seconds=self.retention_seconds,
                    capacity=self.samples.maxlen,
                    routes=sorted(routes, key=lambda r: r['p95_ms'], reverse=True))


def register_http_telemetry(app):
    metrics = RuntimeMetrics()
    app.extensions['runtime_metrics'] = metrics
    from flask import jsonify
    from flask_jwt_extended import get_jwt
    from app.core.permissions import requiere_permiso

    @app.get('/api/diagnostico')
    @requiere_permiso(id_opcion_menu=26, accion='consultar')
    def runtime_diagnostics():
        if str(get_jwt().get('id_perfil')) != '1':
            return jsonify(mensaje='Solo el administrador puede consultar el diagnóstico'), 403
        return jsonify(metrics.snapshot())

    app.logger.setLevel(logging.INFO)
    @app.before_request
    def start_request():
        g.http_started = perf_counter()
        g.request_id = uuid4().hex

    @app.after_request
    def finish_request(response):
        elapsed = (perf_counter() - g.http_started) * 1000
        response.headers['X-Request-ID'] = g.request_id
        response.headers['Server-Timing'] = f'app;dur={elapsed:.2f}'
        metrics.record(request.method, str(request.url_rule) if request.url_rule else 'unmatched',
                       response.status_code, elapsed)
        app.logger.info('http request_id=%s method=%s route=%s status=%s duration_ms=%.2f',
                        g.request_id, request.method,
                        str(request.url_rule) if request.url_rule else 'unmatched',
                        response.status_code, elapsed)
        return response

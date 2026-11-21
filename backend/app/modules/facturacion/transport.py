"""Authenticated bounded HTTP. No redirects, raw errors or credentials in logs."""
import json
import os
from urllib.parse import urlsplit
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.error import HTTPError, URLError


class ApiError(Exception):
    def __init__(self, status=503, retry_after=0):
        self.status = status
        self.retry_after = min(3600, max(0, retry_after))
        super().__init__(f'fact_api HTTP {status}')


def validate_url(value):
    parts = urlsplit(value)
    if (parts.scheme not in ('http','https') or not parts.hostname or parts.username or parts.password
            or parts.query or parts.fragment or parts.path not in ('','/')
            or (parts.scheme == 'http' and parts.hostname not in ('127.0.0.1','localhost','::1'))):
        raise ValueError('FACT_API_URL debe ser un origen HTTPS o localhost HTTP, sin credenciales ni ruta.')
    return value.rstrip('/')


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def call(path, payload=None, operation=None, binary=False):
    base = validate_url(os.environ['FACT_API_URL'])
    token = os.environ.get('FACT_API_TOKEN','').strip()
    if not token:
        raise ApiError(401)
    headers = {'Authorization': 'Bearer '+token, 'Accept': 'application/pdf' if binary else 'application/json'}
    if operation:
        headers.update({'Idempotency-Key': str(operation), 'X-Request-ID': str(operation)})
    if payload is not None:
        headers['Content-Type'] = 'application/json'
    request = Request(base+'/api/barbarito/'+path, data=None if payload is None else json.dumps(payload).encode(), headers=headers)
    try:
        with build_opener(NoRedirect()).open(request, timeout=20) as response:
            limit = 10*1024*1024 if binary else 1024*1024
            data = response.read(limit+1)
            if len(data)>limit:
                raise ApiError(502)
            if binary:
                if not data.startswith(b'%PDF-'):
                    raise ApiError(502)
                return data
            result = json.loads(data)
            if not isinstance(result,dict):
                raise ApiError(502)
            return result
    except HTTPError as error:
        retry = error.headers.get('Retry-After','0')
        status=error.code
        error.close()
        raise ApiError(status, int(retry) if retry.isdigit() else 0) from None
    except (URLError, TimeoutError, OSError, ValueError):
        raise ApiError(503) from None

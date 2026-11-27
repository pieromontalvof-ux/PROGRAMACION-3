"""Deployment defaults and environment overrides for integrations."""
import json
import os
from pathlib import Path
from urllib.parse import urlsplit


def cargar():
    predeterminados = json.loads(Path(__file__).with_name('settings.json').read_text(encoding='utf8'))
    valores = {}
    for nombre, predeterminado in predeterminados.items():
        valor = os.getenv(nombre, str(predeterminado)).strip()
        if isinstance(predeterminado, int):
            try:
                valor = int(valor)
                if valor < 1:
                    raise ValueError
            except ValueError:
                raise ValueError(f'{nombre} debe ser un entero positivo.') from None
        valores[nombre] = valor
    host = valores['ACADESYS_API_HOST'].lower()
    try:
        if not host or urlsplit('https://' + host).hostname != host or any(c.isspace() for c in host):
            raise ValueError
    except ValueError:
        raise ValueError('ACADESYS_API_HOST debe contener solo el dominio.') from None
    valores['ACADESYS_API_HOST'] = host
    if valores['INTEGRACIONES_VIGENCIA_DIAS'] > valores['INTEGRACIONES_VIGENCIA_MAX_DIAS']:
        raise ValueError('INTEGRACIONES_VIGENCIA_DIAS supera INTEGRACIONES_VIGENCIA_MAX_DIAS.')
    if valores['INTEGRACIONES_HTTP_TIMEOUT_SEGUNDOS'] > valores['INTEGRACIONES_HTTP_PLAZO_SEGUNDOS']:
        raise ValueError('INTEGRACIONES_HTTP_TIMEOUT_SEGUNDOS supera INTEGRACIONES_HTTP_PLAZO_SEGUNDOS.')
    return valores

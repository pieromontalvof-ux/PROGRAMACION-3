"""Minimal identity lookup; credentials and provider responses stay server-side."""
import json
import os
import re
from urllib.error import HTTPError, URLError
from urllib.request import Request, build_opener, HTTPRedirectHandler
from werkzeug.exceptions import BadRequest, NotFound, ServiceUnavailable, TooManyRequests


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


urlopen = build_opener(NoRedirect()).open


def consultar(tipo, numero):
    if tipo not in ('DNI', 'RUC') or not isinstance(numero, str) or not re.fullmatch(r'[0-9]{%d}' % (8 if tipo=='DNI' else 11), numero):
        raise BadRequest('Indica un DNI de 8 digitos o un RUC de 11 digitos.')
    token=os.getenv('FACTILIZA_TOKEN','').strip()
    if not token:
        raise ServiceUnavailable('Falta configurar FACTILIZA_TOKEN en el backend. Puedes ingresar los datos manualmente.')
    req=Request(f'https://api.factiliza.com/v1/{tipo.lower()}/info/{numero}', headers={'Authorization':'Bearer '+token,'Accept':'application/json'})
    try:
        # No automatic retries: repeated calls may consume the free quota.
        with urlopen(req,timeout=8) as response:
            raw=response.read(65537)
        if len(raw)>65536:raise ValueError()
        result=json.loads(raw)
        data=result.get('data')
        if result.get('success') is not True or not isinstance(data,dict):
            raise NotFound('El proveedor no encontro datos para ese documento.')
        name=data.get('nombre_completo') if tipo=='DNI' else data.get('nombre_o_razon_social')
        if str(data.get('numero'))!=numero or not isinstance(name,str) or not name.strip() or len(name)>200:
            raise ValueError()
        resultado = {'tipo_documento':tipo,'numero_documento':numero,'nombre':name.strip(),'fuente':'Factiliza'}
        direccion = data.get('direccion_completa') or data.get('direccion')
        if isinstance(direccion, str) and direccion.strip() not in ('', '-'):
            resultado['direccion'] = direccion.strip()[:300]
        return resultado
    except HTTPError as error:
        if error.code==429:raise TooManyRequests('Se alcanzo el limite de consultas del proveedor. Puedes completar los datos manualmente.') from None
        if error.code==404:raise NotFound('El proveedor no encontro ese documento.') from None
        raise ServiceUnavailable('No se pudo consultar el proveedor. Revisa el token o ingresa los datos manualmente.') from None
    except (URLError,TimeoutError,OSError,ValueError,TypeError,AttributeError):
        raise ServiceUnavailable('La consulta externa no esta disponible. Puedes completar los datos manualmente.') from None

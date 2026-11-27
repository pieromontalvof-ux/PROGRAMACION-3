import re

from werkzeug.exceptions import BadGateway, BadRequest


def corresponde(ruta):
    return ruta.rstrip('/') in (
        '/api/integracion/v1/clientes', '/api/integracion/v1/clientes/pendientes',
    )


def leer(respuesta):
    if isinstance(respuesta, list) and not respuesta:
        return {'clientes': []}, None
    if not isinstance(respuesta, dict) or not isinstance(respuesta.get('datos'), list):
        raise BadGateway('La respuesta de AcadeSys no incluye la lista datos.')
    if len(respuesta['datos']) > 100:
        raise BadGateway('AcadeSys devolvio mas de 100 alumnos en una pagina.')
    pagina = respuesta.get('paginacion')
    cursor = None
    if isinstance(pagina, dict) and pagina.get('hayMas') is True:
        cursor = pagina.get('siguienteCursor')
        if not isinstance(cursor, str) or not cursor or len(cursor) > 1024:
            raise BadGateway('AcadeSys indica que hay mas resultados pero no entrego un cursor valido.')
    return {'clientes': respuesta['datos']}, cursor


def mapear(fila):
    if not isinstance(fila, dict):
        raise BadRequest('El alumno debe ser un objeto JSON.')
    identidad = fila.get('idCliente')
    version = fila.get('version')
    if not isinstance(identidad, str) or not 1 <= len(identidad.strip()) <= 120:
        raise BadRequest('Falta el identificador idCliente de AcadeSys.')
    if not isinstance(version, str) or not re.fullmatch(r'[0-9a-fA-F]{64}', version):
        raise BadRequest('Falta la version valida del alumno en AcadeSys.')
    partes = (fila.get(campo) for campo in ('nombres', 'apellidoPaterno', 'apellidoMaterno'))
    nombre = fila.get('nombreCompleto') or ' '.join(p.strip() for p in partes if isinstance(p, str) and p.strip())
    cliente = {
        'tipo_persona': 'NATURAL', 'nombre': nombre,
        'tipo_documento': fila.get('tipoDocumento'), 'numero_documento': fila.get('numeroDocumento'),
        'email': fila.get('correo'), 'telefono': fila.get('celular'),
    }
    return cliente, identidad.strip(), version.lower()

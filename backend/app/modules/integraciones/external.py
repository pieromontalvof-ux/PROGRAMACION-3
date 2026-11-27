import ipaddress
import json
import socket
import ssl
from http.client import HTTPException, HTTPSConnection
from time import monotonic
from urllib.parse import urlsplit

from flask import current_app
from werkzeug.exceptions import BadGateway, BadRequest, GatewayTimeout

class FalloTemporal(BadGateway):
    pass


def url_https(url):
    try:
        destino = urlsplit(url)
        host = destino.hostname
        if (destino.scheme != 'https' or not host or destino.port not in (None, 443)
                or destino.username is not None or destino.password is not None or destino.fragment
                or any(ord(caracter) < 33 for caracter in url)):
            raise ValueError()
        host = host.encode('idna').decode('ascii')
        if len(host) > 253:
            raise ValueError()
    except (UnicodeError, ValueError):
        raise BadRequest('Ingresa una URL HTTPS publica, sin usuario, clave ni fragmento.') from None
    return destino, host


def destino_publico(url):
    destino, host = url_https(url)
    try:
        direcciones = socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
    except OSError:
        raise FalloTemporal('No se pudo encontrar el servidor de la API externa.') from None
    for _, _, _, _, direccion in direcciones:
        ip = ipaddress.ip_address(direccion[0])
        if not ip.is_global or ip.is_multicast or ip.is_reserved or ip.is_link_local:
            raise BadRequest('La API externa debe usar una direccion publica.')
    if not direcciones:
        raise FalloTemporal('El servidor no tiene una direccion disponible.')
    return destino, host, direcciones[0]


class ConexionVerificada(HTTPSConnection):
    def __init__(self, host, direccion):
        super().__init__(host, timeout=current_app.config['INTEGRACIONES_HTTP_TIMEOUT_SEGUNDOS'], context=ssl.create_default_context())
        self.direccion = direccion

    def connect(self):
        familia, tipo, protocolo, _, direccion = self.direccion
        canal = socket.socket(familia, tipo, protocolo)
        try:
            canal.settimeout(self.timeout)
            canal.connect(direccion)
            self.sock = self._context.wrap_socket(canal, server_hostname=self.host)
        except Exception:
            canal.close()
            raise


def consultar(url, token):
    destino, host, direccion = destino_publico(url)
    ruta = destino.path or '/'
    if destino.query:
        ruta += '?' + destino.query
    cabeceras = {'Accept': 'application/json'}
    if token:
        cabeceras['Authorization'] = 'Bearer ' + token
    limite_bytes = current_app.config['INTEGRACIONES_HTTP_MAX_BYTES']
    with_deadline = monotonic() + current_app.config['INTEGRACIONES_HTTP_PLAZO_SEGUNDOS']
    conexion = ConexionVerificada(host, direccion)
    try:
        conexion.request('GET', ruta, headers=cabeceras)
        respuesta = conexion.getresponse()
        if respuesta.status in (401, 403):
            raise BadGateway('La API externa rechazo el acceso. Revisa su clave.')
        if respuesta.status == 204:
            return host, destino.path, []
        if respuesta.status == 429 or respuesta.status >= 500:
            raise FalloTemporal(f'La API externa respondio con HTTP {respuesta.status}.')
        if respuesta.status != 200:
            raise BadGateway(f'La API externa respondio con HTTP {respuesta.status}. Usa la URL final del recurso.')
        datos = bytearray()
        while len(datos) <= limite_bytes:
            if monotonic() > with_deadline:
                raise GatewayTimeout('La API externa tardo demasiado. Puedes volver a solicitar los datos.')
            bloque = respuesta.read1(min(65536, limite_bytes + 1 - len(datos)))
            if not bloque:
                break
            datos.extend(bloque)
        if len(datos) > limite_bytes:
            raise BadGateway('La respuesta es demasiado grande. Solicita una pagina mas pequena.')
        try:
            return host, destino.path, json.loads(datos)
        except (ValueError, RecursionError):
            raise BadGateway('La API externa no devolvio JSON valido.') from None
    except TimeoutError:
        raise GatewayTimeout('La API externa tardo demasiado. Puedes volver a solicitar los datos.') from None
    except (OSError, HTTPException, UnicodeError):
        raise FalloTemporal('No se pudo conectar con la API externa. Revisa la URL y el certificado.') from None
    finally:
        conexion.close()


def separar(datos, tipo=None):
    if isinstance(datos, dict):
        colecciones = {nombre: datos[nombre] for nombre in ('clientes', 'proveedores') if nombre in datos}
        lista = datos.get('data')
    else:
        colecciones = {}
        lista = datos
    if not colecciones and isinstance(lista, list):
        if tipo:
            colecciones = {tipo: lista}
        elif not lista:
            colecciones = {'clientes': [], 'proveedores': []}
        else:
            raise BadGateway('La API devolvio una lista sin indicar el tipo. En Opciones de la consulta indica que contiene esa lista.')
    if not colecciones or any(not isinstance(filas, list) for filas in colecciones.values()):
        raise BadGateway('El JSON debe incluir una lista, datos en data o listas de clientes y proveedores.')
    limite_registros = current_app.config['INTEGRACIONES_HTTP_MAX_REGISTROS']
    if sum(map(len, colecciones.values())) > limite_registros:
        raise BadGateway(f'La respuesta supera {limite_registros} registros. Solicita una pagina mas pequena.')
    return colecciones

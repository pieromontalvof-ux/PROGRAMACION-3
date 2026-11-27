from datetime import datetime, timedelta, timezone
from functools import wraps
from hmac import compare_digest
from hashlib import sha256
import json
from secrets import token_urlsafe
from urllib.parse import parse_qsl, urlencode, urlsplit
from uuid import UUID, uuid4

from flask import Blueprint, current_app, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, verify_jwt_in_request
from sqlalchemy import UniqueConstraint, func, select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from werkzeug.exceptions import BadRequest, Conflict, Forbidden, HTTPException, NotFound, ServiceUnavailable, Unauthorized

from app.core.extensions import db
from app.core.local_scope import local_actual
from app.core.profile_capabilities import perfil_tiene_capacidad
from app.modules.catalogos import repository as catalogo
from app.modules.catalogos.service import crear_proveedor_catalogo
from app.modules.clientes import service as clientes

from . import acadesys, external

bp = Blueprint('integraciones', __name__)


class Solicitud(db.Model):
    __tablename__ = 'integracion_solicitud'
    __table_args__ = (UniqueConstraint('id_local', 'origen', 'tipo', 'clave'), {'schema': 'public'})
    id = db.Column(db.String(36), primary_key=True)
    id_local = db.Column(db.Integer, nullable=False)
    origen = db.Column(db.String(120), nullable=False)
    tipo = db.Column(db.String(15), nullable=False)
    clave = db.Column(db.String(128), nullable=False)
    datos = db.Column(db.JSON, nullable=False)
    estado = db.Column(db.String(15), nullable=False, default='PENDIENTE')
    recibido_en = db.Column(db.DateTime(timezone=True), nullable=False, server_default=func.now())
    revisado_en = db.Column(db.DateTime(timezone=True))
    revisado_por = db.Column(db.Integer)
    id_registro = db.Column(db.String(36))
    mensaje = db.Column(db.Text)
    consulta_id = db.Column(db.String(36))
    eventos = db.Column(db.JSON, nullable=False, default=list)


class ClaveIntegracion(db.Model):
    __tablename__ = 'integracion_clave'
    __table_args__ = {'schema': 'public'}
    id = db.Column(db.String(36), primary_key=True)
    id_local = db.Column(db.Integer, nullable=False)
    nombre = db.Column(db.String(80), nullable=False)
    origen = db.Column(db.String(120), nullable=False)
    permiso = db.Column(db.String(15), nullable=False, default='ambos')
    vence_en = db.Column(db.DateTime(timezone=True))
    revocado_en = db.Column(db.DateTime(timezone=True))
    revocado_por = db.Column(db.Integer)
    huella = db.Column(db.String(64), nullable=False, unique=True)
    creado_por = db.Column(db.Integer, nullable=False)
    creado_en = db.Column(db.DateTime(timezone=True), server_default=func.now(), nullable=False)


class ConsultaIntegracion(db.Model):
    __tablename__ = 'integracion_consulta'
    __table_args__ = {'schema': 'public'}
    id = db.Column(db.String(36), primary_key=True)
    host = db.Column(db.String(253), nullable=False)
    usuario = db.Column(db.Integer, nullable=False)
    fecha = db.Column(db.DateTime(timezone=True), nullable=False, server_default=func.now())
    codigo = db.Column(db.Integer, nullable=False)
    resumen = db.Column(db.JSON)
    url = db.Column(db.String(2048))
    tipo = db.Column(db.String(15))
    id_local = db.Column(db.Integer)
    estado = db.Column(db.String(15))
    intentos = db.Column(db.Integer, nullable=False, default=0)
    ejecutar_en = db.Column(db.DateTime(timezone=True))
    mensaje = db.Column(db.Text)
    errores = db.Column(db.JSON)
    cursor = db.Column(db.Text)


def exigir_admin():
    token = get_jwt()
    perfil = token.get('id_perfil')
    usuario = get_jwt_identity()
    if token.get('tipo_token') != 'operativo' or type(perfil) is not int:
        raise Forbidden('Selecciona un perfil de administracion.')
    if not perfil_tiene_capacidad(perfil, 'administrar_globalmente'):
        raise Forbidden('Solo administracion puede revisar solicitudes.')
    if not db.session.scalar(select(func.public.auth_usuario_tiene_perfil(int(usuario), perfil))):
        raise Forbidden('El perfil ya no esta asignado.')
    return int(usuario)


def admin(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        verify_jwt_in_request()
        return view(exigir_admin(), *args, **kwargs)
    return wrapper


def configuracion_entrada():
    config = current_app.config
    clave = config.get('INTEGRACIONES_API_TOKEN', '')
    try:
        local = int(config.get('INTEGRACIONES_API_LOCAL') or 0)
    except (ValueError, TypeError):
        local = 0
    origen = config.get('INTEGRACIONES_API_ORIGEN')
    if len(clave) < 32 or local < 1 or not origen or len(origen) > 120:
        raise ServiceUnavailable('La entrada API no esta configurada.')
    return local, origen, clave


def identidad_externa():
    esquema, _, recibida = request.headers.get('Authorization', '').partition(' ')
    if esquema.lower() != 'bearer' or not 32 <= len(recibida) <= 256:
        raise Unauthorized('Clave API invalida.')
    try:
        local, origen, clave = configuracion_entrada()
    except ServiceUnavailable:
        pass
    else:
        if compare_digest(recibida.encode(), clave.encode()):
            return local, origen, 'ambos', None
    huella = sha256(recibida.encode()).hexdigest()
    conector = db.session.scalar(select(ClaveIntegracion).filter_by(huella=huella, revocado_en=None).where(
        (ClaveIntegracion.vence_en.is_(None)) | (ClaveIntegracion.vence_en > func.now())
    ))
    if conector is None:
        raise Unauthorized('Clave API invalida.')
    return conector.id_local, conector.origen, conector.permiso, conector.id


def estado(item):
    return {'id': item.id, 'estado': item.estado, 'id_registro': item.id_registro}


def detalle(item):
    return {
        **estado(item), 'id_local': item.id_local, 'origen': item.origen, 'tipo': item.tipo,
        'datos': item.datos, 'recibido_en': item.recibido_en.isoformat(),
        'revisado_en': item.revisado_en.isoformat() if item.revisado_en else None,
        'revisado_por': item.revisado_por, 'mensaje': item.mensaje, 'eventos': item.eventos,
    }


def seleccionar_campos(datos, campos):
    resultado = {}
    for campo in campos:
        if campo in datos:
            valor = datos[campo]
            if valor is not None and not isinstance(valor, str):
                raise BadRequest(f'{campo} debe ser texto.')
            resultado[campo] = valor
    return resultado


def datos_visibles(tipo, datos):
    if not isinstance(datos, dict):
        raise BadRequest('Envia un registro JSON.')
    campos = ('nombre', 'tipo_persona', 'tipo_documento', 'numero_documento', 'email', 'telefono', 'direccion')
    if tipo == 'clientes':
        return seleccionar_campos(datos, campos)
    comercial = datos.get('datos_comerciales')
    campos_proveedor = ('ruc', 'razon_social', 'nombre_comercial', 'direccion', 'telefono', 'email', 'contacto')
    resultado = seleccionar_campos(datos, ('nombre',))
    if resultado.get('nombre') is None:
        resultado.pop('nombre', None)
    if 'datos_comerciales' in datos:
        if not isinstance(comercial, dict):
            raise BadRequest('datos_comerciales debe ser un objeto JSON.')
        resultado['datos_comerciales'] = seleccionar_campos(comercial, campos_proveedor)
    return resultado


@bp.post('/entrada', defaults={'tipo': None})
@bp.post('/entrada/<tipo>')
def recibir(tipo):
    local, origen, permiso, _id = identidad_externa()
    if tipo not in (None, 'clientes', 'proveedores'):
        raise NotFound()
    clave = request.headers.get('Idempotency-Key', '').strip()
    if not clave or len(clave) > 128:
        raise BadRequest('Envia Idempotency-Key con un maximo de 128 caracteres.')
    request.max_content_length = 32 * 1024
    entrada = request.get_json()
    if tipo is None:
        if not isinstance(entrada, dict) or entrada.get('tipo') not in ('clientes', 'proveedores'):
            raise BadRequest('Indica tipo: clientes o proveedores, y envia el registro en datos.')
        tipo, entrada = entrada['tipo'], entrada.get('datos')
    if permiso not in ('ambos', tipo):
        raise Forbidden('La clave no tiene permiso para enviar este tipo de registro.')
    datos = datos_visibles(tipo, entrada)
    item = Solicitud(id=str(uuid4()), id_local=local, origen=origen, tipo=tipo, clave=clave, datos=datos)
    db.session.add(item)
    try:
        db.session.commit()
    except IntegrityError:
        db.session.rollback()
        anterior = db.session.scalar(select(Solicitud).filter_by(id_local=local, origen=origen, tipo=tipo, clave=clave))
        if anterior is None:
            raise
        if anterior.datos != datos:
            raise Conflict('La clave de solicitud ya se uso con otros datos.')
        item = anterior
    return jsonify(estado(item)), 202 if item.estado == 'PENDIENTE' else 200


@bp.get('/entrada/estado/<uuid:identidad>')
def seguimiento(identidad):
    local, origen, permiso, _id = identidad_externa()
    if permiso == 'leer_clientes':
        raise Forbidden('Esta clave es de lectura de clientes.')
    item = db.session.scalar(select(Solicitud).filter_by(id=str(identidad), id_local=local, origen=origen))
    if item is None:
        raise NotFound('Solicitud no encontrada.')
    return jsonify(estado(item))


@bp.get('/salida/clientes')
def salida_clientes():
    codigo = 200
    try:
        _local, _origen, permiso, id_clave = identidad_externa()
        if permiso != 'leer_clientes':
            raise Unauthorized('Clave de lectura de clientes invalida.')
        cursor = request.args.get('cursor', '')
        try:
            limite = int(request.args.get('limite', '50'))
            if not 1 <= limite <= 100 or any(len(request.args.getlist(k)) > 1 for k in ('limite', 'cursor')):
                raise ValueError
            if cursor:
                cursor_uuid = UUID(cursor)
                if str(cursor_uuid) != cursor:
                    raise ValueError
            else:
                cursor_uuid = None
        except ValueError:
            raise BadRequest('Indica un limite de 1 a 100 y un cursor valido.') from None
        permitido = db.session.scalar(select(func.public.integracion_consumir_lectura(id_clave)))
        db.session.commit()
        if not permitido:
            respuesta = jsonify(mensaje='Limite de solicitudes por minuto alcanzado.')
            codigo = 429
        else:
            filas = func.public.integracion_leer_clientes(cursor_uuid, limite + 1).table_valued(
                'id_cliente', 'nombre', 'tipo_persona', 'tipo_documento',
                'numero_documento', 'email', 'telefono', 'direccion',
            )
            registros = db.session.execute(select(filas).order_by(filas.c.id_cliente)).mappings().all()
            datos = []
            for registro in registros[:limite]:
                cliente = dict(registro)
                cliente['idCliente'] = f"BRB-{cliente.pop('id_cliente')}"
                canonico = json.dumps(cliente, sort_keys=True, ensure_ascii=False, separators=(',', ':'))
                datos.append({**cliente, 'version': sha256(canonico.encode('utf8')).hexdigest()})
            hay_mas = len(registros) > limite
            respuesta = jsonify(datos=datos, paginacion={
                'hayMas': hay_mas, 'siguienteCursor': str(registros[limite - 1]['id_cliente']) if hay_mas else None,
            })
    except (BadRequest, Unauthorized) as error:
        respuesta, codigo = jsonify(mensaje=error.description), error.code
    except SQLAlchemyError:
        db.session.rollback()
        respuesta, codigo = jsonify(mensaje='Directorio temporalmente no disponible.'), 503
    respuesta.headers['Cache-Control'] = 'no-store'
    if codigo == 429:
        respuesta.headers['Retry-After'] = str(60 - datetime.now(timezone.utc).second)
    return respuesta, codigo


def metadatos_clave(conector):
    return {
        'id': conector.id, 'nombre': conector.nombre, 'id_local': conector.id_local,
        'creado_en': conector.creado_en.isoformat(), 'creado_por': conector.creado_por,
        'revocado_en': conector.revocado_en.isoformat() if conector.revocado_en else None,
        'revocado_por': conector.revocado_por, 'permiso': conector.permiso,
        'vence_en': conector.vence_en.isoformat() if conector.vence_en else None,
    }


@bp.get('/mi-api/clave')
@admin
def listar_claves(_usuario):
    conectores = db.session.scalars(select(ClaveIntegracion)
                                    .order_by(ClaveIntegracion.creado_en.desc(), ClaveIntegracion.id)).all()
    respuesta = jsonify(claves=[metadatos_clave(conector) for conector in conectores])
    respuesta.headers['Cache-Control'] = 'no-store'
    return respuesta


@bp.post('/mi-api/clave')
@admin
def generar_clave(usuario):
    local = local_actual()
    request.max_content_length = 1024
    datos = request.get_json(silent=True)
    nombre = datos.get('nombre') if isinstance(datos, dict) else None
    if not isinstance(nombre, str) or not 1 <= len(nombre.strip()) <= 80 or not nombre.isprintable():
        raise BadRequest('Indica un nombre de programa de hasta 80 caracteres.')
    permiso = datos.get('permiso', 'ambos')
    vigencia = datos.get('vigencia_dias')
    if permiso not in ('clientes', 'proveedores', 'ambos', 'leer_clientes'):
        raise BadRequest('Selecciona un permiso valido.')
    if vigencia is not None and (type(vigencia) is not int or not 1 <= vigencia <= 365):
        raise BadRequest('Indica una vigencia de 1 a 365 dias.')
    vence = datetime.now(timezone.utc) + timedelta(days=vigencia) if vigencia is not None else None
    nombre = nombre.strip()
    clave = token_urlsafe(32)
    identidad = str(uuid4())
    conector = ClaveIntegracion(
        id=identidad, id_local=local, nombre=nombre, origen=f'{nombre} ({identidad})',
        huella=sha256(clave.encode()).hexdigest(), creado_por=usuario, permiso=permiso, vence_en=vence,
    )
    db.session.add(conector)
    db.session.commit()
    respuesta = jsonify(**metadatos_clave(conector), clave=clave)
    respuesta.headers['Cache-Control'] = 'no-store'
    return respuesta, 201


@bp.delete('/mi-api/clave/<uuid:identidad>')
@admin
def revocar_clave(usuario, identidad):
    conector = db.session.scalar(select(ClaveIntegracion).filter_by(
        id=str(identidad),
    ).with_for_update())
    if conector is None:
        raise NotFound('No se encontro esa clave.')
    if conector.revocado_en is None:
        conector.revocado_en = datetime.now(timezone.utc)
        conector.revocado_por = usuario
        db.session.commit()
    return jsonify(metadatos_clave(conector))


@bp.get('/historial/consultas')
@admin
def historial_consultas(_usuario):
    pagina = request.args.get('pagina', 1, type=int)
    if not 1 <= pagina <= 100000:
        raise BadRequest('Pagina no valida.')
    seleccion = select(ConsultaIntegracion)
    if request.args.get('activas') == '1':
        seleccion = seleccion.where(ConsultaIntegracion.estado.in_(('EN_COLA', 'REINTENTO')))
    filas = db.session.scalars(seleccion.order_by(ConsultaIntegracion.fecha.desc(), ConsultaIntegracion.id.desc())
        .offset((pagina - 1) * 25).limit(26)).all()
    ids = [fila.id for fila in filas[:25]]
    conteos = {}
    if ids:
        for consulta_id, estado_item, cantidad in db.session.execute(
            select(Solicitud.consulta_id, Solicitud.estado, func.count()).where(
                Solicitud.consulta_id.in_(ids)
            ).group_by(Solicitud.consulta_id, Solicitud.estado)
        ):
            conteos.setdefault(consulta_id, {})[estado_item] = cantidad
    return jsonify(consultas=[{
        'id': fila.id, 'host': fila.host, 'usuario': fila.usuario,
        'fecha': fila.fecha.isoformat(), 'codigo': fila.codigo, 'resumen': fila.resumen,
        'estado': fila.estado or ('RESPONDIO' if fila.codigo == 200 else 'FALLIDA'),
        'intentos': fila.intentos, 'mensaje': fila.mensaje,
        'reintentar_en': fila.ejecutar_en.isoformat() if fila.estado == 'REINTENTO' else None, 'errores': fila.errores or [],
        'tiene_siguiente': bool(fila.cursor), 'registros': conteos.get(fila.id, {}),
    } for fila in filas[:25]], hay_mas=len(filas) > 25)


@bp.post('/consultar')
@admin
def consultar_externa(usuario):
    request.max_content_length = 8192
    entrada = request.get_json()
    if not isinstance(entrada, dict):
        raise BadRequest('Indica la URL del recurso del otro programa.')
    url, tipo = entrada.get('url'), entrada.get('tipo')
    anterior_id = entrada.get('anterior')
    if anterior_id is not None:
        if not isinstance(anterior_id, str) or len(anterior_id) != 36:
            raise BadRequest('Identificador de consulta no valido.')
        anterior = db.session.get(ConsultaIntegracion, anterior_id)
        if anterior is None or not anterior.cursor or not anterior.url:
            raise NotFound('La consulta no tiene una pagina siguiente.')
        partes = urlsplit(anterior.url)
        parametros = [(nombre, valor) for nombre, valor in parse_qsl(partes.query, keep_blank_values=True)
                      if nombre != 'cursor']
        url = partes._replace(query=urlencode([*parametros, ('cursor', anterior.cursor)])).geturl()
        tipo = anterior.tipo
    if not isinstance(url, str) or not 1 <= len(url) <= 2048:
        raise BadRequest('Ingresa una URL valida.')
    if tipo not in (None, 'clientes', 'proveedores'):
        raise BadRequest('El tipo de la lista es invalido.')
    destino, host = external.url_https(url)
    trabajo = ConsultaIntegracion(id=str(uuid4()), host=host, usuario=usuario, url=destino.geturl(),
        tipo=tipo, id_local=local_actual(), estado='EN_COLA', codigo=0, ejecutar_en=func.now())
    db.session.add(trabajo)
    db.session.commit()
    return jsonify(id=trabajo.id, estado=trabajo.estado), 202


def ejecutar_consulta(trabajo):
    url, tipo, usuario, local = trabajo.url, trabajo.tipo, trabajo.usuario, trabajo.id_local
    destino = urlsplit(url)
    es_acadesys = destino.hostname == 'acadesys-api.onrender.com' and acadesys.corresponde(destino.path)
    token = current_app.config.get('ACADESYS_API_TOKEN', '') if es_acadesys else ''
    if es_acadesys and not token:
        raise ServiceUnavailable('Falta configurar la clave de lectura de AcadeSys en el servidor.')
    host, ruta, resultado = external.consultar(url, token)
    if es_acadesys:
        colecciones, cursor = acadesys.leer(resultado)
    else:
        colecciones, cursor = external.separar(resultado, tipo), None
    origen = host[:120]
    resumen = {}
    errores = []
    for nombre, filas in colecciones.items():
        resumen[nombre] = {'recibidos': len(filas), 'nuevos': 0, 'repetidos': 0, 'invalidos': 0}
        for indice, fila in enumerate(filas, 1):
            try:
                if es_acadesys:
                    cliente, identidad, version = acadesys.mapear(fila)
                    datos = clientes.validar(cliente)
                    datos['acadesys'] = {'idCliente': identidad, 'version': version}
                    identificador = [host, 'acadesys', identidad, version]
                else:
                    datos = datos_visibles(nombre, fila)
                    identificador = [host, ruta, datos]
                if not datos:
                    raise BadRequest('El registro no contiene campos reconocidos.')
            except BadRequest as error:
                resumen[nombre]['invalidos'] += 1
                errores.append({'tipo': nombre, 'fila': indice, 'mensaje': error.description})
                continue
            huella = json.dumps(identificador, sort_keys=True, ensure_ascii=True, separators=(',', ':'))
            clave = 'consulta:' + sha256(huella.encode()).hexdigest()
            try:
                with db.session.begin_nested():
                    db.session.add(Solicitud(id=str(uuid4()), id_local=local, origen=origen, tipo=nombre,
                                             clave=clave, datos=datos, consulta_id=trabajo.id, eventos=[{
                                                 'usuario': usuario, 'fecha': datetime.now(timezone.utc).isoformat(),
                                                 'accion': 'consultar', 'estado': 'PENDIENTE',
                                                 'mensaje': 'Recibido desde la API externa.',
                                             }]))
            except IntegrityError:
                previo = db.session.scalar(select(Solicitud.id).filter_by(
                    id_local=local, origen=origen, tipo=nombre, clave=clave))
                if previo is None:
                    raise
                resumen[nombre]['repetidos'] += 1
            else:
                resumen[nombre]['nuevos'] += 1
    return resumen, errores, cursor


def procesar_consulta():
    trabajo = db.session.scalar(select(ConsultaIntegracion).where(
        ConsultaIntegracion.estado.in_(('EN_COLA', 'REINTENTO')),
        ConsultaIntegracion.ejecutar_en <= func.now(),
    ).order_by(ConsultaIntegracion.ejecutar_en, ConsultaIntegracion.id).limit(1)
      .with_for_update(skip_locked=True))
    if trabajo is None:
        db.session.rollback()
        return False
    trabajo.intentos += 1
    try:
        with db.session.begin_nested():
            trabajo.resumen, trabajo.errores, trabajo.cursor = ejecutar_consulta(trabajo)
    except HTTPException as error:
        trabajo.codigo = error.code
        trabajo.mensaje = error.description
        if isinstance(error, (external.FalloTemporal, external.GatewayTimeout)) and trabajo.intentos < 3:
            trabajo.estado = 'REINTENTO'
            trabajo.ejecutar_en = datetime.now(timezone.utc) + timedelta(seconds=30 * trabajo.intentos)
        else:
            trabajo.estado = 'FALLIDA'
            trabajo.ejecutar_en = None
            trabajo.url = None
    else:
        trabajo.estado, trabajo.codigo, trabajo.mensaje = 'RESPONDIO', 200, None
        trabajo.ejecutar_en = None
        if not trabajo.cursor:
            trabajo.url = None
    db.session.commit()
    return True


@bp.get('/bandeja')
@admin
def bandeja(_usuario):
    filtro = request.args.get('estado', 'PENDIENTE')
    pagina = request.args.get('pagina', 1, type=int)
    if filtro not in ('PENDIENTE', 'ERROR', 'AGREGADO', 'DESCARTADO', 'TODOS') or pagina < 1:
        raise BadRequest('Filtro o pagina no validos.')
    tipo = request.args.get('tipo')
    if tipo not in (None, 'clientes', 'proveedores'):
        raise BadRequest('Tipo de registros no valido.')
    seleccion = select(Solicitud)
    if tipo:
        seleccion = seleccion.filter_by(tipo=tipo)
    if filtro != 'TODOS':
        seleccion = seleccion.filter_by(estado=filtro)
    filas = db.session.scalars(seleccion.order_by(Solicitud.recibido_en.desc(), Solicitud.id.desc())
                              .offset((pagina - 1) * 25).limit(26)).all()
    categorias = catalogo.listar_categorias_producto() if any(f.tipo == 'proveedores' for f in filas[:25]) else []
    return jsonify(solicitudes=[detalle(f) for f in filas[:25]], hay_mas=len(filas) > 25,
                   categorias=[dict(c) for c in categorias if c['activo']])


@bp.post('/bandeja/<uuid:identidad>')
@admin
def revisar(usuario, identidad):
    datos = request.get_json()
    if not isinstance(datos, dict) or datos.get('accion') not in ('agregar', 'descartar'):
        raise BadRequest('Elige agregar o descartar.')
    item = db.session.scalar(select(Solicitud).filter_by(id=str(identidad)).with_for_update())
    if item is None:
        raise NotFound('Solicitud no encontrada.')
    if item.estado not in ('PENDIENTE', 'ERROR'):
        raise Conflict('La solicitud ya fue resuelta.')
    item.revisado_por = usuario
    item.revisado_en = datetime.now(timezone.utc)
    if datos['accion'] == 'descartar':
        item.estado, item.mensaje = 'DESCARTADO', 'Descartado por administracion.'
    else:
        try:
            with db.session.begin_nested():
                if item.tipo == 'clientes':
                    referencia = item.datos.get('acadesys')
                    if referencia:
                        identidad_externa = referencia['idCliente']
                        bloqueo = f'acadesys:{item.origen}:{identidad_externa}'
                        db.session.execute(select(func.pg_advisory_xact_lock(func.hashtextextended(bloqueo, 0))))
                        agregado = db.session.scalar(select(Solicitud.id).filter_by(
                            origen=item.origen, tipo='clientes', estado='AGREGADO',
                        ).where(Solicitud.datos['acadesys']['idCliente'].as_string() == identidad_externa).limit(1))
                        if agregado:
                            raise Conflict('Este alumno ya fue incorporado desde AcadeSys. Revisa el cliente existente.')
                    resultado = clientes.crear(item.id_local, item.datos, commit=False)
                    registro = resultado['id_cliente']
                else:
                    proveedor = {**item.datos, 'ids_categorias': datos.get('ids_categorias')}
                    resultado, codigo = crear_proveedor_catalogo(usuario, proveedor, commit=False)
                    if codigo != 201:
                        raise BadRequest(resultado['mensaje'])
                    registro = resultado['id_proveedor']
            item.id_registro = str(registro)
            item.estado, item.mensaje = 'AGREGADO', 'Registro incorporado.'
        except (BadRequest, Conflict) as error:
            item.estado, item.mensaje = 'ERROR', error.description
        except IntegrityError:
            item.estado, item.mensaje = 'ERROR', 'El registro ya existe o no cumple las restricciones del catalogo.'
    item.eventos = [*item.eventos, {
        'usuario': usuario, 'fecha': item.revisado_en.isoformat(), 'accion': datos['accion'],
        'estado': item.estado, 'mensaje': item.mensaje,
    }]
    db.session.commit()
    return jsonify(detalle(item))

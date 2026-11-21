from functools import wraps
from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, verify_jwt_in_request
from werkzeug.exceptions import BadRequest, Forbidden, NotFound
from app.core.local_scope import local_actual
from app.modules.salon.salon import validar_sesion_salon
from .service import buscar, crear, obtener

clientes_bp=Blueprint('clientes',__name__)
salon_clientes_bp=Blueprint('salon_clientes',__name__)


def acceso(func):
    @wraps(func)
    def wrapper(*args,**kwargs):
        verify_jwt_in_request()
        if get_jwt().get('tipo_token') == 'salon':
            session = validar_sesion_salon()
            if session['perfil'] not in (2,3):
                raise Forbidden('El perfil activo no tiene acceso al directorio de clientes')
            return func(session['id_local'],*args,**kwargs)
        if get_jwt().get('id_perfil') not in (1,2,3):
            raise Forbidden('El perfil activo no tiene acceso al directorio de clientes')
        return func(local_actual(),*args,**kwargs)
    return wrapper


@clientes_bp.get('/configuracion')
@acceso
def configuracion(local):
    import os
    from app.core.extensions import db
    from sqlalchemy import text
    directory=bool(db.session.execute(text("SELECT to_regclass('public.cliente_comercial') IS NOT NULL")).scalar())
    return jsonify(directorio_disponible=directory,consulta_identidad_externa=bool(os.getenv('FACTILIZA_TOKEN','').strip()))


@clientes_bp.get('')
@acceso
def listar(local):
    try:
        limit=int(request.args.get('limit','25'))
        offset=int(request.args.get('offset','0'))
    except ValueError:
        raise BadRequest('Paginacion invalida')
    q=request.args.get('q','').strip()
    if not 1<=limit<=100 or offset<0 or offset>1000000 or len(q)>200:
        raise BadRequest('Parametros de busqueda invalidos')
    return jsonify({'clientes':buscar(local,q,limit,offset),'limit':limit,'offset':offset})


@clientes_bp.post('')
@acceso
def registrar(local):
    return jsonify(crear(local,request.get_json(silent=True))),201


@clientes_bp.post('/consultar-documento')
@acceso
def consultar_documento(local):
    from .identity import consultar
    data=request.get_json(silent=True) or {}
    if not isinstance(data,dict):raise BadRequest('Datos de consulta invalidos')
    response=jsonify(consultar(data.get('tipo_documento'),data.get('numero_documento')))
    response.headers['Cache-Control']='no-store'
    return response


@clientes_bp.get('/<uuid:id_cliente>')
@acceso
def detalle(local,id_cliente):
    cliente=obtener(local,id_cliente)
    if cliente is None:
        raise NotFound('Cliente no encontrado en este local')
    return jsonify(cliente)


salon_clientes_bp.add_url_rule('/clientes/configuracion',view_func=configuracion,methods=['GET'])
salon_clientes_bp.add_url_rule('/clientes',view_func=listar,methods=['GET'])
salon_clientes_bp.add_url_rule('/clientes',view_func=registrar,methods=['POST'])
salon_clientes_bp.add_url_rule('/clientes/consultar-documento',view_func=consultar_documento,methods=['POST'])
salon_clientes_bp.add_url_rule('/clientes/<uuid:id_cliente>',view_func=detalle,methods=['GET'])


from sqlalchemy.exc import ProgrammingError

@clientes_bp.errorhandler(ProgrammingError)
@salon_clientes_bp.errorhandler(ProgrammingError)
def database_unavailable(error):
    from app.core.extensions import db
    db.session.rollback()
    return jsonify(mensaje='El directorio de clientes necesita aplicar la migracion local.'),503

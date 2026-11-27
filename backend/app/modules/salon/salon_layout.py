"""Distribucion de salon por local, administrada por el gerente."""
import json
import math
import re
from flask import Blueprint, jsonify, request
from flask_jwt_extended import jwt_required, get_jwt, get_jwt_identity
from sqlalchemy import bindparam, func, select
from werkzeug.exceptions import Forbidden, BadRequest, Conflict
from app.core.profile_capabilities import perfil_tiene_capacidad
from app.core.extensions import db
from app.core.local_scope import local_actual
from app.modules.salon.salon import validar_sesion_salon
from app.modules.auditoria.service import registrar_actividad

salon_layout_bp=Blueprint('salon_layout',__name__)

def predeterminado():
    elementos = db.session.execute(select(func.public.salon_distribucion_predeterminada())).scalar_one()
    return {'version': 0, 'elementos': elementos}


def existe():
    return db.session.execute(select(func.public.salon_distribucion_instalada())).scalar()

def leer(local):
    if existe():
        fila=db.session.execute(select(func.public.salon_distribucion(bindparam('local')).table_valued(
            'version', 'elementos',
        )),{'local':local}).mappings().first()
        if fila:return dict(fila)
    return predeterminado()

def validar(datos):
    if not isinstance(datos,dict) or type(datos.get('version')) is not int:raise BadRequest('Version invalida')
    elementos=datos.get('elementos')
    if not isinstance(elementos,list) or not 1<=len(elementos)<=150:raise BadRequest('Agrega entre 1 y 150 elementos')
    codigos=set()
    for e in elementos:
        if not isinstance(e,dict):raise BadRequest('Elemento invalido')
        tipo=e.get('tipo'); codigo=e.get('codigo')
        patron={'mesa':r'M[0-9]{2,3}','puesto':r'B[0-9]{2,3}','barra':r'BARRA'}
        if tipo not in patron or not isinstance(codigo,str) or not re.fullmatch(patron[tipo],codigo) or codigo in codigos:raise BadRequest('Tipo o codigo de mesa invalido o repetido')
        codigos.add(codigo)
        for k in ('x','y','ancho','alto'):
            v=e.get(k)
            if type(v) not in (int,float) or not math.isfinite(v):raise BadRequest('Posicion o tamano invalido')
        if min(e['x'],e['y'])<0 or min(e['ancho'],e['alto'])<4 or e['x']+e['ancho']>100 or e['y']+e['alto']>100:raise BadRequest('Los elementos deben quedar dentro del mapa')
    if any(e['tipo']=='puesto' for e in elementos) and 'BARRA' not in codigos:raise BadRequest('Los puestos necesitan una barra')
    return [{k:e[k] for k in ('codigo','tipo','x','y','ancho','alto')} for e in elementos]

def gerente():
    if not perfil_tiene_capacidad(get_jwt().get('id_perfil'), 'administrar_salon'):raise Forbidden('Solo el perfil Gerente puede administrar el salon')
    return local_actual()

@salon_layout_bp.get('/distribucion')
@jwt_required()
def consultar():
    local=validar_sesion_salon()['id_local'] if get_jwt().get('tipo_token')=='salon' else gerente()
    return jsonify(leer(local))

@salon_layout_bp.put('/distribucion')
@jwt_required()
def guardar():
    local=gerente()
    if not existe():raise Conflict('Ejecuta 20260923_distribucion_salon.sql')
    datos=request.get_json(silent=True); elementos=validar(datos)
    try:
        db.session.execute(select(func.public.salon_bloqueo(bindparam('clave'))),{'clave':f'salon-layout:{local}'})
        anterior=leer(local)
        if anterior['version']!=datos['version']:raise Conflict('La distribucion cambio. Recarga antes de editar.')
        disponibles={e['codigo'] for e in elementos if e['tipo']!='barra'}
        if db.session.execute(select(func.public.salon_pedidos_instalados())).scalar():
            consulta_mesas=func.public.salon_mesas_usadas if db.session.execute(select(func.public.salon_control_instalado())).scalar() else func.public.salon_mesas_usadas_anteriores
            usadas=set(db.session.execute(select(consulta_mesas(bindparam('local')).table_valued(
                'mesa',
            )),{'local':local}).scalars())
            if usadas-disponibles:raise Conflict('No puedes quitar mesas con pedidos registrados: '+', '.join(sorted(usadas-disponibles)))
        db.session.execute(select(func.public.salon_guardar_distribucion(bindparam('local'), bindparam('elementos'))),{'local':local,'elementos':json.dumps(elementos)})
        registrar_actividad(get_jwt_identity(),'SALON','EDITAR_DISTRIBUCION',local,'Actualizo la distribucion del salon',id_perfil_utilizado=get_jwt().get('id_perfil'),id_local=local)
        db.session.commit()
        return jsonify(leer(local))
    except Exception:
        db.session.rollback();raise

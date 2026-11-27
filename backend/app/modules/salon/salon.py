"""PIN independiente: emite tokens que no habilitan las API de gestión."""
import hashlib
import re
from datetime import timedelta
from flask import Blueprint, jsonify, request
from flask_jwt_extended import create_access_token, get_jwt, get_jwt_identity, jwt_required
from sqlalchemy import bindparam, func, select
from werkzeug.exceptions import BadRequest, Conflict, Forbidden
from werkzeug.security import generate_password_hash, check_password_hash
from app.core.extensions import db

salon_bp=Blueprint('salon',__name__)

def perfil_salon(usuario):
    return db.session.execute(select(func.public.salon_perfil(bindparam('id'))),{'id':usuario}).scalar()



def disponible():
    return bool(db.session.execute(select(func.public.salon_pin_instalado())).scalar())


def exigir():
    if not disponible():
        raise Conflict('Falta ejecutar database/migrations/20260923_acceso_salon.sql')


def guardar_pin(usuario, datos):
    pin=datos.get('pin_salon','')
    revocar=datos.get('revocar_pin_salon',False)
    if not isinstance(pin,str) or (pin and not re.fullmatch(r'[0-9]{4}',pin)) or type(revocar) is not bool:
        raise BadRequest('El PIN de Salón debe contener exactamente 4 dígitos')
    if not disponible():
        if pin or revocar: exigir()
        return
    elegible=db.session.execute(select(func.public.salon_elegible(bindparam('id'))),{'id':usuario}).scalar()
    if pin and not elegible:
        raise BadRequest('El PIN requiere gerente, supervisor o miembro mesero/bartender')
    if pin and revocar:
        raise BadRequest('Elige asignar o revocar el PIN')
    if revocar or not elegible:
        db.session.execute(select(func.public.salon_eliminar_pin(bindparam('id'))),{'id':usuario})
    elif pin:
        db.session.execute(select(func.public.salon_guardar_pin(bindparam('id'), bindparam('hash'))),
          {'id':usuario,'hash':generate_password_hash(pin)})


@salon_bp.get('/opciones')
def opciones():
    exigir()
    locales=db.session.execute(select(func.public.salon_locales().table_valued(
        'id_local', 'nombre',
    ))).mappings().all()
    try: local=int(request.args.get('local','0'))
    except ValueError: raise BadRequest('Local inválido')
    usuarios=db.session.execute(select(func.public.salon_usuarios(bindparam('local')).table_valued(
        'id_usuario', 'nombre',
    )),{'local':local}).mappings().all()
    return jsonify(locales=[dict(l) for l in locales],usuarios=[dict(u) for u in usuarios])


@salon_bp.post('/login')
def login_salon():
    exigir()
    datos=request.get_json(silent=True)
    if not isinstance(datos,dict): raise BadRequest('Datos inválidos')
    pin=datos.get('pin','')
    if type(datos.get('id_usuario')) is not int or type(datos.get('id_local')) is not int or not isinstance(pin,str) or not re.fullmatch(r'[0-9]{4}',pin):
        raise BadRequest('Selecciona local y usuario e ingresa los 4 dígitos')
    # Se limita por conexión, sin confiar en cabeceras de proxy suministradas por clientes.
    origen=hashlib.sha256((request.remote_addr or 'desconocido').encode()).hexdigest()
    db.session.execute(select(func.public.salon_limpiar_intentos()))
    intentos=db.session.execute(select(func.public.salon_incrementar_intentos(bindparam('origen'))),{'origen':origen}).scalar_one()
    if intentos>15:
        db.session.commit()
        return jsonify(mensaje='Demasiados intentos. Espera 5 minutos.'),429
    fila=db.session.execute(select(func.public.salon_verificar_pin(bindparam('usuario'), bindparam('local')).table_valued(
        'id_usuario', 'pin_hash', 'version', 'fallos', 'bloqueado_hasta', 'actualizado_en', 'nombres',
        'local', 'bloqueado',
    )),
        {'usuario':datos['id_usuario'],'local':datos['id_local']}).mappings().first()
    if not fila or fila['bloqueado'] or not check_password_hash(fila['pin_hash'],pin):
        if fila and not fila['bloqueado']:
            db.session.execute(select(func.public.salon_fallo_pin(bindparam('id'))),{'id':datos['id_usuario']})
        db.session.commit()
        return jsonify(mensaje='No se pudo acceder. Revisa los datos o espera si agotaste los intentos.'),401
    db.session.execute(select(func.public.salon_reiniciar_pin(bindparam('id'))),{'id':fila['id_usuario']})
    token=create_access_token(identity=str(fila['id_usuario']),expires_delta=timedelta(hours=2),additional_claims={
        'tipo_token':'salon','id_local':datos['id_local'],'pin_version':fila['version'],
        'pin_actualizado':fila['actualizado_en'].isoformat()})
    db.session.commit()
    return jsonify(token=token)


def validar_sesion_salon():
    jwt=get_jwt()
    if jwt.get('tipo_token')!='salon': raise Forbidden('Esta sesión no pertenece a Salón')
    exigir()
    fila=db.session.execute(select(func.public.salon_sesion(bindparam('usuario'), bindparam('local')).table_valued(
        'nombres', 'local', 'version', 'actualizado_en',
    )),
        {'usuario':get_jwt_identity(),'local':jwt.get('id_local')}).mappings().first()
    if not fila or fila['version']!=jwt.get('pin_version') or fila['actualizado_en'].isoformat()!=jwt.get('pin_actualizado'):
        raise Forbidden('El acceso de Salón fue revocado. Inicia sesión nuevamente.')
    return {'usuario':fila['nombres'],'local':fila['local'],'id_usuario':int(get_jwt_identity()),'id_local':jwt['id_local'],'perfil':perfil_salon(int(get_jwt_identity()))}


@salon_bp.get('/me')
@jwt_required()
def sesion_salon():
    return jsonify(validar_sesion_salon())

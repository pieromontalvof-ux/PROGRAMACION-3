"""Administración de tiendas; no copia datos operativos de otras sedes."""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from app.core.profile_capabilities import perfil_tiene_capacidad
from app.core.extensions import db
from app.core.permissions import requiere_permiso
from app.modules.auditoria.service import registrar_actividad

locales_bp = Blueprint('locales', __name__)
COLUMNAS_LOCAL = ('id_local', 'codigo', 'nombre', 'direccion', 'estado_registro')


def validar(datos):
    if not isinstance(datos, dict) or set(datos) != {'nombre', 'direccion'}:
        raise ValueError('Completa nombre y dirección. El código se asigna automáticamente.')
    if any(not isinstance(v, str) for v in datos.values()):
        raise ValueError('Los datos de la tienda deben ser texto.')
    datos = {k: v.strip() for k, v in datos.items()}
    if not 1 <= len(datos['nombre']) <= 100 or not 1 <= len(datos['direccion']) <= 250:
        raise ValueError('Indica un nombre de hasta 100 caracteres y una dirección de hasta 250.')
    return datos


def siguiente_codigo():
    # El bloqueo se mantiene hasta commit, también frente a eliminaciones concurrentes.
    db.session.execute(select(func.public.usuarios_bloquear_locales()))
    return db.session.execute(select(func.public.usuarios_siguiente_codigo_local())).scalar_one()


@locales_bp.get('')
@requiere_permiso(id_opcion_menu='usuarios', accion='consultar')
def listar():
    if not perfil_tiene_capacidad(get_jwt().get('id_perfil'), 'administrar_globalmente'):
        return jsonify(mensaje='Solo el Administrador puede gestionar tiendas.'), 403
    locales = func.public.usuarios_listar_locales().table_valued(*COLUMNAS_LOCAL)
    rows = db.session.execute(select(locales)).mappings().all()
    return jsonify(locales=[dict(r) for r in rows])


@locales_bp.post('')
@requiere_permiso(id_opcion_menu='usuarios', accion='crear')
def crear():
    if not perfil_tiene_capacidad(get_jwt().get('id_perfil'), 'administrar_globalmente'):
        return jsonify(mensaje='Solo el Administrador puede crear tiendas.'), 403
    try:
        datos = validar(request.get_json(silent=True))
    except ValueError as error:
        return jsonify(mensaje=str(error)), 400
    try:
        datos['codigo'] = siguiente_codigo()
        usuario = int(get_jwt_identity())
        creado = func.public.usuarios_crear_local(
            datos['codigo'], datos['nombre'], datos['direccion'], usuario,
        ).table_valued(*COLUMNAS_LOCAL)
        local = db.session.execute(select(creado)).mappings().one()
        registrar_actividad(usuario, 'LOCALES', 'CREAR', local['id_local'],
                            'Creó la tienda ' + local['nombre'])
        db.session.commit()
        return jsonify(mensaje='Tienda creada. Asigna su gerente desde Usuarios.', local=dict(local)), 201
    except IntegrityError:
        db.session.rollback()
        return jsonify(mensaje='No se pudo crear la tienda. Verifica que el código sea único.'), 409
    except Exception:
        db.session.rollback()
        raise


def modificar(identidad, accion):
    if not perfil_tiene_capacidad(get_jwt().get('id_perfil'), 'administrar_globalmente'):
        return jsonify(mensaje='Solo el Administrador puede gestionar tiendas.'), 403
    try:
        datos = validar(request.get_json(silent=True)) if accion == 'EDITAR' else {}
        if accion == 'ESTADO':
            payload = request.get_json(silent=True)
            if not isinstance(payload, dict) or set(payload) != {'estado_registro'} or type(payload['estado_registro']) is not int or payload['estado_registro'] not in (0, 1):
                raise ValueError('Indica un estado válido para la tienda.')
            datos = payload
    except ValueError as error:
        return jsonify(mensaje=str(error)), 400
    try:
        db.session.execute(select(func.public.usuarios_bloquear_locales()))
        bloqueado = func.public.usuarios_bloquear_local(identidad).table_valued(
            *COLUMNAS_LOCAL, 'fecha_creacion', 'usuario_creacion', 'fecha_modificacion', 'usuario_modificacion',
        )
        anterior = db.session.execute(select(bloqueado)).mappings().first()
        if anterior is None:
            db.session.rollback()
            return jsonify(mensaje='La tienda ya no existe.'), 404
        if accion == 'ELIMINAR' or (accion == 'ESTADO' and datos['estado_registro'] == 0):
            if anterior['estado_registro'] == 1 and db.session.execute(select(func.public.usuarios_total_locales_activos())).scalar_one() <= 1:
                db.session.rollback()
                return jsonify(mensaje='Debes conservar al menos una tienda activa.'), 409
            if get_jwt().get('id_local') == identidad:
                db.session.rollback()
                return jsonify(mensaje='Cambia el local activo antes de desactivar o eliminar esta tienda.'), 409
        if accion == 'ELIMINAR':
            # Revisa incluso relaciones CASCADE: nunca elimina datos asociados.
            tiene_datos = db.session.execute(select(func.public.usuarios_local_tiene_datos(identidad))).scalar_one()
            if tiene_datos:
                db.session.rollback()
                return jsonify(mensaje='Esta tienda tiene usuarios, configuraciones o historial asociado. Puedes desactivarla para conservar sus datos.'), 409
            db.session.execute(select(func.public.usuarios_eliminar_local(identidad)))
            resultado = None
        else:
            usuario = int(get_jwt_identity())
            if accion == 'EDITAR':
                actualizado = func.public.usuarios_editar_local(identidad, datos['nombre'], datos['direccion'], usuario)
            else:
                actualizado = func.public.usuarios_estado_local(identidad, datos['estado_registro'], usuario)
            resultado = dict(db.session.execute(select(actualizado.table_valued(*COLUMNAS_LOCAL))).mappings().one())
        from app.modules.auditoria.service import registrar_cambio
        usuario = int(get_jwt_identity())
        registrar_cambio(usuario, 'LOCALES', accion, 'local', identidad, dict(anterior), resultado)
        registrar_actividad(usuario, 'LOCALES', accion, identidad, f'{accion}: tienda {anterior["nombre"]}')
        db.session.commit()
        return jsonify(mensaje={'EDITAR': 'Tienda actualizada.', 'ESTADO': 'Estado de la tienda actualizado.', 'ELIMINAR': 'Tienda eliminada.'}[accion], local=resultado)
    except IntegrityError:
        db.session.rollback()
        return jsonify(mensaje='No se pudo guardar: código duplicado o tienda con datos asociados.'), 409
    except Exception:
        db.session.rollback()
        raise


@locales_bp.put('/<int:identidad>')
@requiere_permiso(id_opcion_menu='usuarios', accion='editar')
def editar(identidad):
    return modificar(identidad, 'EDITAR')


@locales_bp.patch('/<int:identidad>/estado')
@requiere_permiso(id_opcion_menu='usuarios', accion='editar')
def estado(identidad):
    return modificar(identidad, 'ESTADO')


@locales_bp.delete('/<int:identidad>')
@requiere_permiso(id_opcion_menu='usuarios', accion='eliminar')
def eliminar(identidad):
    return modificar(identidad, 'ELIMINAR')

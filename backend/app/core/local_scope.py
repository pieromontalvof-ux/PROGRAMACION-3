"""Acceso a operaciones del local activo; los catalogos siguen siendo globales."""
from flask import g
from flask_jwt_extended import get_jwt, get_jwt_identity
from sqlalchemy import func, select
from werkzeug.exceptions import Conflict, Forbidden, NotFound

from app.core.extensions import db


def local_actual():
    if hasattr(g, 'local_operativo'):
        return g.local_operativo
    token = get_jwt()
    local = token.get('id_local')
    perfil = token.get('id_perfil')
    if (token.get('tipo_token') != 'operativo' or type(local) is not int
            or local <= 0 or type(perfil) is not int):
        raise Forbidden('La sesion no contiene un local valido')
    try:
        usuario = int(get_jwt_identity())
    except (TypeError, ValueError):
        raise Forbidden('La sesion no contiene un usuario valido') from None
    autorizado = db.session.execute(select(func.public.local_permitido(usuario, perfil, local))).scalar()
    if not autorizado:
        raise Forbidden('Ya no tienes acceso al local o perfil activo')
    g.local_operativo = local
    return local


def exigir_migracion_locales():
    if not getattr(g, 'operaciones_por_local_listas', False):
        lista = db.session.execute(select(func.public.operaciones_por_local_listas())).scalar()
        if not lista:
            raise Conflict('Las operaciones por local requieren actualizar la base de datos. '
                           'Los catalogos siguen disponibles.')
        g.operaciones_por_local_listas = True


def ejecutar_local(consulta, parametros=None):
    local = local_actual()
    exigir_migracion_locales()
    return db.session.execute(consulta, {**(parametros or {}), 'id_local_actual': local})


def exigir_registro_local(tipo, identidad):
    local = local_actual()
    exigir_migracion_locales()
    existe = db.session.execute(select(func.public.registro_de_local(tipo, identidad, local))).scalar()
    if not existe:
        raise NotFound('El registro no existe en el local activo')

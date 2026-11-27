from flask import g, has_request_context
from sqlalchemy import func, select

from app.core.extensions import db


def perfil_tiene_capacidad(id_perfil, capacidad):
    try:
        id_perfil = int(id_perfil)
    except (TypeError, ValueError):
        return False

    consulta = select(func.public.perfil_tiene_capacidad(id_perfil, capacidad))
    if not has_request_context():
        return bool(db.session.execute(consulta).scalar())

    capacidades = g.setdefault('capacidades_perfil', {})
    clave = id_perfil, capacidad
    if clave not in capacidades:
        capacidades[clave] = bool(db.session.execute(consulta).scalar())
    return capacidades[clave]

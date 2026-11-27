import json

from flask_jwt_extended import get_jwt
from app.core.profile_capabilities import perfil_tiene_capacidad
from app.core.local_scope import local_actual

from sqlalchemy import func, select

from app.core.extensions import db


def insertar_actividad(
    id_usuario: int,
    modulo: str,
    accion: str,
    id_registro_afectado: int | None,
    descripcion: str,
    id_perfil_utilizado: int | None = None,
    id_puesto_laboral: int | None = None,
    id_local: int | None = None,
):
    alta = func.public.auditoria_insertar_actividad(
        id_usuario, modulo, accion, id_registro_afectado, descripcion,
        id_perfil_utilizado, id_puesto_laboral, id_local,
    )
    return db.session.execute(select(alta)).scalar_one()


def consultar_actividades(limite: int = 50):
    filas = func.public.auditoria_actividades(
        limite, perfil_tiene_capacidad(get_jwt().get('id_perfil'), 'administrar_globalmente'), local_actual()
    ).table_valued(
        'id_actividad_usuario', 'id_usuario', 'usuario', 'id_perfil_utilizado', 'perfil_utilizado', 'id_puesto_laboral', 'puesto_laboral', 'id_local', 'local', 'modulo', 'accion', 'id_registro_afectado', 'descripcion', 'fecha_actividad'
    )
    return db.session.execute(select(filas)).mappings().all()


def insertar_auditoria_cambio(
    id_usuario: int,
    modulo: str,
    accion: str,
    tabla_afectada: str,
    id_registro_afectado: int | None,
    datos_anteriores,
    datos_nuevos,
    motivo: str | None = None,
    id_perfil_utilizado: int | None = None,
    id_puesto_laboral: int | None = None,
    id_local: int | None = None,
):
    anterior = json.dumps(datos_anteriores, ensure_ascii=False, default=str) if datos_anteriores is not None else None
    nuevo = json.dumps(datos_nuevos, ensure_ascii=False, default=str) if datos_nuevos is not None else None
    alta = func.public.auditoria_insertar_cambio(
        id_usuario, id_perfil_utilizado, id_puesto_laboral, id_local, modulo.upper(),
        accion.upper(), tabla_afectada, id_registro_afectado, anterior, nuevo, motivo,
    )
    return db.session.execute(select(alta)).scalar_one()

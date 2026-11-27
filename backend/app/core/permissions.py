from functools import wraps

from flask import jsonify
from flask_jwt_extended import (
    get_jwt,
    get_jwt_identity,
    verify_jwt_in_request,
)
from sqlalchemy import func, select

from app.core.extensions import db


def requiere_permiso(id_opcion_menu: int | str, accion: str):
    def decorador(funcion):
        @wraps(funcion)
        def envoltura(*args, **kwargs):
            verify_jwt_in_request()

            token = get_jwt()

            if token.get("tipo_token") != "operativo":
                return jsonify({
                    "mensaje": "Debes seleccionar un perfil para continuar"
                }), 403

            try:
                id_usuario = int(get_jwt_identity())
                id_perfil = int(token.get("id_perfil"))
            except (TypeError, ValueError):
                return jsonify({
                    "mensaje": "La sesión no contiene un perfil válido"
                }), 401

            autorizado = db.session.execute(select(
                func.public.auth_permiso_accion(id_usuario, id_perfil, id_opcion_menu, accion)
            )).scalar()

            if not autorizado:
                return jsonify({
                    "mensaje": (
                        "No tienes permiso para realizar esta acción "
                        "con el perfil activo"
                    )
                }), 403

            return funcion(*args, **kwargs)

        return envoltura

    return decorador

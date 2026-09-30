from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity
from app.modules.promociones.editor import formulario_promocion, guardar_promocion

from app.core.permissions import requiere_permiso
from app.modules.promociones.service import (
    obtener_promociones,
)


promociones_bp = Blueprint(
    "promociones",
    __name__,
)


@promociones_bp.get('/formulario')
@requiere_permiso(14, 'consultar')
def formulario():
    datos, estado = formulario_promocion()
    return jsonify(datos), estado


@promociones_bp.post('')
@requiere_permiso(14, 'crear')
def crear():
    datos, estado = guardar_promocion(int(get_jwt_identity()), request.get_json(silent=True))
    return jsonify(datos), estado


@promociones_bp.put('/<int:id_promocion>')
@requiere_permiso(14, 'editar')
def editar(id_promocion):
    datos, estado = guardar_promocion(int(get_jwt_identity()), request.get_json(silent=True), id_promocion)
    return jsonify(datos), estado


@promociones_bp.get("")
@requiere_permiso(
    id_opcion_menu=14,
    accion="consultar",
)
def consultar_promociones():
    respuesta, estado = obtener_promociones()

    return jsonify(respuesta), estado

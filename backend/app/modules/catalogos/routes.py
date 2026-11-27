from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt_identity

from app.core.permissions import requiere_permiso
from app.core.units import catalogo_unidades
from app.modules.catalogos.repository import CategoriasProveedorNoDisponibles
from app.modules.catalogos.service import (
    crear_categoria_producto,
    crear_producto_catalogo,
    crear_proveedor_catalogo,
    dependencias_categoria,
    dependencias_proveedor,
    editar_categoria_producto,
    editar_producto_catalogo,
    editar_proveedor_catalogo,
    estado_categoria,
    estado_producto,
    estado_proveedor,
    obtener_catalogo_productos,
    obtener_categorias_producto,
    obtener_dependencias_producto,
    obtener_proveedores,
    reasignar_categoria,
    reasignar_proveedor,
)


catalogos_bp = Blueprint("catalogos", __name__)


@catalogos_bp.post('/proveedores/consultar-ruc')
@requiere_permiso('proveedores', 'consultar')
def consultar_ruc_proveedor():
    from app.modules.clientes.identity import consultar
    from werkzeug.exceptions import HTTPException
    datos = request.get_json(silent=True) or {}
    if not isinstance(datos, dict):
        return jsonify({'mensaje': 'Envía un RUC válido.'}), 400
    try:
        return jsonify(consultar('RUC', datos.get('ruc'))), 200
    except HTTPException as error:
        return jsonify({'mensaje': error.description}), error.code


@catalogos_bp.errorhandler(CategoriasProveedorNoDisponibles)
def categorias_proveedor_sin_migracion(error):
    return jsonify({"mensaje": str(error)}), 503


def _usuario():
    return int(get_jwt_identity())


@catalogos_bp.get("/unidades")
@requiere_permiso('productos', "consultar")
def consultar_unidades():
    contexto = request.args.get("contexto")
    try:
        unidades = catalogo_unidades(contexto)
    except ValueError as error:
        return jsonify({"mensaje": str(error)}), 400
    return jsonify({"estandar": "UNECE Recommendation 20",
                    "simbolos": "SI / BIPM",
                    "unidades": unidades}), 200


@catalogos_bp.get("/productos")
@requiere_permiso('productos', "consultar")
def consultar_productos():
    respuesta, estado = obtener_catalogo_productos()
    return jsonify(respuesta), estado


@catalogos_bp.post("/productos")
@requiere_permiso('productos', "crear")
def crear_producto():
    respuesta, estado = crear_producto_catalogo(
        _usuario(), request.get_json(silent=True) or {})
    return jsonify(respuesta), estado


@catalogos_bp.put("/productos/<int:id_producto>")
@requiere_permiso('productos', "editar")
def editar_producto(id_producto):
    respuesta, estado = editar_producto_catalogo(
        id_producto, _usuario(), request.get_json(silent=True) or {})
    return jsonify(respuesta), estado


@catalogos_bp.get("/productos/<int:id_producto>/dependencias")
@requiere_permiso('productos', "consultar")
def consultar_dependencias_producto(id_producto):
    respuesta, estado = obtener_dependencias_producto(id_producto)
    return jsonify(respuesta), estado


@catalogos_bp.patch("/productos/<int:id_producto>/desactivar")
@requiere_permiso('productos', "desactivar")
def desactivar_producto(id_producto):
    datos = request.get_json(silent=True) or {}
    respuesta, estado = estado_producto(
        id_producto, _usuario(), False, datos.get("motivo"))
    return jsonify(respuesta), estado


@catalogos_bp.patch("/productos/<int:id_producto>/reactivar")
@requiere_permiso('productos', "reactivar")
def reactivar_producto(id_producto):
    datos = request.get_json(silent=True) or {}
    respuesta, estado = estado_producto(
        id_producto, _usuario(), True, datos.get("motivo"))
    return jsonify(respuesta), estado


@catalogos_bp.get("/categorias-productos")
@requiere_permiso('categorias_productos', "consultar")
def consultar_categorias_producto():
    respuesta, estado = obtener_categorias_producto()
    return jsonify(respuesta), estado


@catalogos_bp.post("/categorias-productos")
@requiere_permiso('categorias_productos', "crear")
def crear_categoria():
    respuesta, estado = crear_categoria_producto(
        _usuario(), request.get_json(silent=True) or {})
    return jsonify(respuesta), estado


@catalogos_bp.put("/categorias-productos/<int:id_categoria>")
@requiere_permiso('categorias_productos', "editar")
def editar_categoria(id_categoria):
    respuesta, estado = editar_categoria_producto(
        id_categoria, _usuario(), request.get_json(silent=True) or {})
    return jsonify(respuesta), estado


@catalogos_bp.get("/categorias-productos/<int:id_categoria>/dependencias")
@requiere_permiso('categorias_productos', "consultar")
def consultar_dependencias_categoria(id_categoria):
    respuesta, estado = dependencias_categoria(id_categoria)
    return jsonify(respuesta), estado


@catalogos_bp.post("/categorias-productos/<int:id_categoria>/reasignar")
@requiere_permiso('categorias_productos', "configurar")
def reasignar_productos_categoria(id_categoria):
    respuesta, estado = reasignar_categoria(
        id_categoria, _usuario(), request.get_json(silent=True) or {})
    return jsonify(respuesta), estado


@catalogos_bp.patch("/categorias-productos/<int:id_categoria>/desactivar")
@requiere_permiso('categorias_productos', "desactivar")
def desactivar_categoria(id_categoria):
    datos = request.get_json(silent=True) or {}
    respuesta, estado = estado_categoria(
        id_categoria, _usuario(), False, datos.get("motivo"))
    return jsonify(respuesta), estado


@catalogos_bp.patch("/categorias-productos/<int:id_categoria>/reactivar")
@requiere_permiso('categorias_productos', "reactivar")
def reactivar_categoria(id_categoria):
    datos = request.get_json(silent=True) or {}
    respuesta, estado = estado_categoria(
        id_categoria, _usuario(), True, datos.get("motivo"))
    return jsonify(respuesta), estado


@catalogos_bp.get("/proveedores")
@requiere_permiso('proveedores', "consultar")
def consultar_proveedores():
    respuesta, estado = obtener_proveedores()
    return jsonify(respuesta), estado


@catalogos_bp.post("/proveedores")
@requiere_permiso('proveedores', "crear")
def crear_proveedor():
    respuesta, estado = crear_proveedor_catalogo(
        _usuario(), request.get_json(silent=True) or {})
    return jsonify(respuesta), estado


@catalogos_bp.put("/proveedores/<int:id_proveedor>")
@requiere_permiso('proveedores', "editar")
def editar_proveedor(id_proveedor):
    respuesta, estado = editar_proveedor_catalogo(
        id_proveedor, _usuario(), request.get_json(silent=True) or {})
    return jsonify(respuesta), estado


@catalogos_bp.get("/proveedores/<int:id_proveedor>/dependencias")
@requiere_permiso('proveedores', "consultar")
def consultar_dependencias_proveedor(id_proveedor):
    respuesta, estado = dependencias_proveedor(id_proveedor)
    return jsonify(respuesta), estado


@catalogos_bp.post("/proveedores/<int:id_proveedor>/reasignar")
@requiere_permiso('proveedores', "configurar")
def reasignar_productos_proveedor(id_proveedor):
    respuesta, estado = reasignar_proveedor(
        id_proveedor, _usuario(), request.get_json(silent=True) or {})
    return jsonify(respuesta), estado


@catalogos_bp.patch("/proveedores/<int:id_proveedor>/desactivar")
@requiere_permiso('proveedores', "desactivar")
def desactivar_proveedor(id_proveedor):
    datos = request.get_json(silent=True) or {}
    respuesta, estado = estado_proveedor(
        id_proveedor, _usuario(), False, datos.get("motivo"))
    return jsonify(respuesta), estado


@catalogos_bp.patch("/proveedores/<int:id_proveedor>/reactivar")
@requiere_permiso('proveedores', "reactivar")
def reactivar_proveedor(id_proveedor):
    datos = request.get_json(silent=True) or {}
    respuesta, estado = estado_proveedor(
        id_proveedor, _usuario(), True, datos.get("motivo"))
    return jsonify(respuesta), estado

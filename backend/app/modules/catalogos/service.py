from decimal import Decimal

from app.modules.catalogos.repository import (
    listar_categorias_producto,
    listar_categorias_producto_detalladas,
    listar_productos,
    listar_proveedores,
    listar_proveedores_detallados,
)

from decimal import Decimal, InvalidOperation

from app.core.extensions import db
from app.modules.auditoria.service import (
    registrar_actividad,
    registrar_cambio,
)
from app.modules.catalogos import repository as repo

def convertir_decimal(valor):
    if isinstance(valor, Decimal):
        return float(valor)

    return valor


def serializar_producto(producto):
    return {
        "id_producto": producto["id_producto"],
        "codigo": producto["codigo"],
        "nombre": producto["nombre"],
        "id_categoria": producto["id_categoria"],
        "categoria": producto["categoria"],
        "id_proveedor": producto["id_proveedor"],
        "proveedor": producto["proveedor"],
        "unidad": producto["unidad"],
        "presentacion": convertir_decimal(
            producto["presentacion"]
        ),
        "activo": producto["activo"],
    }


def obtener_catalogo_productos():
    productos = [
        serializar_producto(producto)
        for producto in listar_productos()
    ]

    categorias = listar_categorias_producto()
    proveedores = listar_proveedores()

    total_activos = sum(
        1
        for producto in productos
        if producto["activo"]
    )

    total_inactivos = len(productos) - total_activos

    respuesta = {
        "productos": productos,
        "categorias": categorias,
        "proveedores": proveedores,
        "resumen": {
            "total_productos": len(productos),
            "productos_activos": total_activos,
            "productos_inactivos": total_inactivos,
            "total_categorias": len(categorias),
            "total_proveedores": len(proveedores),
        },
    }

    return respuesta, 200


def obtener_categorias_producto():
    categorias = listar_categorias_producto_detalladas()

    total_activas = sum(
        1
        for categoria in categorias
        if categoria["activo"]
    )

    total_inactivas = len(categorias) - total_activas

    total_productos = sum(
        categoria["total_productos"]
        for categoria in categorias
    )

    respuesta = {
        "categorias": categorias,
        "resumen": {
            "total_categorias": len(categorias),
            "categorias_activas": total_activas,
            "categorias_inactivas": total_inactivas,
            "total_productos_asociados": total_productos,
        },
    }

    return respuesta, 200

def obtener_proveedores():
    proveedores = listar_proveedores_detallados()

    proveedores_activos = sum(
        1
        for proveedor in proveedores
        if proveedor["activo"]
    )

    proveedores_inactivos = (
        len(proveedores) - proveedores_activos
    )

    total_productos = sum(
        proveedor["total_productos"]
        for proveedor in proveedores
    )

    respuesta = {
        "proveedores": proveedores,
        "resumen": {
            "total_proveedores": len(proveedores),
            "proveedores_activos": proveedores_activos,
            "proveedores_inactivos":
                proveedores_inactivos,
            "total_productos_asociados":
                total_productos,
        },
    }

    return respuesta, 200


UNIDADES = {"Kg", "L", "UNI"}


def _texto(datos, campo, maximo):
    valor = str(datos.get(campo, "")).strip()
    return valor if 0 < len(valor) <= maximo else None


def _entero(datos, campo):
    try:
        valor = int(datos.get(campo))
        return valor if valor > 0 else None
    except (TypeError, ValueError):
        return None


def _decimal(datos, campo, permitir_cero=False):
    try:
        valor = Decimal(str(datos.get(campo)))
    except (InvalidOperation, TypeError, ValueError):
        return None
    if not valor.is_finite():
        return None
    if permitir_cero and valor >= 0:
        return valor
    return valor if valor > 0 else None


def crear_categoria_producto(id_usuario, datos):
    nombre = _texto(datos, "nombre", 100)
    prefijo = str(datos.get("prefijo", "")).strip().upper()
    if not nombre or not prefijo.isalpha() or not 1 <= len(prefijo) <= 3:
        return {"mensaje": "Nombre o prefijo inválido"}, 400
    if repo.categoria_repetida(nombre, prefijo):
        return {"mensaje": "El nombre o prefijo ya está registrado"}, 409
    try:
        identidad = repo.crear_categoria(nombre, prefijo)
        nuevo = dict(repo.obtener_categoria(identidad))
        registrar_cambio(id_usuario, "CATALOGOS", "CREAR",
                         "categoria_producto", identidad, None, nuevo)
        registrar_actividad(id_usuario, "CATALOGOS", "CREAR",
                            identidad, f"Creó la categoría {nombre}")
        db.session.commit()
        return {"mensaje": "Categoría creada correctamente",
                "id_categoria": identidad}, 201
    except Exception:
        db.session.rollback()
        raise


def editar_categoria_producto(id_categoria, id_usuario, datos):
    nombre = _texto(datos, "nombre", 100)
    prefijo = str(datos.get("prefijo", "")).strip().upper()
    if not nombre or not prefijo.isalpha() or not 1 <= len(prefijo) <= 3:
        return {"mensaje": "Nombre o prefijo inválido"}, 400
    try:
        actual = repo.obtener_categoria(id_categoria, bloquear=True)
        if actual is None:
            db.session.rollback(); return {"mensaje": "La categoría no existe"}, 404
        if repo.categoria_repetida(nombre, prefijo, id_categoria):
            db.session.rollback(); return {"mensaje": "Nombre o prefijo repetido"}, 409
        anterior = dict(actual)
        repo.actualizar_categoria(id_categoria, nombre, prefijo)
        nuevo = dict(repo.obtener_categoria(id_categoria))
        registrar_cambio(id_usuario, "CATALOGOS", "EDITAR",
                         "categoria_producto", id_categoria, anterior, nuevo)
        registrar_actividad(id_usuario, "CATALOGOS", "EDITAR",
                            id_categoria, f"Editó la categoría {nombre}")
        db.session.commit()
        return {"mensaje": "Categoría actualizada correctamente"}, 200
    except Exception:
        db.session.rollback(); raise


def dependencias_categoria(id_categoria):
    categoria = repo.obtener_categoria(id_categoria)
    if categoria is None:
        return {"mensaje": "La categoría no existe"}, 404
    productos = [dict(x) for x in repo.productos_categoria(id_categoria)]
    return {"categoria": dict(categoria), "productos": productos,
            "productos_activos": sum(1 for x in productos if x["activo"]),
            "puede_desactivar": not any(x["activo"] for x in productos)}, 200


def estado_categoria(id_categoria, id_usuario, activo, motivo):
    motivo = str(motivo or "").strip()
    if len(motivo) < 10:
        return {"mensaje": "El motivo debe tener al menos 10 caracteres"}, 400
    try:
        actual = repo.obtener_categoria(id_categoria, bloquear=True)
        if actual is None:
            db.session.rollback(); return {"mensaje": "La categoría no existe"}, 404
        if not activo and repo.productos_categoria(id_categoria, True):
            db.session.rollback()
            return {"mensaje": "Reasigna o desactiva sus productos activos primero"}, 409
        anterior = dict(actual)
        repo.cambiar_estado_categoria(id_categoria, activo)
        nuevo = dict(repo.obtener_categoria(id_categoria))
        accion = "REACTIVAR" if activo else "DESACTIVAR"
        registrar_cambio(id_usuario, "CATALOGOS", accion,
                         "categoria_producto", id_categoria, anterior, nuevo, motivo)
        registrar_actividad(id_usuario, "CATALOGOS", accion,
                            id_categoria, f"{accion.title()} categoría: {motivo}")
        db.session.commit()
        return {"mensaje": f"Categoría {'reactivada' if activo else 'desactivada'} correctamente"}, 200
    except Exception:
        db.session.rollback(); raise


def reasignar_categoria(id_categoria, id_usuario, datos):
    nueva = _entero(datos, "id_categoria_nueva")
    ids = datos.get("ids_productos")
    motivo = str(datos.get("motivo", "")).strip()
    if not nueva or nueva == id_categoria or not isinstance(ids, list) or not ids:
        return {"mensaje": "Selecciona categoría y productos válidos"}, 400
    if len(motivo) < 10:
        return {"mensaje": "El motivo debe tener al menos 10 caracteres"}, 400
    try:
        origen = repo.obtener_categoria(id_categoria, True)
        destino = repo.obtener_categoria(nueva, True)
        if origen is None or destino is None or not destino["activo"]:
            db.session.rollback(); return {"mensaje": "Categoría de origen o destino inválida"}, 409
        movidos = repo.reasignar_categoria_productos(
            id_categoria, nueva, list({int(x) for x in ids}), id_usuario, motivo)
        if not movidos:
            db.session.rollback(); return {"mensaje": "No se reasignó ningún producto"}, 400
        registrar_actividad(id_usuario, "CATALOGOS", "REASIGNAR",
                            id_categoria, f"Reasignó {len(movidos)} productos de categoría")
        db.session.commit()
        return {"mensaje": "Productos reasignados correctamente", "total": len(movidos)}, 200
    except (TypeError, ValueError):
        db.session.rollback(); return {"mensaje": "Lista de productos inválida"}, 400
    except Exception:
        db.session.rollback(); raise


def crear_proveedor_catalogo(id_usuario, datos):
    nombre = _texto(datos, "nombre", 200)
    if not nombre:
        return {"mensaje": "Ingresa un nombre válido"}, 400
    if repo.proveedor_repetido(nombre):
        return {"mensaje": "El proveedor ya está registrado"}, 409
    try:
        identidad = repo.crear_proveedor(nombre)
        nuevo = dict(repo.obtener_proveedor(identidad))
        registrar_cambio(id_usuario, "CATALOGOS", "CREAR",
                         "proveedor", identidad, None, nuevo)
        registrar_actividad(id_usuario, "CATALOGOS", "CREAR",
                            identidad, f"Creó el proveedor {nombre}")
        db.session.commit()
        return {"mensaje": "Proveedor creado correctamente",
                "id_proveedor": identidad}, 201
    except Exception:
        db.session.rollback(); raise


def editar_proveedor_catalogo(id_proveedor, id_usuario, datos):
    nombre = _texto(datos, "nombre", 200)
    if not nombre:
        return {"mensaje": "Ingresa un nombre válido"}, 400
    try:
        actual = repo.obtener_proveedor(id_proveedor, True)
        if actual is None:
            db.session.rollback(); return {"mensaje": "El proveedor no existe"}, 404
        if repo.proveedor_repetido(nombre, id_proveedor):
            db.session.rollback(); return {"mensaje": "El proveedor ya existe"}, 409
        anterior = dict(actual)
        repo.actualizar_proveedor(id_proveedor, nombre)
        nuevo = dict(repo.obtener_proveedor(id_proveedor))
        registrar_cambio(id_usuario, "CATALOGOS", "EDITAR",
                         "proveedor", id_proveedor, anterior, nuevo)
        registrar_actividad(id_usuario, "CATALOGOS", "EDITAR",
                            id_proveedor, f"Editó el proveedor {nombre}")
        db.session.commit()
        return {"mensaje": "Proveedor actualizado correctamente"}, 200
    except Exception:
        db.session.rollback(); raise


def dependencias_proveedor(id_proveedor):
    proveedor = repo.obtener_proveedor(id_proveedor)
    if proveedor is None:
        return {"mensaje": "El proveedor no existe"}, 404
    productos = [dict(x) for x in repo.productos_proveedor(id_proveedor)]
    return {"proveedor": dict(proveedor), "productos": productos,
            "productos_activos": sum(1 for x in productos if x["activo"]),
            "puede_desactivar": not any(x["activo"] for x in productos)}, 200


def estado_proveedor(id_proveedor, id_usuario, activo, motivo):
    motivo = str(motivo or "").strip()
    if len(motivo) < 10:
        return {"mensaje": "El motivo debe tener al menos 10 caracteres"}, 400
    try:
        actual = repo.obtener_proveedor(id_proveedor, True)
        if actual is None:
            db.session.rollback(); return {"mensaje": "El proveedor no existe"}, 404
        if not activo and repo.productos_proveedor(id_proveedor, True):
            db.session.rollback()
            return {"mensaje": "Reasigna o desactiva sus productos activos primero"}, 409
        anterior = dict(actual)
        repo.cambiar_estado_proveedor(id_proveedor, activo)
        nuevo = dict(repo.obtener_proveedor(id_proveedor))
        accion = "REACTIVAR" if activo else "DESACTIVAR"
        registrar_cambio(id_usuario, "CATALOGOS", accion,
                         "proveedor", id_proveedor, anterior, nuevo, motivo)
        registrar_actividad(id_usuario, "CATALOGOS", accion,
                            id_proveedor, f"{accion.title()} proveedor: {motivo}")
        db.session.commit()
        return {"mensaje": f"Proveedor {'reactivado' if activo else 'desactivado'} correctamente"}, 200
    except Exception:
        db.session.rollback(); raise


def reasignar_proveedor(id_proveedor, id_usuario, datos):
    nuevo = _entero(datos, "id_proveedor_nuevo")
    ids = datos.get("ids_productos")
    motivo = str(datos.get("motivo", "")).strip()
    if not nuevo or nuevo == id_proveedor or not isinstance(ids, list) or not ids:
        return {"mensaje": "Selecciona proveedor y productos válidos"}, 400
    if len(motivo) < 10:
        return {"mensaje": "El motivo debe tener al menos 10 caracteres"}, 400
    try:
        origen = repo.obtener_proveedor(id_proveedor, True)
        destino = repo.obtener_proveedor(nuevo, True)
        if origen is None or destino is None or not destino["activo"]:
            db.session.rollback(); return {"mensaje": "Proveedor de origen o destino inválido"}, 409
        movidos = repo.reasignar_proveedor_productos(
            id_proveedor, nuevo, list({int(x) for x in ids}), id_usuario, motivo)
        if not movidos:
            db.session.rollback(); return {"mensaje": "No se reasignó ningún producto"}, 400
        registrar_actividad(id_usuario, "CATALOGOS", "REASIGNAR",
                            id_proveedor, f"Reasignó {len(movidos)} productos de proveedor")
        db.session.commit()
        return {"mensaje": "Productos reasignados correctamente", "total": len(movidos)}, 200
    except (TypeError, ValueError):
        db.session.rollback(); return {"mensaje": "Lista de productos inválida"}, 400
    except Exception:
        db.session.rollback(); raise


def _datos_producto(datos):
    nombre = _texto(datos, "nombre", 200)
    categoria = _entero(datos, "id_categoria")
    proveedor = _entero(datos, "id_proveedor")
    unidad = str(datos.get("unidad", "")).strip()
    presentacion = _decimal(datos, "presentacion")
    if (not nombre or not categoria or not proveedor or
            unidad not in UNIDADES or presentacion is None):
        return None
    return nombre, categoria, proveedor, unidad, presentacion


def crear_producto_catalogo(id_usuario, datos):
    if "stock_minimo" in datos or "stock_maximo" in datos:
        return {"mensaje": "Los límites se configuran exclusivamente desde Límites de stock por el gerente"}, 403
    valores = _datos_producto(datos)
    if valores is None:
        return {"mensaje": "Completa correctamente los datos del producto"}, 400
    nombre, categoria, proveedor, unidad, presentacion = valores
    if repo.producto_repetido(nombre):
        return {"mensaje": "Ya existe un producto con ese nombre"}, 409
    try:
        if repo.obtener_proveedor(proveedor) is None or not repo.obtener_proveedor(proveedor)["activo"]:
            db.session.rollback(); return {"mensaje": "El proveedor no está activo"}, 409
        codigo = repo.generar_codigo_producto(categoria)
        if codigo is None:
            db.session.rollback(); return {"mensaje": "La categoría no está activa"}, 409
        identidad = repo.crear_producto_registro(
            codigo, nombre, categoria, proveedor, unidad, presentacion)
        nuevo = dict(repo.obtener_producto(identidad))
        registrar_cambio(id_usuario, "CATALOGOS", "CREAR",
                         "producto", identidad, None, nuevo)
        registrar_actividad(id_usuario, "CATALOGOS", "CREAR",
                            identidad, f"Creó el producto {codigo} - {nombre}")
        db.session.commit()
        return {"mensaje": "Producto creado correctamente",
                "id_producto": identidad, "codigo": codigo}, 201
    except Exception:
        db.session.rollback(); raise


def editar_producto_catalogo(id_producto, id_usuario, datos):
    if "stock_minimo" in datos or "stock_maximo" in datos:
        return {"mensaje": "Los límites se configuran exclusivamente desde Límites de stock por el gerente"}, 403
    valores = _datos_producto(datos)
    if valores is None:
        return {"mensaje": "Completa correctamente los datos del producto"}, 400
    nombre, categoria, proveedor, unidad, presentacion = valores
    try:
        actual = repo.obtener_producto(id_producto, True)
        if actual is None:
            db.session.rollback(); return {"mensaje": "El producto no existe"}, 404
        if repo.producto_repetido(nombre, id_producto):
            db.session.rollback(); return {"mensaje": "Ya existe un producto con ese nombre"}, 409
        destino_categoria = repo.obtener_categoria(categoria)
        destino_proveedor = repo.obtener_proveedor(proveedor)
        if (destino_categoria is None or not destino_categoria["activo"] or
                destino_proveedor is None or not destino_proveedor["activo"]):
            db.session.rollback(); return {"mensaje": "Categoría o proveedor inactivo"}, 409
        anterior = dict(actual)
        repo.actualizar_producto_registro(
            id_producto, nombre, categoria, proveedor, unidad, presentacion)
        nuevo = dict(repo.obtener_producto(id_producto))
        motivo = str(datos.get("motivo", "Actualización administrativa")).strip()
        if anterior["id_categoria"] != categoria:
            repo.guardar_historial_categoria_producto(
                id_producto, anterior["id_categoria"], categoria,
                id_usuario, motivo,
            )
        if anterior["id_proveedor"] != proveedor:
            repo.guardar_historial_proveedor_producto(
                id_producto, anterior["id_proveedor"], proveedor,
                id_usuario, motivo,
            )
        registrar_cambio(id_usuario, "CATALOGOS", "EDITAR",
                         "producto", id_producto, anterior, nuevo, motivo)
        registrar_actividad(id_usuario, "CATALOGOS", "EDITAR",
                            id_producto, f"Editó el producto {actual['codigo']}")
        db.session.commit()
        return {"mensaje": "Producto actualizado correctamente"}, 200
    except Exception:
        db.session.rollback(); raise


def obtener_dependencias_producto(id_producto):
    producto = repo.obtener_producto(id_producto)
    if producto is None:
        return {"mensaje": "El producto no existe"}, 404
    dependencias = dict(repo.dependencias_producto(id_producto))
    operativas = dependencias["recetas"] + dependencias["subproductos"] + dependencias["salsas_activas"]
    return {"producto": dict(producto), "dependencias": dependencias,
            "puede_desactivar": operativas == 0}, 200


def estado_producto(id_producto, id_usuario, activo, motivo):
    motivo = str(motivo or "").strip()
    if len(motivo) < 10:
        return {"mensaje": "El motivo debe tener al menos 10 caracteres"}, 400
    try:
        actual = repo.obtener_producto(id_producto, True)
        if actual is None:
            db.session.rollback(); return {"mensaje": "El producto no existe"}, 404
        deps = dict(repo.dependencias_producto(id_producto))
        if not activo and (deps["recetas"] or deps["subproductos"] or deps["salsas_activas"]):
            db.session.rollback()
            return {"mensaje": "El producto tiene recetas, subproductos o salsas activas relacionadas"}, 409
        anterior = dict(actual)
        repo.cambiar_estado_producto(id_producto, activo)
        nuevo = dict(repo.obtener_producto(id_producto))
        accion = "REACTIVAR" if activo else "DESACTIVAR"
        registrar_cambio(id_usuario, "CATALOGOS", accion,
                         "producto", id_producto, anterior, nuevo, motivo)
        registrar_actividad(id_usuario, "CATALOGOS", accion,
                            id_producto, f"{accion.title()} producto: {motivo}")
        db.session.commit()
        return {"mensaje": f"Producto {'reactivado' if activo else 'desactivado'} correctamente"}, 200
    except Exception:
        db.session.rollback(); raise

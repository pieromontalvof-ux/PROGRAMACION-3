from sqlalchemy import bindparam, func, select

from app.core.extensions import db
from app.core.units import unidad_almacenamiento


class CategoriasProveedorNoDisponibles(RuntimeError):
    pass


def categorias_proveedor_disponibles():
    return db.session.execute(
        select(func.public.catalogos_categorias_proveedor_disponibles())
    ).scalar_one()


def listar_productos():
    consulta = select(func.public.catalogos_listar_productos().table_valued('id_producto', 'codigo', 'nombre', 'id_categoria', 'categoria', 'id_proveedor', 'proveedor', 'unidad', 'stock_minimo', 'presentacion', 'activo'))

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_categorias_producto():
    consulta = select(func.public.catalogos_listar_categorias_producto().table_valued('id_categoria', 'nombre', 'prefijo', 'siguiente_numero', 'activo'))

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_categorias_producto_detalladas():
    consulta = select(func.public.catalogos_listar_categorias_producto_detalladas().table_valued('id_categoria', 'nombre', 'prefijo', 'siguiente_numero', 'activo', 'total_productos', 'productos_activos', 'productos_inactivos'))

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_proveedores():
    consulta = select(func.public.catalogos_listar_proveedores().table_valued('id_proveedor', 'nombre', 'activo', 'datos_comerciales', 'ids_categorias'))

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]

def listar_proveedores_detallados():
    proveedores = listar_proveedores()
    for proveedor in proveedores:
        productos = productos_proveedor(proveedor["id_proveedor"])
        categorias = db.session.execute(select(func.public.catalogos_listar_proveedores_detallados(bindparam('id'))), {"id": proveedor["id_proveedor"]}).scalars().all()
        proveedor.update(
            total_productos=len(productos),
            productos_activos=sum(1 for p in productos if p["activo"]),
            productos_inactivos=sum(1 for p in productos if not p["activo"]),
            total_categorias=len(categorias), categorias=list(categorias),
        )
    return proveedores


def categorias_proveedor(id_proveedor):
    return list(db.session.execute(select(func.public.catalogos_categorias_proveedor(bindparam('id'))), {"id": id_proveedor}).scalars().all())


def asignar_categorias_proveedor(id_proveedor, ids):
    if not categorias_proveedor_disponibles():
        raise CategoriasProveedorNoDisponibles(
            "La asignación de categorías requiere ejecutar la migración "
            "20261010_proveedor_categorias.sql con el propietario de las tablas "
            "o un administrador de PostgreSQL. No se guardó ningún cambio."
        )
    db.session.execute(select(func.public.catalogos_asignar_categorias_proveedor_1(bindparam('id'))),
                       {"id": id_proveedor})
    for categoria in ids:
        db.session.execute(select(func.public.catalogos_asignar_categorias_proveedor_2(bindparam('id'), bindparam('categoria'))), {"id": id_proveedor, "categoria": categoria})


def obtener_categoria(id_categoria, bloquear=False):
    return db.session.execute(
        select((func.public.catalogos_obtener_categoria_bloqueado if bloquear else func.public.catalogos_obtener_categoria)(bindparam('id_categoria')).table_valued('id_categoria', 'nombre', 'prefijo', 'siguiente_numero', 'activo')),
        {"id_categoria": id_categoria},
    ).mappings().first()


def categoria_repetida(nombre, prefijo, excluir_id=None):
    return db.session.execute(
        select(func.public.catalogos_categoria_repetida(bindparam('excluir_id'), bindparam('nombre'), bindparam('prefijo'))),
        {"nombre": nombre, "prefijo": prefijo,
         "excluir_id": excluir_id},
    ).scalar()


def crear_categoria(nombre, prefijo):
    return db.session.execute(
        select(func.public.catalogos_crear_categoria(bindparam('nombre'), bindparam('prefijo'))),
        {"nombre": nombre, "prefijo": prefijo},
    ).scalar_one()


def actualizar_categoria(id_categoria, nombre, prefijo):
    db.session.execute(
        select(func.public.catalogos_actualizar_categoria(bindparam('nombre'), bindparam('prefijo'), bindparam('id_categoria'))),
        {"id_categoria": id_categoria, "nombre": nombre,
         "prefijo": prefijo},
    )


def productos_categoria(id_categoria, solo_activos=False):
    return db.session.execute(
        select(func.public.catalogos_productos_categoria(bindparam('id_categoria'), solo_activos).table_valued('id_producto', 'codigo', 'nombre', 'activo')),
        {"id_categoria": id_categoria},
    ).mappings().all()


def cambiar_estado_categoria(id_categoria, activo):
    db.session.execute(
        select(func.public.catalogos_cambiar_estado_categoria(bindparam('activo'), bindparam('id_categoria'))),
        {"id_categoria": id_categoria, "activo": activo},
    )


def reasignar_categoria_productos(
    id_categoria_anterior,
    id_categoria_nueva,
    ids_productos,
    id_usuario,
    motivo,
):
    filas = db.session.execute(
        select(func.public.catalogos_reasignar_categoria_productos_1(bindparam('nueva'), bindparam('anterior'), bindparam('ids'))),
        {"anterior": id_categoria_anterior,
         "nueva": id_categoria_nueva, "ids": ids_productos},
    ).scalars().all()

    for id_producto in filas:
        db.session.execute(
            select(func.public.catalogos_reasignar_categoria_productos_2(bindparam('id_producto'), bindparam('anterior'), bindparam('nueva'), bindparam('usuario'), bindparam('motivo'))),
            {"id_producto": id_producto,
             "anterior": id_categoria_anterior,
             "nueva": id_categoria_nueva,
             "usuario": id_usuario, "motivo": motivo},
        )
    return filas


def obtener_proveedor(id_proveedor, bloquear=False):
    return db.session.execute(
        select((func.public.catalogos_obtener_proveedor_bloqueado if bloquear else func.public.catalogos_obtener_proveedor)(bindparam('id_proveedor')).table_valued('id_proveedor', 'nombre', 'activo', 'datos_comerciales')),
        {"id_proveedor": id_proveedor},
    ).mappings().first()


def proveedor_repetido(nombre, excluir_id=None):
    return db.session.execute(
        select(func.public.catalogos_proveedor_repetido(bindparam('nombre'), bindparam('excluir_id'))),
        {"nombre": nombre, "excluir_id": excluir_id},
    ).scalar()


def crear_proveedor(nombre):
    return db.session.execute(
        select(func.public.catalogos_crear_proveedor(bindparam('nombre'))),
        {"nombre": nombre},
    ).scalar_one()


def actualizar_proveedor(id_proveedor, nombre):
    db.session.execute(
        select(func.public.catalogos_actualizar_proveedor(bindparam('nombre'), bindparam('id_proveedor'))),
        {"id_proveedor": id_proveedor, "nombre": nombre},
    )


def productos_proveedor(id_proveedor, solo_activos=False):
    return db.session.execute(
        select(func.public.catalogos_productos_proveedor(bindparam('id_proveedor'), solo_activos).table_valued('id_producto', 'codigo', 'nombre', 'activo', 'id_categoria')),
        {"id_proveedor": id_proveedor},
    ).mappings().all()


def cambiar_estado_proveedor(id_proveedor, activo):
    db.session.execute(
        select(func.public.catalogos_cambiar_estado_proveedor(bindparam('activo'), bindparam('id_proveedor'))),
        {"id_proveedor": id_proveedor, "activo": activo},
    )


def reasignar_proveedor_productos(
    id_proveedor_anterior,
    id_proveedor_nuevo,
    ids_productos,
    id_usuario,
    motivo,
):
    filas = db.session.execute(
        select(func.public.catalogos_reasignar_proveedor_productos_1(bindparam('nuevo'), bindparam('anterior'), bindparam('ids'))),
        {"anterior": id_proveedor_anterior,
         "nuevo": id_proveedor_nuevo, "ids": ids_productos},
    ).scalars().all()

    for id_producto in filas:
        db.session.execute(
            select(func.public.catalogos_reasignar_proveedor_productos_2(bindparam('id_producto'), bindparam('anterior'), bindparam('nuevo'), bindparam('usuario'), bindparam('motivo'))),
            {"id_producto": id_producto,
             "anterior": id_proveedor_anterior,
             "nuevo": id_proveedor_nuevo,
             "usuario": id_usuario, "motivo": motivo},
        )
    return filas


def obtener_producto(id_producto, bloquear=False):
    return db.session.execute(
        select((func.public.catalogos_obtener_producto_bloqueado if bloquear else func.public.catalogos_obtener_producto)(bindparam('id_producto')).table_valued('id_producto', 'codigo', 'nombre', 'id_categoria', 'id_proveedor', 'unidad', 'stock_minimo', 'presentacion', 'activo')),
        {"id_producto": id_producto},
    ).mappings().first()


def generar_codigo_producto(id_categoria):
    fila = db.session.execute(
        select(func.public.catalogos_generar_codigo_producto(bindparam('id_categoria')).table_valued('prefijo', 'numero')),
        {"id_categoria": id_categoria},
    ).mappings().first()
    if fila is None:
        return None
    return f"{fila['prefijo']}-{int(fila['numero']):03d}"


def producto_repetido(nombre, excluir_id=None):
    return db.session.execute(
        select(func.public.catalogos_producto_repetido(bindparam('nombre'), bindparam('excluir_id'))),
        {"nombre": nombre, "excluir_id": excluir_id},
    ).scalar()


def crear_producto_registro(
    codigo, nombre, id_categoria, id_proveedor,
    unidad, presentacion,
):
    return db.session.execute(
        select(func.public.catalogos_crear_producto_registro(bindparam('codigo'), bindparam('nombre'), bindparam('categoria'), bindparam('proveedor'), bindparam('unidad'), bindparam('presentacion'))),
        {"codigo": codigo, "nombre": nombre,
         "categoria": id_categoria, "proveedor": id_proveedor,
         "unidad": unidad_almacenamiento(unidad),
         "presentacion": presentacion},
    ).scalar_one()


def actualizar_producto_registro(
    id_producto, nombre, id_categoria, id_proveedor,
    unidad, presentacion,
):
    db.session.execute(
        select(func.public.catalogos_actualizar_producto_registro(bindparam('nombre'), bindparam('categoria'), bindparam('proveedor'), bindparam('unidad'), bindparam('presentacion'), bindparam('id_producto'))),
        {"id_producto": id_producto, "nombre": nombre,
         "categoria": id_categoria, "proveedor": id_proveedor,
         "unidad": unidad_almacenamiento(unidad),
         "presentacion": presentacion},
    )


def cambiar_estado_producto(id_producto, activo):
    db.session.execute(
        select(func.public.catalogos_cambiar_estado_producto(bindparam('activo'), bindparam('id_producto'))),
        {"id_producto": id_producto, "activo": activo},
    )


def dependencias_producto(id_producto):
    consulta = select(func.public.catalogos_dependencias_producto(bindparam('id')).table_valued('recetas', 'subproductos', 'salsas_activas', 'ordenes', 'recepciones', 'inventarios', 'movimientos'))
    return db.session.execute(
        consulta, {"id": id_producto}
    ).mappings().one()


def guardar_historial_categoria_producto(
    id_producto, anterior, nueva, id_usuario, motivo,
):
    db.session.execute(select(func.public.catalogos_guardar_historial_categoria_producto(bindparam('producto'), bindparam('anterior'), bindparam('nueva'), bindparam('usuario'), bindparam('motivo'))), {"producto": id_producto, "anterior": anterior,
            "nueva": nueva, "usuario": id_usuario, "motivo": motivo})


def guardar_historial_proveedor_producto(
    id_producto, anterior, nuevo, id_usuario, motivo,
):
    db.session.execute(select(func.public.catalogos_guardar_historial_proveedor_producto(bindparam('producto'), bindparam('anterior'), bindparam('nuevo'), bindparam('usuario'), bindparam('motivo'))), {"producto": id_producto, "anterior": anterior,
            "nuevo": nuevo, "usuario": id_usuario, "motivo": motivo})


def guardar_comercial_proveedor(identidad, datos):
    import json
    from sqlalchemy.exc import IntegrityError
    from werkzeug.exceptions import Conflict
    try:
        db.session.execute(select(func.public.catalogos_guardar_comercial_proveedor(bindparam('datos'), bindparam('id'))),
                           {'id': identidad, 'datos': json.dumps(datos)})
    except IntegrityError as error:
        db.session.rollback()
        if getattr(getattr(error.orig, 'diag', None), 'constraint_name', '') == 'uq_proveedor_ruc':
            raise Conflict('Ese RUC ya pertenece a otro proveedor.') from None
        raise


def ruc_proveedor_repetido(ruc, excluir=None):
    return bool(ruc) and db.session.execute(select(func.public.catalogos_ruc_proveedor_repetido(bindparam('ruc'), bindparam('id'))),
                         {'ruc': ruc, 'id': excluir}).scalar()

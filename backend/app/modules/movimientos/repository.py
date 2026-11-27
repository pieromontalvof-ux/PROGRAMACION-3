from sqlalchemy import bindparam, func, select

from app.core.local_scope import ejecutar_local, exigir_registro_local


def listar_productos_activos_movimiento():
    consulta = select(func.public.mov_productos_activos().table_valued("id_producto", "codigo", "nombre", "unidad", "id_categoria", "categoria"))

    return ejecutar_local(
        consulta
    ).mappings().all()


def listar_proveedores_activos_movimiento():
    consulta = select(func.public.mov_proveedores_activos().table_valued("id_proveedor", "nombre"))

    return ejecutar_local(
        consulta
    ).mappings().all()


def buscar_producto_activo_movimiento(id_producto):
    consulta = select(func.public.mov_producto_activo(bindparam("id_producto")).table_valued("id_producto", "codigo", "nombre", "unidad"))

    return ejecutar_local(
        consulta,
        {"id_producto": id_producto},
    ).mappings().first()


def proveedor_activo_movimiento_existe(id_proveedor):
    consulta = select(func.public.mov_proveedor_activo(bindparam("id_proveedor")))

    return bool(
        ejecutar_local(
            consulta,
            {"id_proveedor": id_proveedor},
        ).scalar()
    )


def generar_codigo_movimiento():
    ejecutar_local(
        select(func.public.mov_bloquear_codigo())
    )

    consulta = select(func.public.mov_siguiente_numero())

    siguiente_numero = int(
        ejecutar_local(consulta).scalar() or 1
    )

    return f"MI-{siguiente_numero:03d}"


def crear_cabecera_movimiento(
    codigo,
    tipo_movimiento,
    motivo_movimiento,
    fecha_movimiento,
    id_usuario,
    local_relacionado,
    id_proveedor,
    observacion,
):
    consulta = select(func.public.mov_crear_cabecera(bindparam("id_local_actual"), bindparam("codigo"), bindparam("tipo_movimiento"), bindparam("motivo_movimiento"), bindparam("fecha_movimiento"), bindparam("id_usuario"), bindparam("local_relacionado"), bindparam("id_proveedor"), bindparam("observacion")))

    return ejecutar_local(
        consulta,
        {
            "codigo": codigo,
            "tipo_movimiento": tipo_movimiento,
            "motivo_movimiento": motivo_movimiento,
            "fecha_movimiento": fecha_movimiento,
            "id_usuario": id_usuario,
            "local_relacionado": local_relacionado,
            "id_proveedor": id_proveedor,
            "observacion": observacion,
        },
    ).scalar_one()


def crear_detalle_movimiento(
    id_movimiento,
    id_producto,
    cantidad,
):
    exigir_registro_local("movimiento", id_movimiento)
    consulta = select(func.public.mov_crear_detalle(bindparam("id_movimiento"), bindparam("id_producto"), bindparam("cantidad")))

    ejecutar_local(
        consulta,
        {
            "id_movimiento": id_movimiento,
            "id_producto": id_producto,
            "cantidad": cantidad,
        },
    )


def buscar_movimiento_creado(id_movimiento):
    exigir_registro_local("movimiento", id_movimiento)
    consulta = select(func.public.mov_buscar_cabecera(bindparam("id_local_actual"), bindparam("id_movimiento")).table_valued("id_movimiento_inventario", "codigo", "tipo_movimiento", "motivo_movimiento", "fecha_movimiento", "local_relacionado", "id_proveedor", "proveedor", "observacion", "registrado_por"))

    return ejecutar_local(
        consulta,
        {"id_movimiento": id_movimiento},
    ).mappings().first()


def listar_detalles_movimiento_creado(id_movimiento):
    exigir_registro_local("movimiento", id_movimiento)
    consulta = select(func.public.mov_listar_detalles(bindparam("id_movimiento")).table_valued("id_producto", "codigo", "nombre", "unidad", "cantidad"))

    return ejecutar_local(
        consulta,
        {"id_movimiento": id_movimiento},
    ).mappings().all()

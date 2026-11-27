from sqlalchemy import bindparam, func, select

from app.core.local_scope import ejecutar_local, exigir_registro_local


def listar_pendientes_recepcion():
    consulta = select(func.public.recep_pendientes(bindparam("id_local_actual")).table_valued(
        'id_orden_compra', 'codigo_orden', 'estado_orden_compra', 'fecha_registro', 'id_proveedor',
        'proveedor', 'datos_comerciales', 'id_producto', 'codigo_producto', 'producto', 'categoria',
        'unidad', 'presentacion', 'cantidad_solicitada', 'cantidad_recibida', 'cantidad_pendiente',
    ))

    return ejecutar_local(consulta).mappings().all()


def bloquear_orden(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = select(func.public.recep_bloquear_orden(bindparam("id_orden"), bindparam("id_local_actual")).table_valued(
        'id_orden_compra', 'codigo', 'estado_orden_compra',
    ))
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).mappings().first()


def obtener_producto_pendiente(
    id_orden,
    id_proveedor,
    id_producto,
):
    exigir_registro_local("orden", id_orden)
    consulta = select(func.public.recep_producto_pendiente(bindparam("id_orden"), bindparam("id_proveedor"), bindparam("id_producto"), bindparam("id_local_actual")).table_valued(
        'id_producto', 'codigo', 'nombre', 'unidad', 'cantidad_solicitada', 'cantidad_recibida',
    ))
    return ejecutar_local(
        consulta,
        {
            "id_orden": id_orden,
            "id_proveedor": id_proveedor,
            "id_producto": id_producto,
        },
    ).mappings().first()


def factura_duplicada(id_proveedor, numero_factura):
    consulta = select(func.public.recep_factura_duplicada(bindparam("id_proveedor"), bindparam("numero_factura")))
    return bool(ejecutar_local(
        consulta,
        {
            "id_proveedor": id_proveedor,
            "numero_factura": numero_factura,
        },
    ).scalar())


def crear_factura_recepcion(
    id_orden,
    id_proveedor,
    numero_factura,
    fecha_recepcion,
    id_usuario,
):
    exigir_registro_local("orden", id_orden)
    consulta = select(func.public.recep_crear_factura(bindparam("id_orden"), bindparam("id_proveedor"), bindparam("numero_factura"), bindparam("fecha_recepcion"), bindparam("id_usuario")))
    return ejecutar_local(
        consulta,
        {
            "id_orden": id_orden,
            "id_proveedor": id_proveedor,
            "numero_factura": numero_factura,
            "fecha_recepcion": fecha_recepcion,
            "id_usuario": id_usuario,
        },
    ).scalar_one()


def crear_detalle_recepcion(
    id_factura,
    id_producto,
    cantidad,
):
    exigir_registro_local("factura", id_factura)
    ejecutar_local(
        select(func.public.recep_crear_detalle(bindparam("id_factura"), bindparam("id_producto"), bindparam("cantidad"))),
        {
            "id_factura": id_factura,
            "id_producto": id_producto,
            "cantidad": cantidad,
        },
    )


def orden_tiene_cantidades_pendientes(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = select(func.public.recep_orden_pendiente(bindparam("id_orden"), bindparam("id_local_actual")))
    return bool(ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).scalar())


def actualizar_estado_orden(id_orden, estado):
    exigir_registro_local("orden", id_orden)
    ejecutar_local(
        select(func.public.recep_actualizar_estado(bindparam("id_orden"), bindparam("estado"))),
        {"id_orden": id_orden, "estado": estado},
    )


def listar_historial_recepciones(
    fecha_desde=None,
    fecha_hasta=None,
    id_proveedor=None,
):
    consulta = select(func.public.recep_historial(bindparam("id_local_actual"), bindparam("fecha_desde"), bindparam("fecha_hasta"), bindparam("id_proveedor")).table_valued(
        'id_factura_recepcion', 'id_orden_compra', 'codigo_orden', 'estado_orden_compra',
        'total_factura', 'moneda', 'numero_factura', 'fecha_recepcion', 'id_proveedor', 'proveedor',
        'recibido_por', 'productos_recibidos', 'cantidad_total',
    ))
    return ejecutar_local(
        consulta,
        {
            "fecha_desde": fecha_desde,
            "fecha_hasta": fecha_hasta,
            "id_proveedor": id_proveedor,
        },
    ).mappings().all()


def obtener_factura_recepcion(id_factura, bloquear=False):
    exigir_registro_local("factura", id_factura)
    if bloquear:
        orden = ejecutar_local(select(func.public.recep_orden_de_factura(bindparam("id"))), {"id": id_factura}).scalar_one()
        bloquear_orden(orden)
        ejecutar_local(
            select(func.public.recep_bloquear_factura(bindparam("id_factura"), bindparam("id_local_actual"))),
            {"id_factura": id_factura},
        )
    consulta = select(func.public.recep_obtener_factura(bindparam("id_factura"), bindparam("id_local_actual")).table_valued(
        'id_factura_recepcion', 'id_orden_compra', 'codigo_orden', 'estado_orden_compra',
        'id_proveedor', 'proveedor', 'numero_factura', 'fecha_recepcion', 'recibido_por',
    ))
    return ejecutar_local(
        consulta,
        {"id_factura": id_factura},
    ).mappings().first()


def listar_detalles_factura(id_factura):
    exigir_registro_local("factura", id_factura)
    consulta = select(func.public.recep_detalles_factura(bindparam("id_factura"), bindparam("id_local_actual")).table_valued(
        'id_factura_recepcion_detalle', 'id_producto', 'codigo', 'nombre', 'unidad',
        'cantidad_recibida', 'cantidad_solicitada', 'recibido_otras_facturas',
    ))
    return ejecutar_local(
        consulta,
        {"id_factura": id_factura},
    ).mappings().all()


def factura_duplicada_excepto(
    id_proveedor,
    numero_factura,
    id_factura,
):
    exigir_registro_local("factura", id_factura)
    consulta = select(func.public.recep_factura_duplicada_excepto(bindparam("id_proveedor"), bindparam("numero_factura"), bindparam("id_factura")))
    return bool(ejecutar_local(
        consulta,
        {
            "id_proveedor": id_proveedor,
            "numero_factura": numero_factura,
            "id_factura": id_factura,
        },
    ).scalar())


def actualizar_factura_recepcion(
    id_factura,
    numero_factura,
    fecha_recepcion,
):
    exigir_registro_local("factura", id_factura)
    ejecutar_local(
        select(func.public.recep_actualizar_factura(bindparam("id_factura"), bindparam("numero_factura"), bindparam("fecha_recepcion"))),
        {
            "id_factura": id_factura,
            "numero_factura": numero_factura,
            "fecha_recepcion": fecha_recepcion,
        },
    )


def actualizar_cantidad_recepcion(id_detalle, cantidad):
    exigir_registro_local("detalle_recepcion", id_detalle)
    ejecutar_local(
        select(func.public.recep_actualizar_cantidad(bindparam("id_detalle"), bindparam("cantidad"))),
        {
            "id_detalle": id_detalle,
            "cantidad": cantidad,
        },
    )


def crear_historial_factura(
    id_factura,
    numero_anterior,
    numero_nuevo,
    fecha_anterior,
    fecha_nueva,
    id_usuario,
    motivo,
    observacion,
):
    exigir_registro_local("factura", id_factura)
    consulta = select(func.public.recep_crear_historial(bindparam("id_factura"), bindparam("numero_anterior"), bindparam("numero_nuevo"), bindparam("fecha_anterior"), bindparam("fecha_nueva"), bindparam("id_usuario"), bindparam("motivo"), bindparam("observacion")))
    return ejecutar_local(
        consulta,
        {
            "id_factura": id_factura,
            "numero_anterior": numero_anterior,
            "numero_nuevo": numero_nuevo,
            "fecha_anterior": fecha_anterior,
            "fecha_nueva": fecha_nueva,
            "id_usuario": id_usuario,
            "motivo": motivo,
            "observacion": observacion,
        },
    ).scalar_one()


def crear_historial_detalle(
    id_historial,
    id_producto,
    cantidad_anterior,
    cantidad_nueva,
):
    exigir_registro_local("historial_factura", id_historial)
    ejecutar_local(
        select(func.public.recep_crear_historial_detalle(bindparam("id_historial"), bindparam("id_producto"), bindparam("cantidad_anterior"), bindparam("cantidad_nueva"))),
        {
            "id_historial": id_historial,
            "id_producto": id_producto,
            "cantidad_anterior": cantidad_anterior,
            "cantidad_nueva": cantidad_nueva,
        },
    )


def calcular_totales_orden(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = select(func.public.recep_totales_orden(bindparam("id_orden"), bindparam("id_local_actual")).table_valued(
        'total_solicitado', 'total_recibido',
    ))
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).mappings().one()

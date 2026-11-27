from sqlalchemy import bindparam, func, select

from app.core.extensions import db

from app.core.local_scope import ejecutar_local, exigir_registro_local, local_actual, exigir_migracion_locales



def listar_productos_para_compra():
    from app.modules.inventarios.operativo import instalado

    local = local_actual()
    exigir_migracion_locales()
    if instalado():
        filas = func.public.compras_productos_sugeridos_operativo(local).table_valued(
            'id_producto', 'codigo', 'nombre', 'unidad', 'presentacion', 'stock_minimo', 'id_categoria', 'categoria', 'id_proveedor', 'proveedor', 'stock_actual', 'consumo_total', 'origen_consumo'
        )
    else:
        filas = func.public.compras_productos_sugeridos_historico(local).table_valued(
            'id_producto', 'codigo', 'nombre', 'unidad', 'presentacion', 'stock_minimo', 'id_categoria', 'categoria', 'id_proveedor', 'proveedor', 'stock_actual', 'consumo_total'
        )
    return db.session.execute(select(filas)).mappings().all()


def producto_activo_existe(id_producto):
    return bool(ejecutar_local(
        select(func.public.compras_producto_activo_existe(bindparam('id_producto'))),
        {"id_producto": id_producto},
    ).scalar())


def generar_codigo_orden():
    ejecutar_local(select(func.public.compras_bloquear_codigo()))
    numero = int(ejecutar_local(select(func.public.compras_siguiente_numero_orden())).scalar() or 1)
    return f"OC-{numero:03d}"


def crear_cabecera_orden(codigo, estado, id_usuario, fecha_registro):
    return ejecutar_local(
        select(func.public.compras_crear_cabecera_orden(bindparam('id_local_actual'), bindparam('codigo'), bindparam('estado'), bindparam('id_usuario'), bindparam('fecha_registro'))),
        {
            "codigo": codigo,
            "estado": estado,
            "id_usuario": id_usuario,
            "fecha_registro": fecha_registro,
        },
    ).scalar_one()


def crear_detalle_orden(id_orden, id_producto, cantidad_solicitada):
    exigir_registro_local("orden", id_orden)
    ejecutar_local(
        select(func.public.compras_crear_detalle_orden(bindparam('id_producto'), bindparam('id_orden'), bindparam('cantidad'), bindparam('id_local_actual'))),
        {
            "id_orden": id_orden,
            "id_producto": id_producto,
            "cantidad": cantidad_solicitada,
        },
    )


def listar_historial_ordenes(
    fecha_desde=None,
    fecha_hasta=None,
    estado=None,
):
    consulta = select(func.public.compras_listar_historial_ordenes(bindparam('id_local_actual'), bindparam('fecha_desde'), bindparam('fecha_hasta'), bindparam('estado')).table_valued(
            'id_orden_compra', 'codigo', 'estado_orden_compra', 'fecha_registro',
            'registrado_por', 'total_productos', 'productos_con_recepcion',
            'productos_completos', 'productos_pendientes', 'motivo_cierre',
            'fecha_modificacion', 'modificado_por'
        ))

    return ejecutar_local(
        consulta,
        {
            "fecha_desde": fecha_desde,
            "fecha_hasta": fecha_hasta,
            "estado": estado,
        },
    ).mappings().all()


def obtener_detalle_orden_historial(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = select(func.public.compras_obtener_detalle_orden_historial(bindparam('id_local_actual'), bindparam('id_orden')).table_valued(
            'id_orden_compra_detalle', 'id_producto', 'codigo', 'nombre', 'unidad',
            'id_proveedor', 'proveedor', 'cantidad_solicitada', 'cantidad_recibida',
            'cantidad_pendiente'
        ))
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).mappings().all()


def obtener_orden_historial(id_orden, bloquear=False):
    exigir_registro_local("orden", id_orden)
    consulta = select((func.public.compras_obtener_orden_historial_bloqueada if bloquear else func.public.compras_obtener_orden_historial)(bindparam('id_local_actual'), bindparam('id_orden')).table_valued(
            'id_orden_compra', 'codigo', 'estado_orden_compra', 'fecha_registro',
            'motivo_cierre'
        ))
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).mappings().first()


def obtener_total_recibido_orden(id_orden):
    exigir_registro_local("orden", id_orden)
    consulta = select(func.public.compras_obtener_total_recibido_orden(bindparam('id_local_actual'), bindparam('id_orden')))
    return ejecutar_local(
        consulta,
        {"id_orden": id_orden},
    ).scalar()


def guardar_historial_estado_orden(
    id_orden,
    estado_anterior,
    estado_nuevo,
    motivo,
    id_usuario,
):
    exigir_registro_local("orden", id_orden)
    ejecutar_local(
        select(func.public.compras_guardar_historial_estado_orden(bindparam('id_orden'), bindparam('estado_anterior'), bindparam('estado_nuevo'), bindparam('motivo'), bindparam('id_usuario'), bindparam('id_local_actual'))),
        {
            "id_orden": id_orden,
            "estado_anterior": estado_anterior,
            "estado_nuevo": estado_nuevo,
            "motivo": motivo,
            "id_usuario": id_usuario,
        },
    )


def enviar_orden_borrador(id_orden,id_usuario):
    exigir_registro_local('orden',id_orden)
    ejecutar_local(select(func.public.compras_enviar_orden_borrador(bindparam('usuario'), bindparam('id'), bindparam('id_local_actual'))),{'id':id_orden,'usuario':id_usuario})


def cambiar_estado_orden_historial(
    id_orden,
    estado,
    motivo,
    id_usuario,
):
    exigir_registro_local("orden", id_orden)
    ejecutar_local(
        select(func.public.compras_cambiar_estado_orden_historial(bindparam('estado'), bindparam('motivo'), bindparam('id_usuario'), bindparam('id_orden'), bindparam('id_local_actual'))),
        {
            "id_orden": id_orden,
            "estado": estado,
            "motivo": motivo,
            "id_usuario": id_usuario,
        },
    )



def estado_orden_valido(estado):
    consulta = select(func.public.compras_estado_orden_valido(estado))
    return bool(db.session.execute(consulta).scalar())

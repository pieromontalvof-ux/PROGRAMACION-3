from sqlalchemy import Numeric, bindparam, cast, func, select

from app.core.extensions import db

from app.core.local_scope import ejecutar_local, exigir_registro_local, local_actual, exigir_migracion_locales



def contar_productos_activos():
    consulta = select(func.public.inv_repository_contar_productos_activos().table_valued(
        'total'
    ))

    resultado = ejecutar_local(consulta).mappings().first()

    return int(resultado["total"] or 0)


def buscar_inventario_de_hoy():
    consulta = select(func.public.inv_repository_buscar_inventario_de_hoy(bindparam('id_local_actual')).table_valued(
        'id_inventario_cierre', 'fecha_inventario', 'estado_inventario', 'usuario_registro',
        'fecha_registro', 'observacion', 'productos_contados', 'usuario'
    ))

    return ejecutar_local(consulta).mappings().first()


def buscar_ultimo_inventario_cerrado():
    consulta = select(func.public.inv_repository_buscar_ultimo_inventario_cerrado(bindparam('id_local_actual')).table_valued(
        'id_inventario_cierre', 'fecha_inventario', 'estado_inventario', 'usuario_registro',
        'fecha_registro', 'observacion', 'productos_contados', 'usuario'
    ))

    return ejecutar_local(consulta).mappings().first()


def buscar_ultimos_inventarios(limite=5):
    consulta = select(func.public.inv_repository_buscar_ultimos_inventarios(bindparam('id_local_actual'), bindparam('limite')).table_valued(
        'id_inventario_cierre', 'fecha_inventario', 'estado_inventario', 'fecha_registro',
        'observacion', 'productos_contados', 'usuario'
    ))

    return ejecutar_local(
        consulta,
        {"limite": limite}
    ).mappings().all()


def consultar_stock_actual():
    from app.modules.inventarios.operativo import instalado

    local = local_actual()
    exigir_migracion_locales()
    if instalado():
        filas = func.public.inventario_stock_consulta_operativo(local).table_valued(
            'id_producto', 'codigo', 'nombre', 'unidad', 'id_categoria', 'categoria', 'stock_minimo', 'stock_maximo', 'fecha_ultimo_conteo', 'stock_ultimo_conteo', 'stock_actual', 'entradas_recepcion', 'entradas_movimiento', 'salidas_movimiento', 'estado_stock'
        )
    else:
        filas = func.public.inventario_stock_consulta_historico(local).table_valued(
            'id_producto', 'codigo', 'nombre', 'unidad', 'stock_minimo', 'id_categoria', 'categoria', 'fecha_ultimo_conteo', 'stock_ultimo_conteo', 'entradas_recepcion', 'entradas_movimiento', 'salidas_movimiento', 'stock_actual', 'estado_stock'
        )
    return db.session.execute(select(filas)).mappings().all()


def buscar_cabecera_inventario_actual():
    consulta = select(func.public.inv_repository_buscar_cabecera_inventario_actual(bindparam('id_local_actual')).table_valued(
        'id_inventario_cierre', 'fecha_inventario', 'estado_inventario', 'usuario_registro',
        'fecha_registro', 'observacion', 'usuario'
    ))

    return ejecutar_local(
        consulta
    ).mappings().first()


def consultar_productos_para_inventario(
    id_inventario_cierre=None
):
    if id_inventario_cierre is not None:
        exigir_registro_local("inventario", id_inventario_cierre)
    consulta = select(func.public.inv_repository_consultar_productos_para_inventario(bindparam('id_inventario_cierre')).table_valued(
        'id_producto', 'codigo', 'nombre', 'unidad', 'id_categoria', 'categoria',
        'stock_contado'
    ))

    return ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre
        }
    ).mappings().all()


def crear_inventario_actual(
    id_usuario,
    fecha_inventario
):
    consulta = select(func.public.inv_repository_crear_inventario_actual(bindparam('id_local_actual'), bindparam('fecha_inventario'), bindparam('id_usuario')))

    return ejecutar_local(
        consulta,
        {
            "id_usuario": id_usuario,
            "fecha_inventario":
                fecha_inventario,
        }
    ).scalar()


def producto_activo_existe(id_producto):
    consulta = select(func.public.inv_repository_producto_activo_existe(bindparam('id_producto')))

    return bool(
        ejecutar_local(
            consulta,
            {"id_producto": id_producto}
        ).scalar()
    )


def guardar_detalle_inventario(
    id_inventario_cierre,
    id_producto,
    stock_contado
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = select(func.public.inv_repository_guardar_detalle_inventario(bindparam('id_inventario_cierre'), bindparam('id_producto'), cast(bindparam('stock_contado'), Numeric)))

    ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre,
            "id_producto": id_producto,
            "stock_contado": stock_contado,
        }
    )


def eliminar_detalle_inventario(
    id_inventario_cierre,
    id_producto
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = select(func.public.inv_repository_eliminar_detalle_inventario(bindparam('id_inventario_cierre'), bindparam('id_producto')))

    ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre,
            "id_producto": id_producto,
        }
    )


def contar_detalles_inventario(
    id_inventario_cierre
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = select(func.public.inv_repository_contar_detalles_inventario(bindparam('id_inventario_cierre')))

    return int(
        ejecutar_local(
            consulta,
            {
                "id_inventario_cierre":
                    id_inventario_cierre
            }
        ).scalar() or 0
    )


def actualizar_estado_inventario(
    id_inventario_cierre,
    estado
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = select(func.public.inv_repository_actualizar_estado_inventario(bindparam('estado'), bindparam('id_inventario_cierre')))

    ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre,
            "estado": estado,
        }
    )


def buscar_inventario_por_fecha(fecha_inventario):
    consulta = select(func.public.inv_repository_buscar_inventario_por_fecha(bindparam('id_local_actual'), bindparam('fecha_inventario')).table_valued(
        'id_inventario_cierre', 'fecha_inventario', 'estado_inventario', 'usuario_registro',
        'fecha_registro', 'observacion', 'usuario'
    ))

    return ejecutar_local(
        consulta,
        {
            "fecha_inventario":
                fecha_inventario
        }
    ).mappings().first()


def eliminar_inventario_provisional(
    id_inventario_cierre
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta_detalles = select(func.public.inv_repository_eliminar_inventario_provisional_1(bindparam('id_inventario_cierre')))

    consulta_cabecera = select(func.public.inv_repository_eliminar_inventario_provisional_2(bindparam('id_inventario_cierre')))

    parametros = {
        "id_inventario_cierre":
            id_inventario_cierre
    }

    ejecutar_local(
        consulta_detalles,
        parametros,
    )

    resultado = ejecutar_local(
        consulta_cabecera,
        parametros,
    )

    return bool(resultado.scalar())


def cerrar_inventario_en_base_datos(
    id_inventario_cierre
):
    exigir_registro_local("inventario", id_inventario_cierre)
    consulta = select(func.public.inv_repository_cerrar_inventario_en_base_datos(bindparam('id_inventario_cierre')))

    return ejecutar_local(
        consulta,
        {
            "id_inventario_cierre":
                id_inventario_cierre
        }
    ).scalar()


def listar_inventarios_para_revision():
    consulta = select(func.public.inv_repository_listar_inventarios_para_revision(bindparam('id_local_actual')).table_valued(
        'id_inventario_cierre', 'fecha_inventario', 'estado_inventario', 'fecha_registro',
        'usuario_registro', 'registrado_por', 'usuario_revision', 'revisado_por',
        'motivo_revision', 'observacion', 'productos_contados', 'productos_en_cero',
        'productos_con_existencia', 'total_productos_actuales'
    ))

    return ejecutar_local(
        consulta
    ).mappings().all()


def buscar_inventario_cerrado_por_id(id_inventario):
    exigir_registro_local("inventario", id_inventario)
    consulta = select(func.public.inv_repository_buscar_inventario_cerrado_por_id(bindparam('id_local_actual'), bindparam('id_inventario')).table_valued(
        'id_inventario_cierre', 'fecha_inventario', 'estado_inventario', 'fecha_registro',
        'usuario_registro', 'registrado_por', 'usuario_revision', 'revisado_por',
        'motivo_revision', 'observacion'
    ))

    return ejecutar_local(
        consulta,
        {"id_inventario": id_inventario},
    ).mappings().first()


def listar_productos_revision(id_inventario):
    exigir_registro_local("inventario", id_inventario)
    filas = func.public.inventario_productos_revision(local_actual(), id_inventario).table_valued(
        'id_producto', 'codigo', 'producto', 'categoria', 'unidad', 'stock_minimo', 'activo', 'stock_contado', 'fue_contado'
    )
    return db.session.execute(select(filas)).mappings().all()


def actualizar_revision_inventario(
    id_inventario,
    id_usuario_revision,
    motivo_revision,
    observacion,
):
    exigir_registro_local("inventario", id_inventario)
    consulta = select(func.public.inv_repository_actualizar_revision_inventario(bindparam('id_usuario_revision'), bindparam('motivo_revision'), bindparam('observacion'), bindparam('id_inventario')))

    return ejecutar_local(
        consulta,
        {
            "id_inventario": id_inventario,
            "id_usuario_revision": id_usuario_revision,
            "motivo_revision": motivo_revision,
            "observacion": observacion,
        },
    ).scalar_one_or_none()


def bloquear_inventario_cerrado(id_inventario):
    exigir_registro_local("inventario", id_inventario)
    consulta = select(func.public.inv_repository_bloquear_inventario_cerrado(bindparam('id_local_actual'), bindparam('id_inventario')).table_valued(
        'id_inventario_cierre', 'fecha_inventario', 'estado_inventario'
    ))

    return ejecutar_local(
        consulta,
        {"id_inventario": id_inventario},
    ).mappings().first()


def buscar_producto_para_correccion(
    id_inventario,
    id_producto,
):
    exigir_registro_local("inventario", id_inventario)
    consulta = select(func.public.inv_repository_buscar_producto_para_correccion(bindparam('id_inventario'), bindparam('id_producto')).table_valued(
        'id_producto', 'codigo', 'nombre', 'activo', 'id_inventario_cierre_detalle',
        'stock_contado'
    ))

    return ejecutar_local(
        consulta,
        {
            "id_inventario": id_inventario,
            "id_producto": id_producto,
        },
    ).mappings().first()


def crear_cabecera_correccion(
    id_inventario,
    id_usuario,
    motivo,
    observacion,
):
    exigir_registro_local("inventario", id_inventario)
    consulta = select(func.public.inv_repository_crear_cabecera_correccion(bindparam('id_inventario'), bindparam('id_usuario'), bindparam('motivo'), bindparam('observacion')))

    return ejecutar_local(
        consulta,
        {
            "id_inventario": id_inventario,
            "id_usuario": id_usuario,
            "motivo": motivo,
            "observacion": observacion,
        },
    ).scalar_one()


def crear_detalle_correccion(
    id_correccion,
    id_producto,
    stock_anterior,
    stock_nuevo,
):
    exigir_registro_local("correccion", id_correccion)
    consulta = select(func.public.inv_repository_crear_detalle_correccion(bindparam('id_correccion'), bindparam('id_producto'), cast(bindparam('stock_anterior'), Numeric), cast(bindparam('stock_nuevo'), Numeric)))

    ejecutar_local(
        consulta,
        {
            "id_correccion": id_correccion,
            "id_producto": id_producto,
            "stock_anterior": stock_anterior,
            "stock_nuevo": stock_nuevo,
        },
    )


def aplicar_stock_corregido(
    id_inventario,
    id_producto,
    stock_nuevo,
):
    exigir_registro_local("inventario", id_inventario)
    parametros = {
        "id_inventario": id_inventario,
        "id_producto": id_producto,
        "stock_nuevo": stock_nuevo,
    }

    if stock_nuevo is None:
        consulta = select(func.public.inv_repository_aplicar_stock_corregido_1(bindparam('id_inventario'), bindparam('id_producto')))
    else:
        consulta = select(func.public.inv_repository_aplicar_stock_corregido_2(bindparam('id_inventario'), bindparam('id_producto'), cast(bindparam('stock_nuevo'), Numeric)))

    ejecutar_local(consulta, parametros)


def listar_historial_correcciones(id_inventario):
    exigir_registro_local("inventario", id_inventario)
    consulta = select(func.public.inv_repository_listar_historial_correcciones(bindparam('id_inventario')).table_valued(
        'id_inventario_cierre_correccion', 'fecha_correccion', 'motivo_correccion',
        'observacion', 'corregido_por', 'id_producto', 'codigo', 'producto', 'unidad',
        'stock_anterior', 'stock_nuevo'
    ))

    return ejecutar_local(
        consulta,
        {"id_inventario": id_inventario},
    ).mappings().all()

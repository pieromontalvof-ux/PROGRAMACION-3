from sqlalchemy import func, select

from app.core.extensions import db


def filas(funcion):
    return [dict(fila) for fila in db.session.execute(select(funcion)).mappings()]


def listar_promociones():
    return filas(func.public.promo_listar().table_valued(
        'id_promocion', 'codigo', 'nombre', 'precio', 'hora_inicio', 'hora_fin', 'activo',
    ))


def listar_grupos_promocion():
    return filas(func.public.promo_listar_grupos().table_valued(
        'id_promocion_grupo', 'id_promocion', 'cantidad_elegir', 'permite_repetir',
    ))


def listar_opciones_promocion():
    return filas(func.public.promo_listar_opciones().table_valued(
        'id_promocion_opcion', 'id_promocion_grupo', 'id_presentacion_venta',
        'id_item_carta', 'codigo_item', 'item_carta', 'tipo', 'id_categoria_carta',
        'categoria_carta', 'contenido', 'unidad', 'precio_individual', 'presentacion_activa',
    ))


def listar_reposiciones_promocion():
    return filas(func.public.promo_listar_reposiciones().table_valued(
        'id_promocion', 'id_presentacion_venta',
    ))

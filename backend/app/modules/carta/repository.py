from sqlalchemy import func, select

from app.core.extensions import db


def listar_categorias_carta_detalladas():
    categorias = func.public.carta_categorias_detalladas().table_valued(
        'id_categoria_carta', 'nombre', 'prefijo', 'siguiente_numero', 'activo',
        'total_items', 'items_activos', 'items_inactivos', 'total_presentaciones',
        'presentaciones_activas', 'presentaciones_inactivas',
    )
    filas = db.session.execute(select(categorias).order_by(categorias.c.nombre)).mappings()
    return [dict(fila) for fila in filas]


def listar_presentaciones_venta_detalladas():
    filas = func.public.carta_presentaciones_detalladas().table_valued(
        'id_presentacion_venta', 'id_item_carta', 'codigo_item', 'item', 'tipo',
        'id_categoria_carta', 'categoria', 'id_menaje', 'menaje', 'contenido', 'unidad', 'precio',
        'activo',
    )
    return [dict(fila) for fila in db.session.execute(select(filas).order_by(filas.c.categoria, filas.c.item, filas.c.contenido, filas.c.precio)).mappings()]


def listar_menajes_detallados():
    filas = func.public.carta_menajes_detallados().table_valued(
        'id_menaje', 'nombre', 'activo', 'capacidad', 'unidad_capacidad', 'diametro_cm',
        'altura_cm', 'largo_cm', 'ancho_cm', 'origen_medidas', 'total_presentaciones',
        'presentaciones_activas', 'presentaciones_inactivas', 'total_items', 'items',
    )
    return [dict(fila) for fila in db.session.execute(select(filas).order_by(filas.c.nombre)).mappings()]


def perfil_administra_catalogos_carta(id_perfil):
    consulta = select(func.public.carta_admin_perfil_autorizado(id_perfil))
    return bool(db.session.execute(consulta).scalar())

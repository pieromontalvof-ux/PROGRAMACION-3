from sqlalchemy import func, select

from app.core.extensions import db


def listar_recetas_detalladas():
    consulta = select(func.public.receta_listar().table_valued('id_receta', 'id_presentacion_venta', 'instrucciones', 'activo', 'id_item_carta', 'codigo_item', 'item_carta', 'tipo_item', 'id_categoria_carta', 'categoria_carta', 'contenido', 'unidad_presentacion', 'precio', 'id_menaje', 'total_componentes', 'componentes', 'id_grupo_salsa', 'cantidad_maxima', 'permite_repetir', 'grupo_salsa_activo', 'opciones_salsa'))

    resultado = db.session.execute(consulta)
    return [dict(fila) for fila in resultado.mappings().all()]

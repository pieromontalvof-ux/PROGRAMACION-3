from sqlalchemy import func, select

from app.core.extensions import db


def listar_subproductos_detallados():
    consulta = select(func.public.produccion_listar_subproductos().table_valued(
        'id_subproducto', 'codigo', 'nombre', 'rendimiento', 'unidad', 'activo', 'instruccion', 'total_ingredientes', 'ingredientes',
    ))

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]


def listar_grupos_salsa_detallados():
    consulta = select(func.public.produccion_listar_grupos_salsa().table_valued(
        'id_grupo_salsa', 'id_presentacion_venta', 'cantidad_maxima', 'activo', 'id_item_carta', 'codigo_item', 'item_carta', 'categoria_carta', 'contenido', 'unidad_presentacion', 'precio', 'total_opciones', 'opciones',
    ))

    resultado = db.session.execute(consulta)

    return [
        dict(fila)
        for fila in resultado.mappings().all()
    ]
